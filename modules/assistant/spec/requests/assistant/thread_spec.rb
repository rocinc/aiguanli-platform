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

RSpec.describe "Talking about one notice, draft or receipt", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Search API") }

  let(:signal) do
    Assistant::Signal.create!(detector: "idle_capacity", fingerprint: "t-#{SecureRandom.hex(3)}", recipient: sam, project:,
                              subject: work_package, channel: "inline", deliver_at: Time.current, state: "pending",
                              payload: { "headline" => "Search API has had no owner for 26 days", "because" => ["No owner for 26 days"],
                                         "options" => [], "nature" => "object" })
  end
  let(:gid) { signal.to_gid.to_s }
  let(:executed) do
    Assistant::Action.create!(kind: "reschedule", title: "Move Search API", tier: "t1", status: "executed", project:, subject: work_package,
                              on_behalf_of: sam, decided_by: sam, executed_at: Time.current,
                              plan: { "steps" => [{ "op" => "update_work_package", "type" => "WorkPackage", "id" => work_package.id,
                                                    "attributes" => { "due_date" => "2026-10-20" } }] })
  end

  describe "the panel" do
    before { login_as(sam) }

    it "opens on the notice, says what it is about and offers three questions above the input" do
      get assistant_panel_path(context: gid)

      page = response.parsed_body
      expect(page.at_css("[data-test-selector='assistant-panel-context']").text.squish).to include("Search API has had no owner")
      expect(page.css("[data-test-selector='assistant-panel-chip']").size).to eq(3)
      expect(page.at_css("[data-test-selector='assistant-panel-context-remove']")).to be_nil
      expect(page.at_css("input[name='context']")["value"]).to eq(gid)
      expect(page.at_css("[data-test-selector='assistant-panel-chips'] ~ .assistant-panel--field #assistant-panel-input")).to be_present
    end

    it "offers other questions for a receipt" do
      get assistant_panel_path(context: executed.to_gid.to_s)

      expect(response.parsed_body.css("[data-test-selector='assistant-panel-chip']").size).to eq(2)
    end

    it "starts the conversation on the notice and keeps it there" do
      allow(Assistant::Reasoning::Turn).to receive(:start) do |conversation, _message|
        conversation.messages.create!(role: "assistant", content: "", status: "streaming")
      end

      post assistant_conversations_path, params: { context: gid, content: "What if we postpone it?" }

      expect(Assistant::Conversation.last).to have_attributes(user: sam, context: signal, project:)
      expect(response.parsed_body.css("[data-test-selector='assistant-panel-chip']")).to be_empty
    end
  end

  describe "someone else's" do
    before { login_as(ben) }

    it "is not found, and does not say what it was about" do
      get assistant_panel_path(context: gid)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include("no owner for 26 days")
    end

    it "cannot be talked about on a made-up conversation either" do
      conversation = Assistant::Conversation.create!(user: sam, context: signal, project:, origin: "panel")

      get sync_assistant_conversation_path(conversation)

      expect(response).to have_http_status(:not_found)
    end

    it "cannot start a conversation about a receipt that is not theirs" do
      post assistant_conversations_path, params: { context: executed.to_gid.to_s, content: "Why?" }

      expect(response).to have_http_status(:not_found)
      expect(Assistant::Conversation.count).to eq(0)
    end
  end

  describe "after an answer settled" do
    let(:conversation) { Assistant::Conversation.create!(user: sam, context: signal, project:, origin: "panel") }

    before { login_as(sam) }

    it "says nothing when the conversation changed nothing" do
      get sync_assistant_conversation_path(conversation), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:no_content)
      expect(signal.reload.outcome).to be_nil
    end

    it "brings every copy of the notice up to date when the person went ahead on its object" do
      conversation.messages.create!(role: "assistant", content: "Done", status: "done",
                                    cards: [{ "type" => "action", "action_id" => executed.id }])

      get sync_assistant_conversation_path(conversation), headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(response.body.scan("<turbo-stream").size).to eq(Assistant::NoticeComponent::DENSITIES.size)
      expect(signal.reload.outcome).to eq("resolved")
      expect(signal.payload["stale_reason"]).to include("##{work_package.id}")
    end
  end
end
