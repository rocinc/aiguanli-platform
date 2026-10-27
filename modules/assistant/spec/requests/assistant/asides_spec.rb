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

RSpec.describe "The assistant's side notes at a decision", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_packages manage_versions use_assistant])
  end
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Search index rebuild for the knowledge base") }

  before do
    Assistant::Membership.ensure_member!(project)
    login_as(sam)
  end

  def aside_signal_for(user, subject, headline, until_at: 5.minutes.from_now)
    Assistant::Signal.create!(detector: "assignee_change_load", fingerprint: SecureRandom.hex(4), recipient: user, project:,
                              subject:, channel: "inline", deliver_at: Time.current,
                              payload: { "headline" => headline, "because" => ["x"], "aside_until" => until_at.iso8601 })
  end

  describe "under a work package right after it was saved" do
    it "says the one thing and takes the room of nothing else" do
      aside_signal_for(sam, work_package, "#1 goes to Ben, who is 4 h over")

      get assistant_work_package_aside_path(work_package)

      frame = response.parsed_body.at_css("turbo-frame#assistant-wp-aside-frame")
      expect(frame.at_css(".assistant-notice--headline").text).to include("who is 4 h over")
      get assistant_work_package_line_path(work_package)
      expect(response.body).to eq(%(<turbo-frame id="assistant-wp-line-frame"></turbo-frame>))
    end

    it "is an empty frame when the moment has passed, for someone else's note, or when there is none" do
      aside_signal_for(sam, work_package, "Too late", until_at: 1.minute.ago)
      aside_signal_for(ben, work_package, "Only for Ben")

      get assistant_work_package_aside_path(work_package)

      expect(response.body).to eq(%(<turbo-frame id="assistant-wp-aside-frame"></turbo-frame>))
    end

    it "is not shown for a work package the person cannot see" do
      hidden = create(:work_package, project: create(:project))

      get assistant_work_package_aside_path(hidden)

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "beside the field that was changed" do
    def field_signal(field, headline)
      Assistant::Signal.create!(detector: "assignee_change_load", fingerprint: SecureRandom.hex(4), recipient: sam, project:, subject: work_package,
                                channel: "inline", deliver_at: Time.current,
                                payload: { "headline" => headline, "because" => ["x"], "field" => field, "aside_until" => 5.minutes.from_now.iso8601 })
    end

    it "is said next to that field only" do
      field_signal("assignee", "#1 goes to Ben, who is 4 h over")

      get assistant_work_package_field_aside_path(work_package, field: "assignee")
      expect(response.parsed_body.at_css("turbo-frame#assistant-wp-field-aside-assignee .assistant-notice--headline").text).to include("4 h over")

      get assistant_work_package_field_aside_path(work_package, field: "status")
      expect(response.body).to eq(%(<turbo-frame id="assistant-wp-field-aside-status"></turbo-frame>))
    end

    it "leaves the header to a field that is not on the page" do
      field_signal("assignee", "#1 goes to Ben, who is 4 h over")

      get assistant_work_package_aside_path(work_package, placed: "assignee")
      expect(response.body).to eq(%(<turbo-frame id="assistant-wp-aside-frame"></turbo-frame>))

      get assistant_work_package_aside_path(work_package, placed: "status")
      expect(response.parsed_body.at_css("turbo-frame#assistant-wp-aside-frame .assistant-notice--headline").text).to include("4 h over")
    end

    it "answers nothing for a row that has no slot" do
      get assistant_work_package_field_aside_path(work_package, field: "subject")

      expect(response).to have_http_status(:no_content)
    end
  end

  describe "under the title of a work package being written" do
    def duplicate_aside(subject)
      get assistant_duplicate_aside_path, params: { project_id: project.id, type_id: work_package.type_id, subject: }
      response.parsed_body.at_css("turbo-frame#assistant-wp-aside-frame")
    end

    it "names the existing one it may repeat" do
      frame = duplicate_aside("Search index rebuild for knowledge base")

      expect(frame.at_css(".assistant-notice--headline").text).to include("##{work_package.id}")
    end

    it "stays empty for a title that matches nothing, or is not written yet" do
      expect(duplicate_aside("Completely different matter altogether").children).to be_empty
      expect(duplicate_aside("Sea").children).to be_empty
    end

    it "is told once and then respects being turned off" do
      duplicate_aside("Search index rebuild for knowledge base")
      signal = Assistant::Signal.find_by!(recipient: sam, detector: "possible_duplicate")

      Assistant::Notice::Controls.new(signal, sam).mute("all")

      expect(duplicate_aside("Search index rebuild for knowledge base").children).to be_empty
    end
  end

  describe "beside the release date of a version" do
    shared_let(:version) { create(:version, project:, effective_date: Date.new(2026, 12, 31)) }

    before do
      late = create(:work_package, project:, subject: "Late item", due_date: Date.new(2026, 12, 20),
                                   start_date: Date.new(2026, 12, 1))
      WorkPackageVersion.create!(work_package: late, version:, kind: "target")
    end

    it "names what no longer fits once the date moves before it" do
      get assistant_version_date_aside_path(version), params: { effective_date: "2026-12-10" }

      frame = response.parsed_body.at_css("turbo-frame#assistant-version-aside-frame")
      expect(frame.at_css(".assistant-notice--headline").text).to include("12")
    end

    it "is empty when everything still fits, or the date is not valid" do
      get assistant_version_date_aside_path(version), params: { effective_date: "2027-02-01" }
      expect(response.parsed_body.at_css("turbo-frame#assistant-version-aside-frame").children).to be_empty

      get assistant_version_date_aside_path(version), params: { effective_date: "not a date" }
      expect(response.parsed_body.at_css("turbo-frame#assistant-version-aside-frame").children).to be_empty
    end
  end
end
