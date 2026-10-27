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

RSpec.describe "Assistant::Actions::Steps::CreateTimeEntry" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking costs assistant]) }
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages log_own_time view_time_entries use_assistant]) }
  shared_let(:member) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: member) }

  it "lets a member who may only log their own time have a draft of it previewed and sent" do
    action = Assistant::Actions::Propose.call(
      kind: "timesheet_draft", title: "Log 3 h", on_behalf_of: member, project:, auto_execute: false,
      steps: [{ op: "create_time_entry", attributes: { work_package_id: work_package.id, user_id: member.id, hours: 3,
                                                       spent_on: Date.current.iso8601 } }]
    )

    expect(action).to have_attributes(status: "proposed", error: nil)
    Assistant::Actions::Execute.call(action, decided_by: member)
    expect(action.reload.status).to eq("executed")
    expect(TimeEntry.where(user: member, entity: work_package).sole.hours).to eq(3)
  end
end
