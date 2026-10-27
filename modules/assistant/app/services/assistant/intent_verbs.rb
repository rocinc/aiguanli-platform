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

module Assistant
  # What can be done with something the assistant remembers someone said,
  # one set for every place that shows it: put it on a meeting's agenda, hand
  # it to someone, remind someone of it, record the answer, set it aside.
  # What a verb needs (meetings, people, a place to write) is read here; what
  # it does is in IntentVerbs::Act.
  class IntentVerbs
    ORDER = {
      "commitment" => %w[schedule assign remind shelve],
      "deferral" => %w[schedule assign remind shelve],
      "decision" => %w[record schedule shelve],
      "question" => %w[answer assign schedule remind shelve],
      "objection" => %w[answer assign schedule remind shelve]
    }.freeze

    DIRECT = 2
    UPCOMING_MEETINGS = 5
    PEOPLE_LIMIT = 30
    OPEN_MEETING_STATES = %w[open in_progress].freeze

    Candidate = Data.define(:meeting, :here)
    Person = Data.define(:user, :free_hours, :away_until)
    Scheduled = Data.define(:action, :meeting, :agenda_item_id)

    def self.kind_of(intent) = intent.kind == "question" && intent.parent_id ? "objection" : intent.kind

    def self.speakers(intent, viewer)
      return [nil, nil] unless viewer&.logged? && source_visible?(intent, viewer)

      [intent.owner, intent.counterparty]
    end

    def self.source_visible?(intent, viewer)
      source = intent.source
      return source.meeting_agenda_item&.meeting&.visible?(viewer) if source.is_a?(MeetingOutcome)

      Assistant::Marks.visible_source?(source, viewer)
    end

    def initialize(intent, user, meeting: nil, today: Date.current, lead: nil)
      @intent = intent
      @user = user
      @meeting = meeting
      @today = today
      @lead = lead
    end

    attr_reader :intent, :user, :meeting, :today

    def kind = self.class.kind_of(intent)

    delegate :project, to: :intent

    def verbs = @verbs ||= intent.live? ? ordered.select { available?(it) } : []

    def direct(limit = DIRECT) = verbs.first(limit)

    def more(limit = DIRECT) = verbs.drop(limit)

    # Whose it is to the person looking: their own to keep or answer, or
    # someone else's to them. A promise is not reminded to its maker and not
    # handed on by the one it was made to; a question is not reminded to the
    # one who has to answer it.
    def stance
      return :maker if intent.owner_id == user.id && intent.commitment_like?
      return :receiver if intent.counterparty_id == user.id && intent.owner_id != user.id

      :third
    end

    def available?(verb)
      return false if verb == "remind" && (stance == :maker || (stance == :receiver && !intent.commitment_like?))
      return false if verb == "assign" && stance == :receiver && intent.commitment_like?

      case verb
      when "schedule" then schedule_targets.any?
      when "assign" then assignable? && assignable_users.any?
      when "remind" then place.present? && remind_targets.any?
      when "record" then meeting.present?
      when "answer" then place.present? || meeting.present?
      when "shelve" then true
      end
    end

    def work_package
      return @work_package if defined?(@work_package)

      candidate = intent.work_package || (intent.subject if intent.subject.is_a?(WorkPackage))
      @work_package = candidate if candidate&.visible?(user)
    end

    # Where words about this can be written down: the work package or the
    # forum thread it came from.
    def place
      return @place if defined?(@place)

      @place = if work_package && user.allowed_in_work_package?(:add_work_package_comments, work_package)
                 work_package
               elsif intent.subject.is_a?(::Message) && user.allowed_in_project?(:view_messages, project)
                 intent.subject
               end
    end

    def assignable?
      return user.allowed_in_work_package?(:edit_work_packages, work_package) if work_package && intent.commitment_like?
      return user.allowed_in_project?(:add_work_packages, project) if intent.commitment_like?

      place.present?
    end

    def schedule_targets
      @schedule_targets ||= begin
        taken = scheduled.map { it.meeting.id }
        here = meeting if schedulable?(meeting) && taken.exclude?(meeting.id)
        others = upcoming_meetings(except: [meeting&.id, *taken])
        [*here&.then { Candidate.new(it, true) }, *others.map { Candidate.new(it, false) }]
      end
    end

    def scheduled
      @scheduled ||= intent_actions("schedule").executed.order(:executed_at).filter_map do |action|
        found = action.subject
        next unless found.is_a?(Meeting) && found.visible?(user)

        entry = action.inverse.detect { it["type"] == "MeetingAgendaItem" && it["created"] }
        Scheduled.new(action:, meeting: found, agenda_item_id: entry&.fetch("id"))
      end
    end

    def people
      @people ||= begin
        assignable_users.map do |person|
          reading = Assistant::PersonLoad.of(person, today:)
          Person.new(user: person, free_hours: reading.free_hours, away_until: reading.away_until)
        end
      end
    end

    def remind_targets
      @remind_targets ||= [intent.owner, intent.counterparty, work_package&.assigned_to]
                          .compact.uniq.select { it.is_a?(User) && it.active? && it != user && !it.is_a?(AssistantUser) }
    end

    def outcome_reason
      return :no_meeting unless meeting
      return :not_started if meeting.open? || meeting.draft?
      return :over unless meeting.in_progress?
      return :forbidden unless user.allowed_in_project?(:manage_outcomes, meeting.project)

      nil
    end

    def agenda_items
      @agenda_items ||= if meeting
                          meeting.agenda_items.includes(:work_package).sort_by do
                            [it.meeting_section&.position.to_i, it.position.to_i]
                          end
                        else
                          []
                        end
    end

    def agenda_item_for(candidate_meeting)
      entry = scheduled.find { it.meeting == candidate_meeting }
      candidate_meeting.agenda_items.find_by(id: entry.agenda_item_id) if entry&.agenda_item_id
    end

    def intent_actions(verb)
      Assistant::Action.where(project_id: intent.project_id)
                       .where("plan -> 'intent' ->> 'id' = ? AND plan -> 'intent' ->> 'verb' = ?", intent.id.to_s, verb)
    end

    def drafts
      Assistant::Action.proposed.where(on_behalf_of_id: user.id)
                       .where("plan -> 'intent' ->> 'id' = ?", intent.id.to_s).order(:created_at)
    end

    private

    LEADS = { maker: "assign", receiver: "remind" }.freeze

    def ordered
      order = ORDER.fetch(kind)
      first = @lead || LEADS[stance]
      first && order.include?(first) ? [first, *(order - [first])] : order
    end

    def schedulable?(candidate)
      candidate.present? && !candidate.template? && candidate.state.in?(OPEN_MEETING_STATES) &&
        candidate.project_id == intent.project_id && user.allowed_in_project?(:manage_agendas, candidate.project)
    end

    def upcoming_meetings(except:)
      return [] unless user.allowed_in_project?(:manage_agendas, project)

      ::Meeting.visible(user).where(project:, template: false, state: OPEN_MEETING_STATES)
               .where.not(id: except.compact)
               .where("meetings.start_time + (interval '1 hour' * meetings.duration) >= ?", Time.current)
               .order(:start_time).limit(UPCOMING_MEETINGS).to_a
    end

    def assignable_users
      @assignable_users ||= Principal.possible_assignee(project).where(type: "User", status: Principal.statuses[:active])
                                     .where.not(id: user.id).to_a.sort_by { it.name.downcase }.first(PEOPLE_LIMIT)
    end
  end
end
