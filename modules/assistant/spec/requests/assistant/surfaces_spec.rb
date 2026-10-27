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

RSpec.describe "Where the assistant shows up", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_package_comments use_assistant])
  end
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Search API") }

  before { login_as(sam) }

  describe "an assistant notification" do
    let(:notification) do
      Notification.create!(recipient: sam, actor: Assistant.user, resource: work_package, reason: :assistant,
                           subject: "Search API is late", read_ian: false)
    end
    let!(:signal) do
      Assistant::Signal.create!(detector: "stalled", fingerprint: "n", recipient: sam, project:, subject: work_package,
                                channel: "notification", state: "delivered", score: 50,
                                deliver_at: 1.minute.ago, delivered_at: Time.current,
                                payload: { "headline" => "Search API has not moved for 6 working days",
                                           "notification_id" => notification.id })
    end

    it "tells the notification center what it is about, and where to act on it" do
      get assistant_notification_path(notification, format: :json)

      expect(response.parsed_body).to include("headline" => "Search API has not moved for 6 working days",
                                              "why" => I18n.t("assistant.notice.why.leads", name: project.name), "url" => work_package_path(work_package))
      expect(signal.reload.seen_at).to be_present
    end

    it "takes the person there" do
      get assistant_notification_path(notification)

      expect(response).to redirect_to(work_package_path(work_package))
    end

    it "is only for its recipient" do
      login_as(create(:user))
      get assistant_notification_path(notification, format: :json)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the answer being written" do
    let(:conversation) { Assistant::Conversation.create!(user: sam, project:, context: work_package) }
    let(:message) { conversation.messages.create!(role: "assistant", content: "It can, if #75", status: "streaming") }

    it "gives the text from where the browser is, so nothing is repeated" do
      get assistant_conversation_message_path(conversation, message, format: :json, offset: 8)

      expect(response.parsed_body).to include("status" => "streaming", "offset" => 8, "content" => "if #75", "length" => 14)
    end

    it "subscribes to the conversation's signed stream while writing" do
      get assistant_conversation_message_path(conversation, message)

      expect(response.body).to include("assistant--message-stream")
      expect(response.body).to include(Turbo::StreamsChannel.signed_stream_name(conversation))
    end
  end

  describe "a change proposed in a comment" do
    let(:journal) do
      work_package.add_journal(user: sam, notes: "Let's push this a week")
      work_package.save_journals
      work_package.journals.last
    end

    it "offers its options under the comment, to the person who said it" do
      action = Assistant::Action.create!(kind: "said_change", title: "Move #{work_package.id} by 5 working days", tier: "t2",
                                         status: "proposed", project:, subject: work_package, on_behalf_of: sam,
                                         plan: { "steps" => [] }, preview: { "success" => true })
      Assistant::Signal.create!(detector: "said_change", fingerprint: "j", recipient: sam, project:, subject: work_package,
                                action:, channel: "inline", state: "pending", score: 30, deliver_at: Time.current,
                                payload: { "headline" => "You proposed: move by a week", "source_gid" => journal.to_gid.to_s,
                                           "options" => [{ "label" => action.title, "action_id" => action.id }] })

      html = ApplicationController.render(Assistant::SourceSignalsComponent.new(source: journal, user: sam), layout: false)
      expect(html).to include("You proposed: move by a week")
      expect(html).to include("assistant-action-approve").or include(%(data-assistant-action-id="#{action.id}"))

      expect(Assistant::SourceSignalsComponent.signals_for(journal, create(:user))).to be_empty
    end
  end
end
