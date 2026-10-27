# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

RSpec.describe "The assistant's line under an object's title", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking forums wiki assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant view_wiki_pages])
  end
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:) }
  shared_let(:version) { create(:version, project:) }

  def signal_for(user, subject, headline, **payload)
    Assistant::Signal.create!(detector: "stalled", fingerprint: SecureRandom.hex(4), recipient: user, project:, subject:,
                              channel: "inline", deliver_at: Time.current,
                              payload: { "headline" => headline, "because" => ["x"] }.merge(payload))
  end

  before { Assistant::Membership.ensure_member!(project) }

  context "on a work package" do
    before { login_as(sam) }

    it "says the most important thing in one line and folds the rest" do
      signal_for(sam, work_package, "No movement for 5 days").update!(score: 80)
      signal_for(sam, work_package, "Estimate looks short")

      get assistant_work_package_line_path(work_package)

      line = response.parsed_body.at_css("[data-test-selector='assistant-object-line']")
      expect(line.css(".assistant-notice--headline").first.text).to include("No movement for 5 days")
      expect(line.at_css("[data-test-selector='assistant-object-line-more'] summary").text).to include("1")
    end

    it "keeps other people's signals and the ones under a comment out of it" do
      signal_for(ben, work_package, "Only for Ben")
      signal_for(sam, work_package, "Under a comment", "source_gid" => work_package.to_gid.to_s)

      get assistant_work_package_line_path(work_package)

      expect(response.body).to eq(%(<turbo-frame id="assistant-wp-line-frame"></turbo-frame>))
    end

    it "waits there for a notification that has been delivered, and not before" do
      signal_for(sam, work_package, "Delivered nudge").update!(channel: "notification", state: "delivered")
      signal_for(sam, work_package, "Not yet sent", score: 90).update!(channel: "notification", state: "pending")

      get assistant_work_package_line_path(work_package)

      expect(response.parsed_body.css(".assistant-notice--headline").map(&:text)).to eq(["Delivered nudge"])
    end

    it "takes no room where the assistant is off" do
      other = create(:project, enabled_module_names: %w[work_package_tracking])
      create(:member, project: other, principal: sam, roles: [role])
      wp = create(:work_package, project: other)
      Assistant::Signal.create!(detector: "stalled", fingerprint: "o", recipient: sam, project: other, subject: wp,
                                channel: "inline", deliver_at: Time.current, payload: { "headline" => "Hidden" })

      get assistant_work_package_line_path(wp)

      expect(response.body).to eq(%(<turbo-frame id="assistant-wp-line-frame"></turbo-frame>))
    end

    it "is gone after the person has dealt with it, wherever they did" do
      signal = signal_for(sam, work_package, "No movement for 5 days")

      patch assistant_signal_path(signal), params: { outcome: "rejected" },
                                           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      get assistant_work_package_line_path(work_package)

      expect(response.body).to eq(%(<turbo-frame id="assistant-wp-line-frame"></turbo-frame>))
    end
  end

  context "on a version page" do
    before { login_as(sam) }

    it "puts the line between the header and the widgets, only for the person it is meant for" do
      signal_for(sam, version, "Three items have no date")

      get version_path(version)
      line = response.parsed_body.at_css("[data-test-selector='assistant-object-line']")
      expect(line.css(".assistant-notice--headline").first.text).to include("Three items have no date")
      expect(line.previous_element["class"]).to include("PageHeader")
      expect(line.next_element["class"]).to include("widget-boxes")

      login_as(ben)
      get version_path(version)
      expect(response.parsed_body.at_css("[data-test-selector='assistant-object-line']")).to be_nil
    end
  end

  describe "the mark in lists" do
    before { login_as(sam) }

    it "is a link on the work package only for the person it is meant for" do
      signal_for(sam, work_package, "No movement for 5 days")

      get "/api/v3/work_packages/#{work_package.id}", headers: { "Accept" => "application/json" }
      expect(JSON.parse(response.body).dig("_links", "assistantNotice", "title")).to eq("No movement for 5 days") # rubocop:disable Rails/ResponseParsedBody

      login_as(ben)
      get "/api/v3/work_packages/#{work_package.id}", headers: { "Accept" => "application/json" }
      expect(JSON.parse(response.body)["_links"]).not_to have_key("assistantNotice") # rubocop:disable Rails/ResponseParsedBody
    end
  end
end
