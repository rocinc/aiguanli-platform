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

RSpec.describe Assistant::Facts::ReleaseRisks do
  shared_let(:project) { create(:project) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B") }
  let(:today) { Date.new(2026, 10, 16) }
  let(:version) { create(:version, project:, effective_date: Date.new(2026, 10, 23)) }
  let(:readiness) { Assistant::Facts::VersionReadiness.new(version, today:) }

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    Assistant::Facts.reset!
  end

  it "names overdue, unowned and leave-on-due-date work with its number and title" do
    late = create(:work_package, project:, version:, assigned_to: ben, subject: "Billing basis", due_date: today - 2)
    away = create(:work_package, project:, version:, assigned_to: ben, subject: "Invoices", due_date: Date.new(2026, 10, 23))
    nobody = create(:work_package, project:, version:, subject: "Tax id check", due_date: today + 3)
    create(:user_non_working_time, user: ben, start_date: Date.new(2026, 10, 21), end_date: Date.new(2026, 10, 23))

    lines = described_class.new(readiness, today:).lines.to_h { |kind, line| [kind, line] }

    expect(lines[:overdue]).to include("##{late.id}", "Billing basis")
    expect(lines[:leave]).to include("##{away.id}", "Invoices", "10/23", "Ben B", "10/21–10/23")
    expect(lines[:unassigned]).to include("##{nobody.id}", "Tax id check")
  end

  it "says when a chain on the critical path has no room left" do
    first = create(:work_package, project:, version:, assigned_to: ben, start_date: today, due_date: today + 2)
    second = create(:work_package, project:, version:, assigned_to: ben, start_date: today + 3, due_date: Date.new(2026, 10, 23))
    create(:follows_relation, from: second, to: first)

    chain = described_class.new(readiness, today:).lines.to_h[:margin]

    expect(chain).to include("##{first.id}→##{second.id}")
  end
end
