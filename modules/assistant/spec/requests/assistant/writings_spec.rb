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

# 04 G3: the editor's AI writing runs through the assistant.
RSpec.describe "Writing in the editor", :skip_csrf, type: :rails_request,
                                                   with_settings: { ai_text_transform_actions_enabled: true } do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant wiki]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages use_assistant view_wiki_pages]) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:other) { create(:user, member_with_roles: { project => role }) }
  shared_let(:fix) do
    AI::TextTransformAction.create!(label: "Fix grammar", prompt: "Fix the grammar.", usage_scope: "everywhere")
  end
  shared_let(:wiki) { project.wiki || create(:wiki, project:) }

  let(:llm) { instance_double(Assistant::Llm) }

  before do
    login_as(sam)
    allow(Assistant::Llm).to receive_messages(configured?: true, new: llm)
    allow(llm).to receive(:json).and_return({})
    allow(llm).to receive(:chat) do |messages:, **, &on_delta|
      @system = messages.first[:content]
      @user = messages.last[:content]
      ["Das ist ", "ein Satz."].each { on_delta.call(:content, it) }
      Assistant::Llm::Reply.new(content: "Das ist ein Satz.", tool_calls: [], finish_reason: "stop", usage: {})
    end
  end

  it "lists the administrator's actions and the built-in ones" do
    get assistant_writings_path(project_id: project.id)

    expect(response.parsed_body).to include("enabled" => true)
    expect(response.parsed_body["actions"].pluck("label")).to eq(["Fix grammar"])
    expect(response.parsed_body["built_in"].pluck("key")).to eq(%w[continue rewrite translate write])
  end

  it "runs an action with the team's glossary in front, and streams the text as events" do
    create(:wiki_page, wiki:, title: "Glossary", text: "Knowledge base — never 'KB'")

    post assistant_writings_path, params: { project_id: project.id, action_id: fix.id, input: "das ist ein satz" }
    id = response.parsed_body["id"]
    perform_enqueued_jobs

    get assistant_writing_path(id)
    body = response.parsed_body
    expect(body["status"]).to eq("succeeded")
    expect(body["events"].pluck("kind")).to include("text_delta", "completed")
    expect(body["events"].find { it["kind"] == "completed" }.dig("payload", "text")).to eq("Das ist ein Satz.")
    expect(@system).to include("Fix the grammar.", "TEAM GLOSSARY", "never 'KB'")
  end

  it "continues with the person's direction and tells the model to leave the text alone" do
    post assistant_writings_path, params: { project_id: project.id, built_in: "continue", input: "Der Plan steht.",
                                            instruction: "往风险方向续写一句" }
    perform_enqueued_jobs

    expect(response).to have_http_status(:created)
    expect(@system).to include("原文必须保持原样", "往风险方向续写一句")
    expect(@user).to eq("Der Plan steht.")
  end

  it "rewrites a whole draft from the person's remark, keeping the original task" do
    post assistant_writings_path, params: { project_id: project.id, built_in: "revise", base: "continue",
                                            input: "Der Plan steht.", previous: "Das Risiko ist klein.",
                                            instruction: "kürzer", task_instruction: "Risiken" }
    perform_enqueued_jobs

    expect(response).to have_http_status(:created)
    expect(@system).to include("重写整份上一稿", "原文必须保持原样", "最初的要求：Risiken", "这次的修改意见", "kürzer")
    expect(@user).to include("【原始材料】\nDer Plan steht.", "【上一稿】\nDas Risiko ist klein.")
  end

  it "rewrites a draft with a configured action's prompt as the task" do
    post assistant_writings_path, params: { project_id: project.id, built_in: "revise", action_id: fix.id,
                                            input: "das ist ein satz", previous: "Das ist ein Satz.", instruction: "formeller" }
    perform_enqueued_jobs

    expect(@system).to include("原来的任务", "Fix the grammar.", "formeller")
  end

  it "rewrites only the chosen passage, with the whole text as context" do
    post assistant_writings_path, params: { project_id: project.id, built_in: "refine_selection",
                                            input: "Eins. Zwei. Drei.", selection: "Zwei.", instruction: "更短" }
    perform_enqueued_jobs

    expect(response).to have_http_status(:created)
    expect(@system).to include("只重写这个片段", "这一段的修改意见：更短")
    expect(@user).to eq("【全文，仅作上下文】\nEins. Zwei. Drei.\n\n【需要修改的片段】\nZwei.")
  end

  it "does not run a rewrite without a previous draft, or a passage rewrite without passage and remark" do
    post assistant_writings_path, params: { project_id: project.id, built_in: "revise", input: "x", instruction: "y" }
    expect(response).to have_http_status(:bad_request)

    post assistant_writings_path, params: { project_id: project.id, built_in: "refine_selection", input: "x", selection: "x" }
    expect(response).to have_http_status(:bad_request)

    post assistant_writings_path, params: { project_id: project.id, built_in: "refine_selection", input: "x", instruction: "y" }
    expect(response).to have_http_status(:bad_request)
  end

  it "keeps a run to the person who started it" do
    run = Assistant::Writing.start(user: other, input: "x", built_in: "continue")

    get assistant_writing_path(run.uuid)

    expect(response).to have_http_status(:not_found)
  end
end
