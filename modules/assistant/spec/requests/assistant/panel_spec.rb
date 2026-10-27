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

RSpec.describe "The conversation panel", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Search API") }

  before { login_as(sam) }

  it "opens on the object the page is about" do
    get assistant_panel_path(context: work_package.to_gid.to_s)

    expect(response.body).to include(%(<turbo-frame id="assistant-panel-frame">))
    expect(response.body).to include("##{work_package.id} Search API")
    expect(response.body).to include("Ask me anything about this project")
    expect(response.body).not_to include("Can this still make it in time?")
    expect(response.parsed_body.at_css("[data-test-selector='assistant-panel-stop']")).to have_attribute("hidden")
  end

  it "starts a conversation about it and shows the answer being written" do
    allow(Assistant::Reasoning::Turn).to receive(:start) do |conversation, _message|
      conversation.messages.create!(role: "assistant", content: "Looking at #", status: "streaming")
    end

    post assistant_conversations_path, params: { context: work_package.to_gid.to_s, content: "Can this make it?" }

    conversation = Assistant::Conversation.last
    expect(conversation).to have_attributes(user: sam, context: work_package, project:)
    expect(response.body).to include("Can this make it?")
    expect(response.body).to include(%(aria-busy="true"))
    expect(response.body).to include("assistant--message-stream")

    streaming = conversation.messages.find_by(status: "streaming")
    streaming.update!(content: "It can, if **#75** starts Monday.", status: "done")
    get assistant_conversation_message_path(conversation, streaming)

    expect(response.body).not_to include(%(aria-busy="true"))
    expect(response.body).to include("<strong>#75</strong>").or include("<strong>")
  end

  it "opens a conversation by its id, whatever page it is asked from" do
    conversation = Assistant::Conversation.create!(user: sam, project:, context: project, title: "Welcome")
    conversation.messages.create!(role: "assistant", content: "Here is what is going on.", status: "done")

    get assistant_panel_path(conversation_id: conversation.id)

    expect(response.body).to include("Here is what is going on.")
    expect(response.body).to include(project.name)
  end

  it "does not open someone else's conversation by its id" do
    other = Assistant::Conversation.create!(user: create(:user), project:)
    other.messages.create!(role: "assistant", content: "Private", status: "done")

    get assistant_panel_path(conversation_id: other.id)

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include("Private")
  end

  it "does not let one person read another's conversation" do
    other = Assistant::Conversation.create!(user: create(:user), project:)
    message = other.messages.create!(role: "assistant", content: "Private", status: "done")

    get assistant_conversation_message_path(other, message)

    expect(response).to have_http_status(:not_found)
  end

  it "takes the work package from the page's address when no context is given" do
    get assistant_panel_path(work_package_id: work_package.id)

    expect(response.body).to include("##{work_package.id} Search API")
    expect(response.body).to include("assistant-panel-context-remove")
  end

  it "lists the person's earlier conversations in the panel, and starts a new one on request" do
    conversation = Assistant::Conversation.create!(user: sam, project:, context: work_package, title: "Earlier question")
    conversation.messages.create!(role: "user", content: "Earlier question", status: "done")

    get assistant_panel_path(context: work_package.to_gid.to_s, fresh: 1)

    expect(response.body).to include("assistant-panel-history", "Earlier question")
    expect(response.body).not_to include("assistant_messages_#{conversation.id}")
  end

  it "stops an answer being written and says so" do
    conversation = Assistant::Conversation.create!(user: sam, project:, context: work_package)
    answer = conversation.messages.create!(role: "assistant", content: "It can, if", status: "streaming")

    post assistant_stop_conversation_message_path(conversation, answer)

    expect(response).to have_http_status(:no_content)
    expect(answer.reload).to have_attributes(status: "stopped", content: "It can, if")
    get assistant_conversation_message_path(conversation, answer)
    expect(response.body).to include("Stopped.")
  end

  it "does not stop someone else's answer" do
    other = Assistant::Conversation.create!(user: create(:user), project:)
    answer = other.messages.create!(role: "assistant", content: "Private", status: "streaming")

    post assistant_stop_conversation_message_path(other, answer)

    expect(response).to have_http_status(:not_found)
    expect(answer.reload.status).to eq("streaming")
  end

  it "offers work packages, people and versions to refer to" do
    get assistant_references_path(context: work_package.to_gid.to_s, q: "Search", trigger: "@"), as: :json

    expect(response.parsed_body).to include(a_hash_including("kind" => "work_package", "text" => "##{work_package.id}"))

    get assistant_references_path(context: work_package.to_gid.to_s, q: sam.firstname, trigger: "@"), as: :json
    expect(response.parsed_body).to include(a_hash_including("kind" => "user", "text" => "@#{sam.name}"))

    get assistant_references_path(context: work_package.to_gid.to_s, q: sam.firstname, trigger: "#"), as: :json
    expect(response.parsed_body.pluck("kind")).not_to include("user")
  end

  it "offers nothing outside the projects the assistant is on for the person" do
    hidden = create(:work_package, project: create(:project))

    get assistant_references_path(q: hidden.id.to_s, trigger: "#"), as: :json

    expect(response.parsed_body).to eq([])
  end

  it "renders the drawer and the header button on every page" do
    get my_page_path

    expect(response.body).to include("assistant-panel-dialog")
    expect(response.body).to include("assistant-top-menu-button")
  end

  it "stays open when a question is sent from it" do
    get my_page_path

    expect(response.parsed_body.at_css("#assistant-panel-dialog")["data-keep-open-on-submit"]).to eq("true")
  end

  it "gives the question back when it cannot be sent because an answer is still being written" do
    conversation = Assistant::Conversation.create!(user: sam, project:, context: work_package, title: "Busy")
    conversation.messages.create!(role: "user", content: "First question", status: "done")
    conversation.messages.create!(role: "assistant", content: "Looking", status: "streaming")

    post reply_assistant_conversation_path(conversation), params: { content: "Second question" }

    expect(response.parsed_body.at_css("#assistant-panel-input").text).to eq("Second question")
  end
end
