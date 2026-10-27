# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

RSpec.describe "The assistant's tools over MCP", with_ee: %i[mcp_server] do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant])
  end
  shared_let(:sam) { create(:user, firstname: "Sam", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", member_with_roles: { project => role }) }
  shared_let(:outsider) { create(:user) }

  let(:monday) { Date.new(2026, 10, 12) }
  let!(:mine) { create(:work_package, project:, assigned_to: sam, start_date: monday, due_date: monday + 1) }
  let!(:bens) { create(:work_package, project:, assigned_to: ben, start_date: monday, due_date: monday + 2) }
  let(:user) { sam }

  before do
    allow(Setting).to receive(:working_days).and_return([1, 2, 3, 4, 5])
    Assistant::Membership.ensure_member!(project)
    create(:mcp_configuration, identifier: "mcp_server")
    %w[assistant_work_package assistant_propose decide_assistant_action].each do
      create(:mcp_configuration, identifier: "tools/#{it}")
    end
  end

  def call_tool(name, arguments)
    header "Authorization", "Bearer #{create(:oauth_access_token, scopes: 'mcp', resource_owner: user).plaintext_token}"
    header "Content-Type", "application/json"
    post "/mcp", { jsonrpc: "2.0", id: "1", method: "tools/call", params: { name:, arguments: } }.to_json
    JSON.parse(last_response.body).dig("result", "structuredContent")
  end

  def propose(ref, due_date)
    call_tool("assistant_propose", project_id: project.identifier, title: "Move #{ref}",
                                   steps: [{ op: "update_work_package", work_package: ref, attributes: { due_date: } }])
  end

  it "answers with the same computed facts the panel sees" do
    result = call_tool("assistant_work_package", project_id: project.identifier, ref: "##{bens.id}")

    expect(result).to include("id" => bens.id, "assignee" => { "id" => ben.id, "name" => ben.name })
    expect(result).not_to have_key("cards")
  end

  it "does the person's own change right away and records where it came from" do
    result = propose("##{mine.id}", (monday + 3).iso8601)

    expect(result).to include("tier" => "t1", "done" => true)
    expect(mine.reload.due_date).to eq(monday + 3)
    expect(Assistant::Action.find(result["action_id"]).basis).to contain_exactly(include("kind" => "mcp"))
  end

  it "leaves someone else's work waiting until the person confirms it" do
    result = propose("##{bens.id}", (monday + 4).iso8601)
    expect(result).to include("tier" => "t2", "needs_confirmation" => true)
    expect(bens.reload.due_date).to eq(monday + 2)

    decided = call_tool("decide_assistant_action", action_id: result["action_id"], decision: "approve")

    expect(decided).to include("status" => "executed")
    expect(bens.reload.due_date).to eq(monday + 4)
  end

  context "for someone the assistant is not available to" do
    let(:user) { outsider }

    it "refuses" do
      call_tool("assistant_work_package", project_id: project.id, ref: "##{bens.id}")

      expect(JSON.parse(last_response.body).dig("result", "isError")).to be(true)
      expect(last_response.body).not_to include(bens.subject)
    end
  end
end
