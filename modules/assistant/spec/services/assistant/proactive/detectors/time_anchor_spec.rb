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

RSpec.describe "Time anchor detectors" do
  shared_let(:project) do
    create(:project, enabled_module_names: %w[work_package_tracking assistant meetings costs budgets])
  end
  shared_let(:other_project) { create(:project, name: "Scribe", enabled_module_names: %w[work_package_tracking]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant
                                          view_meetings edit_meetings manage_agendas log_own_time view_own_time_entries])
  end
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role, other_project => role }) }

  let(:now) { Time.zone.local(2026, 10, 16, 15, 30) }
  let(:today) { now.to_date }

  before do
    travel_to(now)
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
    Assistant::Facts.reset!
  end

  after { travel_back }

  def candidates(detector) = detector.new(project, today:, since: 1.day.ago).candidates

  describe Assistant::Proactive::Detectors::MeetingPrep do
    it "drafts the agenda an hour before: what last time said and what is due among those invited" do
      previous = create(:meeting, project:, author: lead, title: "Weekly", start_time: now - 7.days)
      create_intent(project:, subject: previous, owner: ben, title: "Ship the search API")
      meeting = create(:meeting, project:, author: lead, title: "Weekly", start_time: now + 50.minutes)
      create(:meeting_participant, meeting:, user: ben, invited: true)
      due = create(:work_package, project:, assigned_to: ben, due_date: today + 2, subject: "Search API")

      found = candidates(described_class).sole

      expect(found).to have_attributes(recipient: lead, subject: meeting, channel: "notification")
      steps = found.options_for(lead).sole[:steps]
      expect(steps.map { it["op"] }.uniq).to eq(["create_meeting_agenda_item"])
      notes = steps.map { it["attributes"]["notes"] }.join
      expect(notes).to include("Ship the search API", "##{due.id}")
    end
  end

  describe Assistant::Proactive::Detectors::DeadlineCluster do
    it "warns someone a week ahead of three due dates on one day, across projects, and moves the least urgent" do
      low = create(:issue_priority, position: 1)
      high = create(:issue_priority, position: 5)
      date = today + 5
      keep = create(:work_package, project:, assigned_to: ben, due_date: date, priority: high)
      move = create(:work_package, project:, assigned_to: ben, due_date: date, start_date: date, priority: low)
      create(:work_package, project: other_project, assigned_to: ben, due_date: date, priority: high)

      found = candidates(described_class).sole

      expect(found).to have_attributes(recipient: ben, nature: :own)
      step = found.options_for(ben).sole[:steps].sole
      expect(step["id"]).to eq(move.id)
      expect(step["id"]).not_to eq(keep.id)
      expect(Date.parse(step["attributes"]["due_date"])).to be > date
    end
  end

  describe Assistant::Proactive::Detectors::DeadlineCluster, "with parents" do
    it "counts only leaves: a parent's date is only its children's summed up" do
      date = today + 5
      create(:work_package, project:, assigned_to: ben, due_date: date)
      create(:work_package, project:, assigned_to: ben, due_date: date)
      parent = create(:work_package, project:, assigned_to: ben, due_date: date, start_date: date, schedule_manually: true)
      create(:work_package, project:, parent:, assigned_to: lead, due_date: today + 4, schedule_manually: true)

      expect(parent.reload.due_date).to eq(date)
      expect(candidates(described_class)).to be_empty

      create(:work_package, project:, assigned_to: ben, due_date: date)

      expect(candidates(described_class).sole.facts[:ids]).not_to include(parent.id)
    end
  end

  describe Assistant::Proactive::Detectors::WeeklyTimesheet do
    it "drafts someone's week from what they said, on Friday afternoon, unless the duty does it" do
      wp = create(:work_package, project:, assigned_to: ben)
      wp.add_journal(user: ben, notes: "排查花了三小时，是缓存的问题")
      wp.save!(validate: false)
      wp.journals.last.update_columns(created_at: now)

      found = candidates(described_class).sole

      expect(found.recipient).to eq(ben)
      expect(found.options_for(ben).sole[:steps].sole["attributes"]).to include("hours" => 3, "work_package_id" => wp.id)

      Assistant::Duty.create!(project:, kind: "timesheet_draft", delegator: lead)
      expect(candidates(described_class)).to be_empty
    end
  end

  describe Assistant::Proactive::Detectors::BudgetBrief do
    let(:now) { Time.zone.local(2026, 9, 30, 10) }

    it "briefs the lead in hours on the last working day of the quarter when no budget is visible" do
      wp = create(:work_package, project:, assigned_to: ben)
      create(:time_entry, project:, entity: wp, user: ben, hours: 6, spent_on: today - 3)

      found = candidates(described_class).sole

      expect(found.recipient).to eq(lead)
      expect(found.facts).to include(money: false, spent: 6.0)
      expect(found.headline).to include("2026")
    end
  end

  describe Assistant::Proactive::Detectors::PhaseGate do
    it "checks two weeks before a gate whether the phase is ready, and offers the late work to the next phase" do
      gate = Assistant::Facts.add_working_days(today, 10)
      build_def = create(:project_phase_definition, :with_finish_gate, name: "Build")
      next_def = create(:project_phase_definition, name: "Close")
      create(:project_phase, project:, definition: build_def, start_date: today - 20, finish_date: gate)
      create(:project_phase, project:, definition: next_def, start_date: gate + 1, finish_date: gate + 20)
      late = create(:work_package, project:, project_phase_definition: build_def, assigned_to: ben, due_date: gate + 5)

      found = candidates(described_class).sole

      expect(found.recipient).to eq(lead)
      expect(found.facts).to include(open: 1, gate:)
      options = found.options_for(lead)
      expect(options.map { it[:kind] }).to include("gate_review")
      step = options.reject { it[:kind] == "gate_review" }.sole[:steps].sole
      expect(step).to include("id" => late.id, "attributes" => { "project_phase_definition_id" => next_def.id })
    end
  end
end
