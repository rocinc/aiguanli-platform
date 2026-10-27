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
RSpec.describe Assistant::Actions::Steps::UpdateWorkPackage do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }

  let(:monday) { Date.new(2026, 11, 2) }
  let(:work_package) do
    create(:work_package, project:, assigned_to: sam, start_date: monday, due_date: monday + 1, schedule_manually: false)
  end

  before do
    allow(Setting).to receive(:working_days).and_return([1, 2, 3, 4, 5])
    Assistant::Membership.ensure_member!(project)
  end

  it "keeps the date that was asked for when scheduling saves the work package again as a manual one" do
    action = Assistant::Actions::Propose.call(
      kind: "reschedule", title: "Move it", on_behalf_of: sam, project:, subject: work_package, auto_execute: false,
      steps: [{ op: "update_work_package", type: "WorkPackage", id: work_package.id,
                attributes: { due_date: (monday + 10).iso8601 } }]
    )

    change = action.preview["changes"].sole
    expect(change["changes"]).to include("due_date" => [(monday + 1).iso8601, (monday + 10).iso8601])
    expect(change["changes"]).to include("schedule_manually" => [false, true])

    Assistant::Actions::Execute.call(action, decided_by: sam)
    expect(action.reload.inverse.sole["attributes"]).to include("due_date" => (monday + 1).iso8601)
    Assistant::Actions::Undo.call(action, user: sam)
    expect(work_package.reload.due_date).to eq(monday + 1)
  end
end
