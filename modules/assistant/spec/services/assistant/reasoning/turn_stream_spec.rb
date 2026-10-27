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

RSpec.describe Assistant::Reasoning::Turn, "streaming" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }

  let(:conversation) { Assistant::Conversation.create!(user: sam, project:) }
  let(:question) { conversation.messages.create!(role: "user", content: "Can #75 make it?", status: "done") }
  let(:placeholder) { conversation.messages.create!(role: "assistant", content: "", status: "streaming") }
  let(:llm) do
    instance_double(Assistant::Llm).tap do |llm|
      allow(llm).to receive(:chat) do |**, &on_delta|
        %w[It\  can, \ if\  it\  starts\  Monday.].each { on_delta.call(:content, it) }
        Assistant::Llm::Reply.new(content: "It can, if it starts Monday.", tool_calls: [], finish_reason: "stop", usage: {})
      end
    end
  end
  let(:broadcasts) { [] }

  before do
    stub_const("Assistant::Reasoning::Turn::Listener::FLUSH_EVERY", -1)
    allow(Turbo::StreamsChannel).to receive(:broadcast_action_to) { |*, **args| broadcasts << args }
  end

  it "broadcasts contiguous slices with offsets and keeps the text on the message" do
    seen = []
    allow(Turbo::StreamsChannel).to receive(:broadcast_action_to) do |*, **args|
      seen << [args[:attributes][:kind], placeholder.reload.content] if args[:attributes][:kind] == "delta"
      broadcasts << args
    end

    described_class.new(conversation:, user_message: question, placeholder:, llm:).call

    deltas = broadcasts.select { it[:attributes][:kind] == "delta" }
    expect(deltas.map { it[:attributes][:from] }).to eq([0] + deltas[..-2].map { it[:attributes][:to] })
    expect(deltas.map { CGI.unescapeHTML(it[:html]) }.join).to eq("It can, if it starts Monday.")
    expect(seen.last.last).to eq("It can, if it starts Monday.")
    expect(broadcasts.last[:attributes][:kind]).to eq("settled")
    expect(placeholder.reload).to have_attributes(status: "done", progress: nil)
  end

  it "stops writing once the person has stopped it, keeping what was written" do
    allow(llm).to receive(:chat) do |**, &on_delta|
      on_delta.call(:content, "It can, ")
      placeholder.update_columns(status: "stopped")
      on_delta.call(:content, "if it starts Monday.")
      raise "kept going after the stop"
    end

    described_class.new(conversation:, user_message: question, placeholder:, llm:).call

    expect(placeholder.reload).to have_attributes(status: "stopped", content: "It can, ")
  end
end

RSpec.describe "Polling a message being written", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }

  let(:conversation) { Assistant::Conversation.create!(user: sam, project:) }
  let(:message) do
    conversation.messages.create!(role: "assistant", content: "Looking at #75 — it can", status: "streaming",
                                  progress: "Following the critical path…")
  end

  before { login_as(sam) }

  it "answers with the text after the offset the browser already has" do
    get assistant_conversation_message_path(conversation, message, format: :json), params: { offset: 12 }

    expect(response.parsed_body).to include("status" => "streaming", "offset" => 12, "length" => 23,
                                            "content" => "75 — it can", "progress" => "Following the critical path…")
  end

  it "clamps an offset past the end" do
    get assistant_conversation_message_path(conversation, message, format: :json), params: { offset: 99 }

    expect(response.parsed_body).to include("offset" => 23, "content" => "")
  end
end
