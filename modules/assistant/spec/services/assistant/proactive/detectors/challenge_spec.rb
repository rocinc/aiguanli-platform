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

RSpec.describe "Challenge and retrospective detectors" do
  shared_let(:task) { create(:type_task) }
  shared_let(:project) do
    create(:project, types: [task], enabled_module_names: %w[work_package_tracking assistant backlogs meetings wiki])
  end
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant
                                          view_meetings edit_meetings manage_agendas view_wiki_pages edit_wiki_pages add_work_packages])
  end
  shared_let(:lead) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:closed) { create(:closed_status) }
  shared_let(:bug) { create(:type, name: "缺陷") }

  let(:now) { Time.zone.local(2026, 10, 14, 9) }
  let(:today) { now.to_date }

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
    Assistant::Facts.reset!
  end

  before { travel_to(now) }
  after { travel_back }

  def at(time)
    travel_to(time)
    yield
  ensure
    travel_to(now)
  end

  def candidates(detector) = detector.new(project, today:, since: 1.day.ago).candidates

  def close!(wp, at:)
    at(at) { wp.update!(status: closed) }
  end

  describe Assistant::Proactive::Detectors::PreMortem do
    it "drafts a pre-mortem from the facts a week before a version ships, as a slot on the next meeting" do
      version = create(:version, project:, effective_date: today + 4)
      create_list(:work_package, 4, project:, version:, assigned_to: ben)
      late = create(:work_package, project:, version:, assigned_to: ben, due_date: today - 2)
      meeting = create(:meeting, project:, author: lead, start_time: now + 1.day)

      found = candidates(described_class).sole

      expect(found).to have_attributes(recipient: lead, subject: version, channel: "brief")
      expect(found.because.join).to include("##{late.id}")
      steps = found.options_for(lead).sole[:steps]
      expect(steps.map { it["op"] }).to eq(%w[create_meeting_agenda_item])
      notes = steps.sole["attributes"]["notes"]
      expect(notes).to include("- ", "##{late.id}")
      expect(notes).not_to include("[ ]")
      expect(steps.sole["attributes"]["meeting_id"]).to eq(meeting.id)
    end
  end

  describe Assistant::Proactive::Detectors::CrossSprintPattern do
    it "notices defects found in the last two days, sprint after sprint" do
      [Date.new(2026, 9, 7), Date.new(2026, 9, 21), Date.new(2026, 10, 5)].each do |monday|
        sprint = create(:sprint, project:, start_date: monday, finish_date: monday + 4)
        at(monday.to_time + 9.hours) { create(:work_package, project:, sprint:, assigned_to: ben) }
        at((monday + 4).to_time + 9.hours) { create_list(:work_package, 2, project:, type: bug) }
      end

      found = candidates(described_class).sole

      expect(found.recipient).to eq(lead)
      expect(found.facts[:patterns]).to include("late_defects")
    end
  end

  describe Assistant::Proactive::Detectors::RetroFollowUp do
    it "lists what the last retrospective said to do and whether it was done, for the host" do
      previous = create(:meeting, project:, author: lead, title: "Sprint 5 回顾会", start_time: now - 14.days)
      upcoming = create(:meeting, project:, author: lead, title: "Sprint 6 回顾会", start_time: now + 1.day)
      wp = create(:work_package, project:, assigned_to: ben, subject: "测试提前")
      create_intent(project:, subject: previous, owner: ben, title: "测试提前到第二周", work_package: wp)
      close!(wp, at: now - 2.days)
      create_intent(project:, subject: previous, owner: lead, title: "每日同步改到 10 点")

      found = candidates(described_class).sole

      expect(found).to have_attributes(recipient: lead, subject: upcoming)
      expect(found.headline).to include("1", "2")
      notes = found.options_for(lead).sole[:steps].sole["attributes"]["notes"]
      expect(notes).to include("测试提前到第二周", "每日同步改到 10 点")
    end
  end

  describe Assistant::Proactive::Detectors::Recognition do
    it "says when a long-standing problem was finally solved" do
      wp = at(now - 40.days) { create(:work_package, project:, assigned_to: ben, subject: "导出乱码") }
      close!(wp, at: now - 1.day)

      found = candidates(described_class).sole

      expect(found.recipient).to eq(lead)
      expect(found.because.join).to include("##{wp.id}", "Ben B")
    end
  end

  describe Assistant::Duties::DevilsAdvocate do
    it "puts the case against tomorrow's sprint on its planning meeting, from the facts" do
      allow(Assistant::Facts::Capacity).to receive(:new).and_return(instance_double(Assistant::Facts::Capacity, hours: 10.0, absences: []))
      sprint = create(:sprint, project:, start_date: today + 1, finish_date: today + 10)
      create(:work_package, project:, sprint:, assigned_to: ben, remaining_hours: 30)
      meeting = create(:meeting, project:, author: lead, title: "Sprint 计划会", start_time: now + 1.day)
      duty = Assistant::Duty.create!(project:, kind: "devils_advocate", delegator: lead)

      result = Assistant::Duties::Runner.new(duty, now:).call

      expect(result.produced).to be(true)
      action = Assistant::Action.find(result.action_ids.sole)
      step = action.steps.sole
      expect(step["attributes"]).to include("meeting_id" => meeting.id)
      expect(step["attributes"]["notes"]).to include("30.0", "10.0")
    end
  end
end
