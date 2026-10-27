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

RSpec.describe Assistant::Facts::Capacity do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant])
  end
  shared_let(:full_time) { create(:user, member_with_roles: { project => role }) }
  shared_let(:part_time) { create(:user, member_with_roles: { project => role }) }
  shared_let(:monday) { Date.new(2026, 10, 12) }
  shared_let(:friday) { Date.new(2026, 10, 16) }

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    Assistant::Facts.reset!
    create(:user_working_hours, user: full_time, valid_from: monday - 30, availability_factor: 100)
    create(:user_working_hours, user: part_time, valid_from: monday - 30, availability_factor: 40)
  end

  it "counts a person at the share of their time they have for the project" do
    expect(described_class.new(full_time, monday, friday).hours).to eq(40.0)
    expect(described_class.new(part_time, monday, friday).hours).to eq(16.0)
  end

  it "leaves them proportionally less room for the same load" do
    [full_time, part_time].each do |user|
      create(:work_package, project:, assigned_to: user, start_date: monday, due_date: friday, remaining_hours: 10)
    end

    expect(Assistant::Facts::Load.new(full_time, monday, friday, today: monday).free_hours).to eq(30.0)
    expect(Assistant::Facts::Load.new(part_time, monday, friday, today: monday).free_hours).to eq(6.0)
  end
end
