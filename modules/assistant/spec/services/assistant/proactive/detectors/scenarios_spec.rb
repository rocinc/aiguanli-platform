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

RSpec.describe "Scenario S4: sprint planning" do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant backlogs meetings]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant
                                          view_meetings edit_meetings manage_agendas])
  end
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:closed) { create(:closed_status) }

  let(:now) { Time.zone.local(2026, 10, 16, 10) }
  let(:today) { now.to_date }

  before do
    travel_to(now)
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
    Assistant::Facts.reset!
  end

  after { travel_back }

  it "drafts the planning agenda the working day before: capacity, carry-over, scope against the room, the goal" do
    previous = create(:sprint, project:, start_date: Date.new(2026, 10, 5), finish_date: Date.new(2026, 10, 16))
    sprint = create(:sprint, project:, start_date: Date.new(2026, 10, 19), finish_date: Date.new(2026, 10, 30))
    left = create(:work_package, project:, sprint: previous, assigned_to: ben, subject: "Search API", remaining_hours: 6)
    planned = create(:work_package, project:, sprint:, assigned_to: ben, subject: "Export", remaining_hours: 30)
    create(:user_non_working_time, user: ben, start_date: Date.new(2026, 10, 22), end_date: Date.new(2026, 10, 23))
    meeting = create(:meeting, project:, author: lead, title: "Sprint planning", start_time: now + 3.days)

    found = Assistant::Proactive::Detectors::SprintPlanningPrep.new(project, today:).candidates.sole

    expect(found).to have_attributes(recipient: lead, subject: meeting)
    notes = found.options_for(lead).sole[:steps].to_h { [it["attributes"]["title"], it["attributes"]["notes"]] }
    expect(notes.values).to all(be_present)
    expect(notes.values.join).to include("Ben B", "2 day(s) off", "##{left.id}", "##{planned.id}")
  end

  it "puts the leave dates in the capacity, the owner on carried-over work, and keeps points off unestimated scope" do
    previous = create(:sprint, project:, start_date: Date.new(2026, 10, 5), finish_date: Date.new(2026, 10, 16))
    sprint = create(:sprint, project:, start_date: Date.new(2026, 10, 19), finish_date: Date.new(2026, 10, 30))
    left = create(:work_package, project:, sprint: previous, assigned_to: ben, subject: "Search API", remaining_hours: 6)
    sized = create(:work_package, project:, sprint:, assigned_to: ben, subject: "Export", story_points: 3)
    unsized = create(:work_package, project:, sprint:, assigned_to: ben, subject: "Alerts UI")
    create(:user_non_working_time, user: ben, start_date: Date.new(2026, 10, 22), end_date: Date.new(2026, 10, 23))
    create(:meeting, project:, author: lead, title: "Sprint planning", start_time: now + 3.days, duration: 1.5)
    allow_any_instance_of(Assistant::Facts::SprintHistory).to receive(:velocity).and_return(20) # rubocop:disable RSpec/AnyInstance

    found = Assistant::Proactive::Detectors::SprintPlanningPrep.new(project, today:).candidates.sole
    notes = found.options_for(lead).sole[:steps].to_h { [it["attributes"]["title"], it["attributes"]["notes"]] }

    expect(notes["Capacity"]).to include("Ben B: ", "2 day(s) off, 10/22–10/23")
    expect(notes["Left over from last sprint"]).to include("##{left.id} “Search API” · Ben B ·")
    expect(notes["Scope that fits"]).to include("##{sized.id} “Export” (3 points)")
    expect(notes["Scope that fits"].lines.grep(/##{unsized.id} “Alerts UI”/).sole).not_to match(/points/)
  end

  it "leaves the goal to the host's own item, and keeps the agenda inside the meeting with a slot for decisions" do
    create(:sprint, project:, start_date: Date.new(2026, 10, 19), finish_date: Date.new(2026, 10, 30))
    meeting = create(:meeting, project:, author: lead, title: "Sprint planning", start_time: now + 3.days, duration: 1.5)
    create(:meeting_agenda_item, meeting:, author: lead, title: "Sprint goal draft", duration_in_minutes: 10)

    found = Assistant::Proactive::Detectors::SprintPlanningPrep.new(project, today:).candidates.sole
    steps = found.options_for(lead).sole[:steps].map { it["attributes"] }

    expect(steps.pluck("title")).not_to include("Sprint goal")
    expect(steps.last["title"]).to eq("Decisions and action items")
    expect(steps.sum { it["duration_in_minutes"].to_i } + 10).to be <= 90
  end

  it "counts story points at the hours a point has cost when sprint work has no hour estimate" do
    sprint = create(:sprint, project:, start_date: today, finish_date: today + 9)
    4.times do
      done = create(:work_package, project:, assigned_to: ben, story_points: 2, status: closed)
      create(:time_entry, project:, entity: done, user: ben, hours: 10, spent_on: today - 5)
    end
    wp = create(:work_package, project:, sprint:, assigned_to: ben, story_points: 3)

    expect(Assistant::Facts.remaining_hours(wp)).to eq(15.0)
    expect(Assistant::Facts::Load.new(ben, today, today + 9).hours).to eq(15.0)
  end
end
