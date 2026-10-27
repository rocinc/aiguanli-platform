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

RSpec.describe Assistant::Facts::Load do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant])
  end
  shared_let(:person) { create(:user, member_with_roles: { project => role }) }
  shared_let(:closed) { create(:closed_status) }
  shared_let(:monday) { Date.new(2026, 10, 12) }
  shared_let(:friday) { Date.new(2026, 10, 16) }

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    Assistant::Facts.reset!
    create(:user_working_hours, user: person, valid_from: monday - 30, availability_factor: 100)
  end

  def load_for(today: monday, window: monday..friday) = described_class.new(person, window.begin, window.end, today:)

  def overdue(**) = create(:work_package, project:, assigned_to: person, start_date: monday - 10, due_date: monday - 3, **)

  it "counts open work that is past due as due today" do
    wp = overdue(remaining_hours: 6)

    expect(load_for.hours).to eq(6.0)
    expect(load_for.entries.sole).to have_attributes(work_package: wp, hours_in_range: 6.0)
    expect(load_for.free_hours).to eq(34.0)
  end

  it "does not count overdue work that is finished or closed" do
    overdue(remaining_hours: 6, status: closed)
    overdue(remaining_hours: 0)

    expect(load_for.hours).to eq(0.0)
  end

  it "puts overdue work on the next working day when today is not one" do
    saturday = monday - 2
    overdue(remaining_hours: 6)

    expect(load_for(today: saturday, window: saturday..friday).hours).to eq(6.0)
    expect(load_for(today: saturday, window: saturday..(saturday + 1)).hours).to eq(0.0)
  end

  it "does not carry overdue work into a window that starts after today" do
    overdue(remaining_hours: 6)

    expect(load_for(window: (monday + 7)..(monday + 11)).hours).to eq(0.0)
  end

  it "counts work due later in the window as before" do
    create(:work_package, project:, assigned_to: person, start_date: monday, due_date: friday, remaining_hours: 10)

    expect(load_for.hours).to eq(10.0)
  end

  it "counts a parent only for its own hours, not again for its children" do
    parent = overdue(remaining_hours: 4)
    create(:work_package, project:, parent:, assigned_to: person, start_date: monday - 10, due_date: monday - 3,
                          remaining_hours: 2)

    expect(load_for.hours).to eq(6.0)
  end

  it "keeps the capacity of days off as it was" do
    create(:user_non_working_time, user: person, start_date: monday + 1, end_date: monday + 2)
    overdue(remaining_hours: 6)

    expect(load_for.free_hours).to eq(Assistant::Facts::Capacity.new(person, monday, friday).hours - 6.0)
    expect(Assistant::Facts::Capacity.new(person, monday, friday).hours).to eq(24.0)
  end
end
