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

RSpec.describe Assistant::IntentVerbs do
  shared_let(:project) do
    create(:project, enabled_module_names: %w[work_package_tracking meetings assistant])
  end
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_packages work_package_assigned
                                          add_work_package_comments view_meetings manage_agendas manage_outcomes use_assistant])
  end
  shared_let(:host) { create(:user, firstname: "Sam", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", member_with_roles: { project => role }) }
  shared_let(:ada) { create(:user, firstname: "Ada", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:) }

  let(:now) { Time.zone.local(2026, 10, 12, 10, 30) }
  let(:previous) { create(:meeting, project:, author: host, start_time: now - 3.days, state: :closed) }
  let(:current) { create(:meeting, project:, author: host, title: "Mid-sprint planning", start_time: now, duration: 1) }

  before { travel_to(now) }

  after { travel_back }

  def intent(kind: "commitment", **attributes)
    status = { "decision" => "active" }.fetch(kind, "open")
    create_intent(project:, subject: work_package, owner: ben, kind:, status:, work_package:, **attributes)
  end

  def verbs_for(thing, user: host, meeting: current) = described_class.new(thing, user, meeting:)

  describe "which verbs a kind has" do
    {
      "commitment" => { direct: %w[schedule assign], more: %w[remind shelve] },
      "deferral" => { direct: %w[schedule assign], more: %w[remind shelve] },
      "decision" => { direct: %w[record schedule], more: %w[shelve] },
      "question" => { direct: %w[answer assign], more: %w[schedule remind shelve] }
    }.each do |kind, expected|
      it "puts the two most used #{kind} verbs in front and the rest behind the menu" do
        verbs = verbs_for(intent(kind:))

        expect(verbs.direct).to eq(expected[:direct])
        expect(verbs.more).to eq(expected[:more])
      end
    end

    it "treats a question raised against a decision as an objection" do
      decision = intent(kind: "decision")
      objection = intent(kind: "question", parent: decision)

      expect(described_class.kind_of(objection)).to eq("objection")
    end

    it "offers nothing for what is already settled" do
      expect(verbs_for(intent(status: "done")).verbs).to be_empty
    end

    it "does not offer to remind someone when there is nobody else to remind" do
      expect(verbs_for(intent(owner: host)).verbs).not_to include("remind")
    end

    it "does not offer to hand something to someone to a person who may not edit" do
      reader = create(:user, member_with_roles: { project => create(:project_role, permissions: %i[view_work_packages view_meetings use_assistant]) })

      expect(verbs_for(intent, user: reader).verbs).not_to include("assign", "schedule")
    end
  end

  describe "meetings to schedule into" do
    it "puts this meeting first, then at most five later ones, and leaves out the meeting it is already on" do
      later = create_list(:meeting, 7, project:, author: host, start_time: now + 1.day)
      verbs = verbs_for(intent)

      expect(verbs.schedule_targets.first).to have_attributes(meeting: current, here: true)
      expect(verbs.schedule_targets.size).to eq(6)
      expect(verbs.schedule_targets.drop(1).map(&:meeting)).to all(satisfy { later.include?(it) })
    end

    it "does not offer a meeting that is over, cancelled or a template" do
      create(:meeting, project:, author: host, start_time: now + 1.day, state: :cancelled)
      create(:meeting, project:, author: host, start_time: now + 1.day, template: true)

      expect(verbs_for(intent).schedule_targets.map(&:meeting)).to eq([current])
    end

    it "remembers where it was put, and does not offer that meeting again" do
      thing = intent
      result = Assistant::IntentVerbs::Act.new(verbs_for(thing), "schedule", { meeting_id: current.id }).call

      expect(result.state).to eq(:done)
      fresh = verbs_for(thing)
      expect(fresh.scheduled.map(&:meeting)).to eq([current])
      expect(fresh.schedule_targets).to be_empty
    end
  end

  describe "whose words they were" do
    it "names the speakers only to someone who can open the place they were said" do
      thing = intent(counterparty: ada)
      outsider = create(:user)

      expect(described_class.speakers(thing, host)).to eq([ben, ada])
      expect(described_class.speakers(thing, outsider)).to eq([nil, nil])
    end
  end

  describe "people to hand it to" do
    it "lists the project's people alphabetically with what is left of their week, and who is away" do
      create(:user_non_working_time, user: ada, start_date: now.to_date, end_date: now.to_date + 8.days)
      people = verbs_for(intent).people

      expect(people.map { it.user.firstname }).to eq(%w[Ada Ben])
      expect(people.first.away_until).to eq(now.to_date + 8.days)
      expect(people.last.free_hours).to be >= 0
    end
  end

  describe "recording a result" do
    it "explains why not instead of failing when the meeting is not running" do
      expect(verbs_for(intent(kind: "decision")).outcome_reason).to eq(:not_started)
      current.update_columns(state: Meeting.states[:in_progress])
      expect(verbs_for(intent(kind: "decision"), meeting: current.reload).outcome_reason).to be_nil
      expect(verbs_for(intent(kind: "decision"), meeting: nil).outcome_reason).to eq(:no_meeting)
    end
  end
end
