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
  module Desk
    class InsightsComponent < ApplicationComponent
      include OpPrimer::ComponentHelpers
      include Assistant::QuietWords

      delegate :new_here?, :rules, :wrong, :held, :muted_rules, :missed, to: :scorecard

      def initialize(project:, user:)
        super()
        @project = project
        @user = user
      end

      attr_reader :project, :user

      def scorecard = @scorecard ||= Assistant::Proactive::Scorecard.new(project, user:)

      def rule_name(key) = t("assistant.insights.detectors.#{key}.title")

      def rule_what(key) = t("assistant.insights.detectors.#{key}.what")

      def said_line
        said = scorecard.said_count
        return t("assistant.insights.said.none") if said.zero?

        adopted = scorecard.adopted_count
        percent = scorecard.adoption_percent
        return t("assistant.insights.said.few", said:, adopted:) unless percent

        t("assistant.insights.said.enough", said:, adopted:, percent:)
      end

      def headline
        [said_line, t("assistant.insights.muted_count", count: muted_rules.size),
         t("assistant.insights.wrong_count", count: scorecard.wrong_count)].join(t("assistant.insights.joiner"))
      end

      def figures = [lead_line, density_line, saved_line, missed_line, cost_line]

      def rule_line(rule)
        parts = [t("assistant.insights.rule.said", said: rule.said, adopted: rule.adopted)]
        parts << t("assistant.insights.rule.muted") if rule.muted
        parts << t("assistant.insights.rule.demoted") if rule.demoted
        parts.join(t("assistant.insights.joiner"))
      end

      def candour_line
        candour = scorecard.candour
        return t("assistant.insights.candour.few", count: candour.comments) unless candour.per_hundred

        t("assistant.insights.candour.value", count: tidy(candour.per_hundred))
      end

      def candour_note
        return unless scorecard.candour.per_hundred
        return t("assistant.insights.candour.before_few") unless (change = scorecard.candour_change)

        before = tidy(scorecard.candour_before.per_hundred)
        t("assistant.insights.candour.#{change}", count: tidy(scorecard.candour_gap), before:)
      end

      def candour_how
        before = scorecard.candour_before
        t("assistant.insights.candour.how", comments: scorecard.candour.comments, promises: scorecard.candour.promises,
                                            before_comments: before.comments, before_promises: before.promises)
      end

      def missed_line
        return t("assistant.insights.missed.none") if missed.empty?

        t("assistant.insights.missed.value", count: missed.size)
      end

      def missed_due(entry) = t("assistant.insights.missed.due", day: Assistant::Text.day(entry.due_on))

      def wrong_line(entry) = t("assistant.insights.wrong_line", when: Assistant::Text.moment(entry.at))

      def left_alone
        [t("assistant.insights.set_aside", count: scorecard.set_aside_count),
         t("assistant.insights.undone", count: scorecard.undone_count)]
      end

      def held_reason(entry) = t("assistant.insights.held_reasons.#{entry.reason}")

      def held_time(entry) = Assistant::Text.stamp(entry.at)

      private

      def lead_line
        lead = scorecard.lead_days
        return t("assistant.insights.lead.few", count: lead[:count]) if lead[:count] < Assistant::Proactive::Scorecard::MIN_LEAD

        t("assistant.insights.lead.enough", days: tidy(lead[:average]))
      end

      def density_line
        density = scorecard.interruptions_per_person_day
        return t("assistant.insights.density.none") unless density

        t("assistant.insights.density.value", count: tidy(density), cap: scorecard.interruption_cap)
      end

      def saved_line
        minutes = scorecard.minutes_saved
        return t("assistant.insights.saved.none") if minutes.zero?

        time = if minutes < 60
                 t("assistant.insights.minutes", count: minutes)
               else
                 t("assistant.insights.hours", count: tidy(minutes / 60.0))
               end
        t("assistant.insights.saved.value", time:)
      end

      def cost_line
        tokens = scorecard.tokens
        return t("assistant.insights.cost.none") if tokens.zero?

        t("assistant.insights.cost.tokens", count: helpers.number_with_delimiter(tokens, delimiter: ","))
      end

      def tidy(number)
        rounded = number.to_f.round(1)
        rounded == rounded.to_i ? rounded.to_i : rounded
      end
    end
  end
end
