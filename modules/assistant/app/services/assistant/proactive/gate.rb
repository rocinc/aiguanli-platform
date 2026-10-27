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
    # The five questions every candidate answers before anyone hears of it
    # (03 §3.2). The verdict says where it may go: interrupt, brief, or the
    # pool that is only shown when someone looks.
    class Gate
      Verdict = Data.define(:pass, :route, :score, :reasons) do
        def interrupt? = route == :interrupt

        def brief? = route == :brief

        def pool? = route == :pool
      end

      WEIGHTS = { critical_path: 30, external: 25, deadline: 25, contradiction: 25, cascade: 15, people: 5, money: 10 }.freeze
      INTERRUPT_SCORE = 40
      TOO_EARLY_WORKING_DAYS = 10
      ONCE_PER = 7.days
      # Its stages are the reminders (03 §5): two private asks at most, ever.
      OWN_CADENCE = %w[commitment_ladder].freeze

      def initialize(candidate, preference: nil, today: Date.current)
        @candidate = candidate
        @preference = preference || Assistant::Preference.effective(candidate.recipient, candidate.project)
        @today = today
      end

      def call
        reasons = []
        return verdict(false, :drop, 0, ["muted"]) if muted?
        return verdict(false, :drop, 0, ["already_said"]) if already_said? || said_this_week?
        return verdict(false, :drop, 0, ["already_known"]) if already_known? || said_known?
        return verdict(false, :drop, 0, ["not_theirs"]) if said_not_theirs?
        return verdict(false, :pool, 0, ["cannot_act"]) unless can_act?
        return verdict(false, :pool, 0, ["too_late"]) if too_late?
        return verdict(false, :pool, 0, ["cold_start"]) if cold_start?

        score = self.score
        route = if candidate.certainty != :fact
                  reasons << "uncertain"
                  :brief
                elsif too_early?
                  reasons << "early"
                  :brief
                elsif demoted_before?
                  reasons << "demoted_before"
                  :brief
                elsif score >= threshold
                  :interrupt
                else
                  :brief
                end
        verdict(true, route, score, reasons)
      end

      def score
        impact = candidate.impact
        WEIGHTS.sum do |key, weight|
          value = impact[key]
          case value
          when true then weight
          when Numeric then [value, 5].min * weight / (key == :people ? 1 : 5.0)
          else 0
          end
        end.round
      end

      private

      attr_reader :candidate, :preference, :today

      def verdict(pass, route, score, reasons) = Verdict.new(pass:, route:, score:, reasons:)

      def recipient = candidate.recipient

      def muted? = preference.muted?(candidate.detector)

      # The learning loop moves this per person and detector (§9).
      def threshold
        INTERRUPT_SCORE + preference.thresholds.fetch(candidate.detector.to_s, 0).to_i
      end

      def already_said?
        counted(Assistant::Signal.where(recipient:, detector: candidate.detector.to_s, fingerprint: candidate.fingerprint)).exists?
      end

      # What was kept back for being new is not counted as said once the
      # first weeks are over; it is weighed again like anything else.
      def counted(scope)
        Assistant::ColdStart.active?(candidate.project, today:) ? scope : scope.where.not(id: Assistant::Signal.cold_start_pool.select(:id))
      end

      # The same thing told to the same person again within a week, even in
      # new words (a new slip count, a later date), is not told. What appears
      # on the object itself is not a reminder.
      def said_this_week?
        return false if candidate.channel == "inline" || candidate.detector.to_s.in?(OWN_CADENCE)

        about_the_same.where(created_at: ONCE_PER.ago..).exists?
      end

      # Once it was moved to the brief instead of interrupting (budget used
      # up, or the rule demoted), the same thing does not interrupt later.
      def demoted_before?
        about_the_same.where(created_at: Assistant::Proactive::Feedback::WINDOW.ago..)
                      .where("payload ->> 'demoted' IS NOT NULL").exists?
      end

      def about_the_same
        subject = candidate.subject.is_a?(ActiveRecord::Base) ? candidate.subject : nil
        scope = Assistant::Signal.where(recipient:, detector: candidate.detector.to_s)
        counted(subject ? scope.where(subject:) : scope.where(fingerprint: candidate.fingerprint))
      end

      # "I already know" on this kind of notice about this object: not again.
      def said_known? = about_the_same.where(outcome: "known").exists?

      # "Not mine": it went to the next in line then, and goes there again.
      def said_not_theirs? = about_the_same.where(outcome: "not_mine").exists?

      # They touched it, wrote about it, read a notification about it or had
      # it open after the fact arose: they know (03 §3.2).
      def already_known?
        since = candidate.facts[:since] || candidate.facts["since"]
        subject = candidate.subject
        return false unless since && subject.is_a?(ActiveRecord::Base) && subject.respond_to?(:journals)

        since = since.to_time
        subject.journals.where(user: recipient).where(created_at: since..).exists? ||
          Notification.where(recipient:, resource: subject, read_ian: true).where(updated_at: since..).exists? ||
          Assistant::View.seen_since?(recipient, subject, since)
      end

      def can_act?
        return true if candidate.nature.in?(%i[opportunity decision]) && candidate.steps_for.nil?

        subject = candidate.subject
        allowed = case subject
                  when WorkPackage then recipient.allowed_in_work_package?(:edit_work_packages, subject) ||
                                        recipient.allowed_in_work_package?(:add_work_package_comments, subject)
                  when Project then recipient.allowed_in_project?(:view_project, subject)
                  else candidate.project.nil? || recipient.allowed_in_project?(:view_work_packages, candidate.project)
                  end
        allowed && (candidate.steps_for.nil? || candidate.options_for(recipient).any?)
      end

      # Nothing interrupts and nothing waits in the brief while it is new
      # (M1.1); what shows on the page where the person is working still does.
      def cold_start?
        candidate.channel != "inline" && Assistant::ColdStart.active?(candidate.project, today:)
      end

      def too_late?
        return false unless candidate.act_by

        Assistant::Facts.working_days_between(today, candidate.act_by) < candidate.effort_days.to_i
      end

      def too_early?
        return false unless candidate.act_by

        Assistant::Facts.working_days_between(today, candidate.act_by) > TOO_EARLY_WORKING_DAYS
      end
    end
  end
end
