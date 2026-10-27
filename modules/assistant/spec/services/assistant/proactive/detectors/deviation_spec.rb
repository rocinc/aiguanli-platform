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

require "spec_helper"

RSpec.describe "Deviation detectors" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant backlogs budgets costs]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant manage_versions])
  end
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:closed) { create(:closed_status) }

  let(:today) { Date.new(2026, 10, 14) } # Wednesday

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
  end

  def candidates(detector) = detector.new(project, today:).candidates

  describe Assistant::Proactive::Detectors::BurndownDrift do
    # Monday 5th to Friday 16th: ten working days, seven gone by the 14th.
    let!(:sprint) { create(:sprint, project:, start_date: Date.new(2026, 10, 5), finish_date: Date.new(2026, 10, 16)) }

    def item(points, closed: false, priority: nil)
      create(:work_package, project:, sprint:, story_points: points, assigned_to: ben,
                            status: closed ? self.closed : create(:status), **{ priority: }.compact)
    end

    it "tells the lead when what is left is 30% over the ideal line, with what to take out" do
      low = create(:issue_priority, position: 1)
      item(5, closed: true)
      item(5, priority: low)
      item(10)
      # 20 points, ideal leaves 6 after 7 of 10 days; 15 left is 150% over.
      found = candidates(described_class)

      expect(found.size).to eq(1)
      expect(found.first).to have_attributes(recipient: lead, nature: :team, act_by: sprint.finish_date)
      expect(found.first.facts).to include("unit" => "points", "total" => 20.0, "remaining" => 15.0, "ideal_remaining" => 6.0)
      cut = found.first.options_for(lead).find { it[:kind] == "cut_scope" }
      expect(cut[:steps].first).to include("attributes" => { "sprint_id" => nil })
    end

    it "stays quiet on the line" do
      item(5, closed: true)
      item(5, closed: true)
      item(4, closed: true)
      item(6)

      expect(candidates(described_class)).to be_empty
    end
  end

  describe Assistant::Proactive::Detectors::BudgetAhead do
    let!(:budget) { create(:budget, project:, author: lead, base_amount: 1000) }
    let!(:done) { create(:work_package, project:, budget:, status: closed) }
    let!(:open_one) { create(:work_package, project:, budget:) }

    def spend(wp, amount)
      create(:time_entry, entity: wp, user: ben, hours: 4).update_columns(costs: amount)
    end

    it "tells the budget owner when spending runs ten points ahead of the work done" do
      spend(done, 300)
      spend(open_one, 400)

      found = candidates(described_class)

      expect(found.size).to eq(1)
      expect(found.first.recipient).to eq(lead)
      expect(found.first.facts).to include(spent_percent: 70, done_percent: 50, ahead_points: 20, forecast: 1400.0)
      expect(found.first.because.join).to include("##{open_one.id}")
    end

    it "says nothing when spending keeps pace" do
      spend(done, 500)

      expect(candidates(described_class)).to be_empty
    end
  end

  describe Assistant::Proactive::Detectors::HoursOverEstimate do
    let!(:wp) { create(:work_package, project:, assigned_to: ben, estimated_hours: 8) }

    it "asks the assignee once logged time passes 1.5 times the estimate" do
      create(:time_entry, entity: wp, user: ben, hours: 11)
      expect(candidates(described_class)).to be_empty

      create(:time_entry, entity: wp, user: ben, hours: 1)
      found = candidates(described_class)

      expect(found.size).to eq(1)
      expect(found.first).to have_attributes(recipient: ben, nature: :own)
      expect(found.first.options_for(ben).map { it[:kind] }).to eq(%w[adjust_estimate blocked])
    end
  end
end
