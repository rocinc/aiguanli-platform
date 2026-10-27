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
require_relative "../../../../support/intent_helpers"

RSpec.describe "Cascade detectors" do
  shared_let(:project) do
    create(:project, enabled_module_names: %w[work_package_tracking assistant backlogs resource_management wiki])
  end
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant])
  end
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:quinn) { create(:user, firstname: "Quinn", lastname: "Q", member_with_roles: { project => role }) }

  let(:today) { Date.new(2026, 10, 14) }

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
  end

  def candidates(detector) = detector.new(project, today:, since: 1.day.ago).candidates

  def event!(kind, subject, actor: lead, **changes)
    Assistant::Event.create!(kind:, subject:, project:, actor:, changes_made: changes.transform_keys(&:to_s),
                             created_at: Time.current)
  end

  describe Assistant::Proactive::Detectors::MemberLeaving do
    it "drafts the handover with each open work package and a suggested new owner" do
      create(:work_package, project:, assigned_to: quinn, status: create(:closed_status))
      wp = create(:work_package, project:, subject: "Search API", assigned_to: ben, due_date: today + 5, estimated_hours: 4)
      create_intent(project:, subject: wp, owner: ben, counterparty: lead, title: "Ship the search API")
      event!("member_removed", ben)

      found = candidates(described_class)

      expect(found.size).to eq(1)
      expect(found.first).to have_attributes(recipient: lead, nature: :team)
      options = found.first.options_for(lead)
      page = options.find { it[:kind] == "handover_page" }[:steps].first
      expect(page["attributes"]["text"]).to include("##{wp.id} Search API", "Ship the search API")
      expect(options.map { it[:kind] }).to include("reassign")
    end
  end

  describe Assistant::Proactive::Detectors::SprintSqueeze do
    let!(:sprint) { create(:sprint, project:, start_date: Date.new(2026, 10, 12), finish_date: Date.new(2026, 10, 16)) }

    it "tells whoever added work mid-sprint what it crowds out" do
      allow(Assistant::Facts::Capacity).to receive(:new).and_return(instance_double(Assistant::Facts::Capacity, hours: 24.0,
                                                                                                                absences: []))
      low = create(:issue_priority, position: 1)
      kept = create(:work_package, project:, sprint:, assigned_to: ben, remaining_hours: 16)
      dropped = create(:work_package, project:, sprint:, assigned_to: ben, remaining_hours: 6, priority: low)
      added = create(:work_package, project:, sprint:, assigned_to: ben, remaining_hours: 8)
      event!("work_package.updated", added, sprint_id: [nil, sprint.id])

      found = candidates(described_class)

      expect(found.size).to eq(1)
      expect(found.first).to have_attributes(recipient: lead, subject: added, channel: "inline")
      expect(found.first.facts).to include(over_hours: 6.0)
      moved = found.first.options_for(lead).first[:steps].map { it["id"] }
      expect(moved).to eq([dropped.id])
      expect(moved).not_to include(kept.id)
    end
  end

  describe Assistant::Proactive::Detectors::AbsenceRipple do
    it "also tells whoever is accountable for the work the time off hits" do
      create(:work_package, project:, assigned_to: ben, responsible: quinn, start_date: today + 1, due_date: today + 3)
      create(:user_non_working_time, user: ben, start_date: today + 1, end_date: today + 2)

      expect(candidates(described_class).map(&:recipient)).to contain_exactly(lead, quinn)
    end
  end

  describe Assistant::Proactive::Detectors::AllocationOverbooked do
    it "tells whoever approved an allocation that books someone past their time" do
      create(:user_working_hours, user: ben, valid_from: today - 30)
      wp = create(:work_package, project:)
      create(:resource_allocation, entity: wp, principal: ben, requested_by: lead, reviewed_by: lead,
                                   start_date: Date.new(2026, 10, 19), end_date: Date.new(2026, 10, 20), allocated_time: 20 * 60)

      found = candidates(described_class)

      expect(found.size).to eq(1)
      expect(found.first.recipient).to eq(lead)
      expect(found.first.facts).to include(user_id: ben.id, over_hours: 4.0)
    end
  end
end
