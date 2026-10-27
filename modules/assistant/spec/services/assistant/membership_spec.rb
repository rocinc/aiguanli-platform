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
#++

require "spec_helper"

RSpec.describe Assistant::Membership do
  shared_let(:type) { create(:type) }
  shared_let(:project) { create(:project, types: [type], enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:in_progress) { create(:status, name: "In progress", position: 1) }
  shared_let(:developed) { create(:status, name: "Developed", position: 2) }
  shared_let(:rich_role) do
    create(:project_role, name: "Rich", permissions: %i[view_work_packages edit_work_packages add_work_packages use_assistant])
  end
  shared_let(:poor_role) { create(:project_role, name: "Poor", permissions: %i[view_work_packages]) }
  shared_let(:work_package) { create(:work_package, project:, type:, status: in_progress) }

  before do
    create(:workflow, role: rich_role, type:, old_status: in_progress, new_status: developed)
    create(:workflow, role: poor_role, type:, old_status: developed, new_status: in_progress)
  end

  def assistant_role = ProjectRole.find_by!(name: described_class::ROLE_NAME)

  it "gives a new assistant role the workflow of the given role with the most permissions" do
    described_class.ensure_member!(project)

    expect(assistant_role.workflows.pluck(:old_status_id, :new_status_id)).to eq([[in_progress.id, developed.id]])
  end

  it "lets the assistant move work forward once the role exists" do
    described_class.ensure_member!(project)

    expect(Assistant::Duties::AdvanceMergedPr.next_status(work_package)).to eq(developed)
  end

  it "leaves a workflow somebody already set up alone, and copies only once" do
    role = described_class.role
    Workflow.where(role_id: role.id).delete_all
    create(:workflow, role:, type:, old_status: developed, new_status: in_progress)

    2.times { described_class.ensure_member!(project) }

    expect(Workflow.where(role_id: role.id).pluck(:old_status_id, :new_status_id)).to eq([[developed.id, in_progress.id]])
  end

  it "does not fail when no other role has a workflow" do
    Workflow.delete_all

    expect { described_class.ensure_member!(project) }.not_to raise_error
    expect(assistant_role.workflows).to be_empty
  end
end
