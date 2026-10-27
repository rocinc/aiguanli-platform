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
RSpec.describe "Whose name words go out in" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_package_comments work_package_assigned
                                          view_work_package_watchers use_assistant])
  end
  shared_let(:sam) { create(:user, firstname: "Sam", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", member_with_roles: { project => role }) }
  shared_let(:fiona) { create(:user, firstname: "Fiona", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: ben) }

  before do
    Assistant::Membership.ensure_member!(project)
    work_package.add_watcher(fiona)
  end

  def say(**step)
    Assistant::Actions::Propose.call(
      kind: "say", title: "Say it", on_behalf_of: sam, project:, subject: work_package, auto_execute: false,
      steps: [{ op: "comment", type: "WorkPackage", id: work_package.id, attributes: { notes: "Fine by me." }, **step }]
    )
  end

  it "writes words that are the person's as the person, and says who drafted them" do
    action = say(as: "person")

    expect(action).to have_attributes(tier: "t2", status: "proposed")
    Assistant::Actions::Execute.call(action, decided_by: sam)

    journal = work_package.journals.reload.where.not(notes: [nil, ""]).last
    expect(journal.user).to eq(sam)
    expect(journal.cause).to include("type" => "assistant_action", "signed_by_id" => sam.id, "action_id" => action.id)
  end

  it "keeps statements about the object the assistant's own" do
    action = say

    Assistant::Actions::Execute.call(action, decided_by: sam)

    journal = work_package.journals.reload.where.not(notes: [nil, ""]).last
    expect(journal.user).to eq(Assistant.user)
    expect(journal.cause).to include("on_behalf_of_id" => sam.id, "signed_by_id" => nil)
  end

  it "tells whom the platform would notify, without that deciding who has to agree" do
    action = say

    expect(action.preview["notified_user_ids"]).to contain_exactly(ben.id, fiona.id)
    expect(action.preview["affected_user_ids"]).to be_empty
    expect(Assistant::DraftComponent.new(action:, user: sam).outcome).to include(ben.name)
  end
end
