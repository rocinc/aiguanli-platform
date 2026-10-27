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

# 04 D2 (总结长帖), D4 (翻译), F1 (起草 PR 描述).
RSpec.describe Assistant::Reasoning::Tools::Draft do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking forums assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages view_messages use_assistant]) }
  shared_let(:ada) { create(:user, firstname: "Ada", member_with_roles: { project => role }) }
  shared_let(:outsider) { create(:user) }
  shared_let(:forum) { create(:forum, project:) }

  def draft(args, user = ada) = described_class.new(Assistant::Reasoning::Tools::Context.new(user:, project:)).call(args)

  it "reads a whole forum topic for a summary, and nothing for someone who may not read it" do
    root = create(:message, forum:, author: ada, subject: "PDF page numbers", content: "Printing is painful.")
    create(:message, forum:, parent: root, author: ada, content: "Agreed, footer please.")

    result = draft("kind" => "summary", "about" => "forum:#{root.id}")

    expect(result.dig("material", "posts").pluck("text")).to eq(["Printing is painful.", "Agreed, footer please."])
    expect { draft({ "kind" => "summary", "about" => "forum:#{root.id}" }, outsider) }
      .to raise_error(Assistant::Reasoning::Tools::Refused)
  end

  it "gives a PR description the work package's acceptance criteria and asks a translation for the language wanted" do
    wp = create(:work_package, project:, subject: "Page numbers", description: "- [ ] footer shows n / m\n- [ ] works in landscape")

    expect(draft("kind" => "pr_description", "about" => "##{wp.id}").dig("material", "acceptance"))
      .to eq(["footer shows n / m", "works in landscape"])
    expect(draft("kind" => "translation", "about" => "##{wp.id}", "to" => "de")["template"]).to include("de")
  end
end
