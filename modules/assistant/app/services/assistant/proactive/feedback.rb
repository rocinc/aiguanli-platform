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
    # What became of each notice, and what the assistant learns from it
    # (03 §9): a rule a person keeps ignoring or rejecting needs a higher score
    # to interrupt them; a muted rule stops for them; a rule nobody takes up
    # across the project falls back to the brief; a person who never reacts to
    # interruptions gets fewer of them.
    module Feedback
      module_function

      WINDOW = 30.days
      MIN_SAMPLES = 5
      LOW_ADOPTION = 0.1
      # Fewer settled notices than this say nothing about a rule.
      RULE_SAMPLES = 10
      STEP = 10
      MAX_RAISE = 40
      IGNORED_AFTER = 7.days
      UNSEEN_AFTER = 14.days

      # Outcomes are written where people press the buttons (Decisions,
      # SignalsController); this reads them back once per sweep.
      def retune!(project, since: 1.day.ago)
        Assistant::Signal.where(project:).where(outcome_at: since..).distinct.pluck(:recipient_id, :detector)
                         .each { |recipient_id, detector| (user = User.find_by(id: recipient_id)) && tune!(user, detector) }
        Assistant::Signal.where(project:, state: "held", outcome: nil).where.not(snoozed_until: nil)
                         .where(updated_at: since..).distinct.pluck(:recipient_id, :detector)
                         .each { |recipient_id, detector| (user = User.find_by(id: recipient_id)) && tune!(user, detector) }
      end

      def seen!(signals)
        Assistant::Signal.where(id: Array(signals).map do
          it.respond_to?(:id) ? it.id : it
        end, seen_at: nil).update_all(seen_at: Time.current)
      end

      def expire_ignored!(project, now: Time.current)
        Assistant::Signal.live.where(project:, state: "delivered", seen_at: nil).where(delivered_at: ..(now - UNSEEN_AFTER))
                         .update_all(state: "expired")
        stale = Assistant::Signal.live.where(project:, state: "delivered").where(seen_at: ..(now - IGNORED_AFTER))
        pairs = stale.distinct.pluck(:recipient_id, :detector)
        stale.update_all(outcome: "ignored", outcome_at: now, state: "expired")
        pairs.each { |recipient_id, detector| (user = User.find_by(id: recipient_id)) && tune!(user, detector) }
      end

      def tune!(user, detector)
        rows = Assistant::Signal.judged.where(recipient: user, detector:).where(outcome_at: WINDOW.ago..)
        total = rows.count
        return if total < MIN_SAMPLES

        good = rows.where(outcome: Assistant::Signal::GOOD_OUTCOMES).count
        rate = good.fdiv(total)
        preference = Assistant::Preference.for(user)
        thresholds = preference.thresholds.dup
        current = thresholds.fetch(detector.to_s, 0).to_i
        thresholds[detector.to_s] = if rate < 0.25 then [current + STEP, MAX_RAISE].min
                                    elsif rate > 0.6 then [current - STEP, 0].max
                                    else current
                                    end
        preference.thresholds = thresholds
        preference.interrupt_cap = adapted_cap(user, preference)
        preference.save!
      end

      # Someone who mostly lets interruptions pass gets one fewer, down to one.
      # It never rises again on its own: their level, or their own setting,
      # is where that is decided.
      def adapted_cap(user, preference)
        return preference.interrupt_cap if preference.cap_chosen?

        interruptions = Assistant::Signal.where(recipient: user, channel: "notification").where(delivered_at: WINDOW.ago..)
        return preference.interrupt_cap if interruptions.count < MIN_SAMPLES

        answered = interruptions.where.not(outcome: [nil, "ignored"]).count.fdiv(interruptions.count)
        return preference.interrupt_cap if answered >= 0.2

        current = preference.interrupt_cap || Assistant::Preference::CAPS.fetch(preference.proactivity || "standard", 2)
        [current - 1, 1].max
      end

      # Notices people said were wrong ("the fact is wrong"), per rule: the
      # false alarms of the scorecard. Leaving it, declining it, taking back
      # what it did and saying it was not theirs are not false alarms.
      def false_alarms(project, since: WINDOW.ago)
        Assistant::Signal.where(project:, outcome: "wrong").where(outcome_at: since..).group(:detector).count
      end

      # Rules nobody in a project takes up (under 10% of at least ten settled
      # notices in 30 days): delivered only to the brief from now on, and
      # marked on the insights tab.
      def demoted_detectors(project)
        rows = Assistant::Signal.judged.where(project:).where(outcome_at: WINDOW.ago..)
        rows.group(:detector).count.filter_map do |detector, total|
          next if total < RULE_SAMPLES

          good = rows.where(detector:, outcome: Assistant::Signal::GOOD_OUTCOMES).count
          detector if good.fdiv(total) < LOW_ADOPTION
        end
      end
    end
  end
end
