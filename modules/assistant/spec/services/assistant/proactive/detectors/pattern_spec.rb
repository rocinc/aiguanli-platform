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

RSpec.describe "Pattern detectors" do
  shared_let(:bug) { create(:type, name: "Bug") }
  shared_let(:project) do
    create(:project, types: [bug], enabled_module_names: %w[work_package_tracking assistant backlogs github])
  end
  shared_let(:role) { create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant]) }
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:closed) { create(:closed_status) }

  let(:today) { Date.new(2026, 10, 14) }

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
  end

  def candidates(detector) = detector.new(project, today:).candidates

  describe Assistant::Proactive::Detectors::SystematicUnderestimate do
    # Planned Monday to Tuesday (2 working days), closed the next Monday: 6 working days, 3×.
    def finished_bug(start)
      travel_to(start.to_time + 9.hours) do
        create(:work_package, project:, type: bug, start_date: start, due_date: start + 1, estimated_hours: 4)
      end.tap do |wp|
        travel_to((start + 7).to_time + 9.hours) do
          wp.reload.status = closed
          wp.add_journal(user: lead)
          wp.save!(validate: false)
        end
      end
    end

    let!(:sprint) { create(:sprint, project:, start_date: Date.new(2026, 10, 19), finish_date: Date.new(2026, 10, 30)) }
    let!(:planned) { create(:work_package, project:, type: bug, sprint:, estimated_hours: 6) }

    it "tells the lead before the sprint that this type takes three times as long, with estimates to scale" do
      [Date.new(2026, 8, 3), Date.new(2026, 8, 17), Date.new(2026, 8, 31), Date.new(2026, 9, 14)].each { finished_bug(it) }

      found = candidates(described_class)

      expect(found.size).to eq(1)
      expect(found.first.facts).to include(type: "Bug", duration_ratio: 3.0, samples: 4)
      step = found.first.options_for(lead).first[:steps].first
      expect(step).to include("id" => planned.id, "attributes" => { "estimated_hours" => 18.0 })
    end

    it "does not judge on fewer than four finished examples" do
      [Date.new(2026, 8, 3), Date.new(2026, 8, 17), Date.new(2026, 8, 31)].each { finished_bug(it) }

      expect(candidates(described_class)).to be_empty
    end
  end

  describe Assistant::Proactive::Detectors::RepeatedCheckFailure do
    it "tells the lead when one check fails three times across two pull requests" do
      wp = create(:work_package, project:)
      first, second = create_list(:github_pull_request, 2, work_packages: [wp])
      create_list(:github_check_run, 2, github_pull_request: first, name: "rspec", conclusion: "failure")
      create(:github_check_run, github_pull_request: second, name: "rspec", conclusion: "failure")
      create(:github_check_run, github_pull_request: second, name: "lint", conclusion: "failure")

      found = candidates(described_class)

      expect(found.size).to eq(1)
      expect(found.first.facts).to include(check: "rspec", failures: 3)
    end
  end
end
