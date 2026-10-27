# frozen_string_literal: true

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

RSpec.describe "Assistant action lifecycle" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_packages manage_work_package_relations
                                          work_package_assigned use_assistant])
  end
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, member_with_roles: { project => role }) }
  shared_let(:outsider) { create(:user) }

  let(:monday) { Date.new(2026, 10, 12) }
  let!(:first) { create(:work_package, project:, assigned_to: ben, start_date: monday, due_date: monday + 2) }
  let!(:second) do
    create(:work_package, project:, assigned_to: ben, start_date: monday + 3, due_date: monday + 7, schedule_manually: false)
  end

  before do
    allow(Setting).to receive(:working_days).and_return([1, 2, 3, 4, 5])
    create(:follows_relation, from: second, to: first)
    Assistant::Membership.ensure_member!(project)
  end

  def propose(due_date, on_behalf_of: sam)
    Assistant::Actions::Propose.call(
      kind: "reschedule", title: "Move it", on_behalf_of:, project:, subject: first,
      steps: [{ op: "update_work_package", type: "WorkPackage", id: first.id, attributes: { due_date: due_date.iso8601 } }],
      basis: [{ "kind" => "quote", "label" => "planning", "quote" => "push it a week" }]
    )
  end

  it "previews the consequences without changing anything" do
    action = propose(monday + 9)

    expect(action.preview["cascaded"]).to include(second.to_gid.to_s)
    expect(first.reload.due_date).to eq(monday + 2)
    expect(second.reload.start_date).to eq(monday + 3)
  end

  it "asks before moving other people's work" do
    expect(propose(monday + 9)).to have_attributes(tier: "t2", status: "proposed")
  end

  it "does it right away when nothing else moves and it is the person's own work" do
    lone = create(:work_package, project:, assigned_to: sam, start_date: monday, due_date: monday + 1)
    action = Assistant::Actions::Propose.call(
      kind: "reschedule", title: "Move mine", on_behalf_of: sam, project:, subject: lone,
      steps: [{ op: "update_work_package", type: "WorkPackage", id: lone.id, attributes: { due_date: (monday + 3).iso8601 } }]
    )

    expect(action).to have_attributes(tier: "t1", status: "executed")
    expect(lone.reload.due_date).to eq(monday + 3)
  end

  it "signs the change and can take it back with what moved along" do
    action = propose(monday + 9)
    Assistant::Actions::Execute.call(action, decided_by: sam)

    journal = first.journals.reload.last
    expect(journal.user).to eq(Assistant.user)
    expect(journal.cause).to include("type" => "assistant_action", "on_behalf_of_id" => sam.id)
    expect(second.reload.start_date).to be > monday + 3

    result = Assistant::Actions::Undo.call(action.reload, user: sam)

    expect(result.success).to be(true)
    expect(first.reload.due_date).to eq(monday + 2)
    expect(second.reload.start_date).to eq(monday + 3)
  end

  it "never does more than the person it acts for could" do
    action = propose(monday + 9, on_behalf_of: outsider)

    expect(action.status).to eq("failed")
    expect(first.reload.due_date).to eq(monday + 2)
  end

  it "leaves fields someone changed since alone" do
    action = propose(monday + 9)
    Assistant::Actions::Execute.call(action, decided_by: sam)
    WorkPackages::UpdateService.new(user: sam, model: first.reload).call(due_date: monday + 12)

    expect(Assistant::Actions::Undo.new(action.reload, user: sam).conflicts.pluck("attribute")).to include("due_date")
  end
end
