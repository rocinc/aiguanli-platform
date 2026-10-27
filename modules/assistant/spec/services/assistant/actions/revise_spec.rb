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
require "rails_helper"

RSpec.describe Assistant::Actions::Revise do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_package_comments use_assistant])
  end
  shared_let(:sam) { create(:user, firstname: "Sam", lastname: "Lee", member_with_roles: { project => role }) }
  shared_let(:bob) { create(:user, firstname: "Bob", lastname: "Fischer", member_with_roles: { project => role }) }
  shared_let(:fiona) { create(:user, firstname: "Fiona", lastname: "Chen", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Search API") }

  let(:original) { %(Hi #{Assistant::Reasoning::StepBuilder.mention(bob)}, is Friday still fine?) }
  let(:action) do
    Assistant::Actions::Propose.call(
      kind: "ask_owner", title: "Ask Bob", on_behalf_of: sam, project:, subject: work_package, auto_execute: false,
      steps: [{ "op" => "comment", "type" => "WorkPackage", "id" => work_package.id, "attributes" => { "notes" => original } }]
    )
  end

  def revise(text) = described_class.call(action, user: sam, edits: { "0" => { "notes" => text } }).reload

  def notes = action.steps.first.dig("attributes", "notes")

  def notified = action.preview["notified_user_ids"]

  it "keeps the original mention when the text goes back unchanged" do
    revise("Hi @Bob Fischer, is Friday still fine?")

    expect(notes).to eq(original)
  end

  it "no longer mentions someone whose name was taken out" do
    revise("Hi Bob, is Friday still fine?")

    expect(notes).to eq("Hi Bob, is Friday still fine?")
    expect(notified).not_to include(bob.id)
  end

  it "turns a member's full name written with an @ into a mention" do
    revise("Hi @Bob Fischer, is Friday fine? Fiona knows: @Fiona Chen")

    expect(notes).to include(Assistant::Reasoning::StepBuilder.mention(fiona))
    expect(notes.scan("<mention").size).to eq(2)
  end

  it "leaves a name that matches nobody as plain text" do
    revise("Hi @Bob Fischer, ask @Zed Nobody and @Fiona")

    expect(notes).to eq("Hi #{Assistant::Reasoning::StepBuilder.mention(bob)}, ask @Zed Nobody and @Fiona")
  end

  it "does not nest a mention that is already in the text" do
    revise("Hi #{Assistant::Reasoning::StepBuilder.mention(fiona)} and @Bob Fischer")

    expect(notes.scan("<mention").size).to eq(2)
    expect(notes).not_to match(%r{<mention[^>]*><mention})
  end
end
