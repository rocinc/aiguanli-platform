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
  module Proactive
    # The rules that decide whether there is anything to say. They are code:
    # no model is asked whether something happened (03 §3).
    module Detectors
      def self.all
        [CriticalSlip, VersionCheckpoint, Stalled, MergedNotAdvanced, MeetingDecisionNotApplied, ThirdReschedule,
         AbsenceRipple, AssignedWithHistory, DateChangeCascade, IdleCapacity, IdeaGarden,
         WeakDecision, CommitmentLadder, BurndownDrift, BudgetAhead, HoursOverEstimate,
         SaidDoneStillOpen, GreenButSlipping, DeferredStillInVersion, MeetingWithoutMinutes, ReviewWaiting,
         SystematicUnderestimate, RepeatedCheckFailure, MemberLeaving, SprintSqueeze, AllocationOverbooked,
         RepeatedQuestion, ThreadSettled, WikiContradictsDecision, UnansweredForumQuestion, DocumentConflictsDecision,
         CrossProjectReuse, Overlap, Matchmaker, PreMortem, CrossSprintPattern, RetroFollowUp, Recognition,
         MeetingPrep, BudgetBrief, PhaseGate, DeadlineCluster, WeeklyTimesheet, BoardBottleneck, CalendarCrunch,
         PortfolioHealth, SprintPlanningPrep, WikiStale, PossibleDuplicate,
         TimeEntryAnomaly, AssistantArrival, RequestWeigh, AssigneeChangeLoad, CloseWithOpenChildren,
         EstimateChangeEffect]
      end

      def self.fetch(name) = all.find { it.key == name.to_s }

      class Base
        def self.key = name.demodulize.underscore

        def initialize(project, today: Date.current, since: nil)
          @project = project
          @today = today
          @since = since || 1.day.ago
        end

        def candidates = raise NotImplementedError

        private

        attr_reader :project, :today, :since

        def candidate(**) = Candidate.build(detector: self.class.key, project:, **)

        def open_work_packages
          @open_work_packages ||= WorkPackage.where(project:).where.not(status_id: Assistant::Facts.closed_status_ids)
                                             .includes(:status, :assigned_to, :responsible).to_a
        end

        def graph = @graph ||= Assistant::Facts::ScheduleGraph.new(project)

        def leads = Routing.leads(project)

        def human?(user) = user.is_a?(User) && user.active? && !user.is_a?(AssistantUser)

        def page_top(subject)
          subject = subject.meeting if subject.is_a?(::MeetingAgendaItem)
          [::WorkPackage, ::Version, ::Meeting, ::WikiPage, ::Message].any? { subject.is_a?(it) } ? subject : project
        end

        HEADLINE_KEY = /headline|\Aowner_|\Awaiting\z/
        HEADLINE_LIMIT = 40
        MIN_KEPT = 6

        def t(key, **vars)
          text = I18n.t("assistant.proactive.#{self.class.key}.#{key}", **vars)
          key.to_s.match?(HEADLINE_KEY) && cjk? && text.length > HEADLINE_LIMIT ? fitted(key, vars, text) : text
        end

        def cjk? = I18n.locale.to_s.start_with?("zh", "ja", "ko")

        PERSON_KEY = /name\z|\A(who|person|owner|assignee|user|other|author|speaker)\z/
        CUT_AT = /[\s，。、；：,.;:!?！？）)」』]/

        # A main sentence stays within 40 characters (03 L6) by shortening the longest thing a person wrote into it.
        # People's names are never the part that gets shortened, and a cut never lands inside one.
        def fitted(key, vars, text)
          names = vars.select { |name, value| name.to_s.match?(PERSON_KEY) && value.is_a?(String) }.values
          name, written = vars.select { |k, value| value.is_a?(String) && !names.include?(value) && !k.to_s.match?(PERSON_KEY) }
                              .max_by { |_, value| value.length }
          kept = written.to_s.length - (text.length - HEADLINE_LIMIT)
          return text if name.nil? || kept < MIN_KEPT

          I18n.t("assistant.proactive.#{self.class.key}.#{key}", **vars, name => shorten(written, kept, names))
        end

        def shorten(written, limit, names)
          cut = limit - 1
          names.each do |person|
            at = written.index(person)
            cut = at if at && at < cut && cut < at + person.length
          end
          boundary = written.first(cut).rindex(CUT_AT)
          cut = boundary if boundary && boundary >= MIN_KEPT
          "#{written.first(cut).rstrip}…"
        end

        def ref(wp) = "##{wp.id} #{wp.subject}"

        def day(date) = date && Assistant::Text.day(date)

        def step(wp, attributes)
          { "op" => "update_work_package", "type" => "WorkPackage", "id" => wp.id, "attributes" => attributes }
        end

        def comment(wp, notes)
          { "op" => "comment", "as" => "person", "type" => "WorkPackage", "id" => wp.id, "attributes" => { "notes" => notes } }
        end

        def mention(user) = Assistant::Reasoning::StepBuilder.mention(user)

        def option(label, consequence, kind, steps) = { label:, consequence:, kind:, steps: }

        def shift(wp, days)
          return {} unless wp.due_date

          start = wp.start_date && Assistant::Facts.add_working_days(wp.start_date, days)
          { "start_date" => start&.iso8601, "due_date" => Assistant::Facts.add_working_days(wp.due_date, days).iso8601 }.compact
        end

        def free_member(from, to, hours, except: [])
          Routing.assignable(project, on: today).reject { except.include?(it.id) }
                 .map { [it, Assistant::Facts::Load.new(it, from, to, today:).free_hours] }
                 .select { _2 >= hours }.max_by(&:last)
        end

        # The next meeting of this project that is still to happen, before `by` when given.
        def next_meeting(by: nil, where: nil)
          scope = ::Meeting.where(project:, template: false).where.not(state: %i[cancelled closed])
                           .where(start_time: Time.current..).order(:start_time)
          scope = scope.where(start_time: ..by.end_of_day) if by
          where ? scope.detect(&where) : scope.first
        end

        def agenda_step(meeting, title, notes, minutes: nil)
          { "op" => "create_meeting_agenda_item",
            "attributes" => { "meeting_id" => meeting.id, "title" => title.truncate(250), "notes" => notes,
                              "duration_in_minutes" => minutes }.compact }
        end

        def wiki_step(title, text, notes: nil)
          { "op" => "create_wiki_page",
            "attributes" => { "project_id" => project.id, "title" => title.truncate(250), "text" => text, "notes" => notes }.compact }
        end

        def events(kind)
          Assistant::Event.where(project:, kind:).where(created_at: since..).by_humans.includes(:subject, :actor)
        end
      end
    end
  end
end
