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

RSpec.describe Assistant::Proactive::Routing do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant])
  end
  shared_let(:reader_role) { create(:project_role, permissions: %i[view_work_packages use_assistant]) }
  shared_let(:closed) { create(:closed_status) }
  shared_let(:ben) { create(:user, firstname: "Ben", member_with_roles: { project => role }) }
  shared_let(:ada) { create(:user, firstname: "Ada", member_with_roles: { project => role }) }
  shared_let(:system_admin) { create(:admin, firstname: "System", member_with_roles: { project => role }) }
  shared_let(:quinn) { create(:user, firstname: "Quinn", member_with_roles: { project => role }) }
  shared_let(:reader) { create(:user, firstname: "Rae", member_with_roles: { project => reader_role }) }
  shared_let(:today) { Date.new(2026, 10, 12) }

  def finished_by(user) = create(:work_package, project:, assigned_to: user, status: closed)

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    Assistant::Facts.reset!
    [ben, reader].each { finished_by(it) }
    epic = create(:work_package, project:, assigned_to: ada, schedule_manually: true)
    create(:work_package, project:, parent: epic, assigned_to: ben)
    create(:work_package, project:, assigned_to: quinn)
  end

  describe ".assignable" do
    it "is those who hold leaf work here and may be given more, not who only sit in the project or hold epics" do
      expect(described_class.people(project)).to include(ada, system_admin)
      expect(described_class.assignable(project, on: today)).to contain_exactly(ben, quinn)
    end

    it "counts time logged as hands-on work" do
      create(:time_entry, project:, entity: create(:work_package, project:), user: ada, hours: 2, spent_on: today - 3)

      expect(described_class.assignable(project, on: today)).to include(ada)
    end

    it "takes in someone just handed their first leaf work package, with no time logged" do
      expect(TimeEntry.where(user: quinn)).to be_empty
      expect(described_class.assignable(project, on: today)).to include(quinn)
    end

    it "leaves out whoever is off today" do
      create(:user_non_working_time, user: ben, start_date: today - 2, end_date: today + 2)

      expect(described_class.assignable(project, on: today)).not_to include(ben)
      expect(described_class.assignable(project, on: today + 3)).to include(ben)
    end

    it "leaves out whoever is not allowed to take work packages" do
      expect(described_class.assignable(project, on: today)).not_to include(reader)
    end
  end
end
