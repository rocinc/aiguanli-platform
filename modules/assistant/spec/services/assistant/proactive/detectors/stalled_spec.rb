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

RSpec.describe Assistant::Proactive::Detectors::Stalled do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant])
  end
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:doing) { create(:status, name: "In progress") }

  let(:today) { Date.new(2026, 10, 12) }
  let!(:wp) do
    create(:work_package, project:, assigned_to: ben, status: doing, due_date: today + 10).tap do |work_package|
      work_package.journals.update_all(created_at: Time.zone.local(2026, 10, 2, 16))
    end
  end

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
    Assistant::Facts.reset!
  end

  def candidates(on: today) = described_class.new(project, today: on, since: 1.day.ago).candidates

  def history(on: today) = Assistant::Facts::History.new(wp.reload, today: on)

  it "says it has not moved for the working days since the last change" do
    found = candidates.sole

    expect(found).to have_attributes(recipient: ben, subject: wp)
    expect(history.idle_working_days).to eq(5)
  end

  it "does not count the days the assignee was away" do
    create(:user_non_working_time, user: ben, start_date: Date.new(2026, 10, 5), end_date: Date.new(2026, 10, 9))

    expect(history.idle_working_days).to eq(0)
    expect(candidates).to be_empty
  end

  it "counts the days after they are back" do
    create(:user_non_working_time, user: ben, start_date: Date.new(2026, 10, 5), end_date: Date.new(2026, 10, 9))

    expect(history(on: Date.new(2026, 10, 19)).idle_working_days).to eq(5)
    expect(candidates(on: Date.new(2026, 10, 19)).sole.subject).to eq(wp)
  end

  it "reckons from the day it is given, not from the clock" do
    travel_to(Time.zone.local(2026, 12, 1, 9)) do
      expect(history.idle_working_days).to eq(5)
    end
  end
end
