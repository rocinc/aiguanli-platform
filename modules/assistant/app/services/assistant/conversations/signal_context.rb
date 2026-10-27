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
  module Conversations
    class SignalContext < Context
      def visible_to?(user) = record.recipient_id == user.id

      def title(_user) = Assistant::Text.plain(record.headline.to_s).squish.truncate(70)

      def chips(_user) = I18n.t("assistant.thread.chips.notice")

      def body(user)
        [headline, rule, why, subject_line, basis, facts, options(user), state].compact.join("\n")
      end

      def follow(conversation)
        return false unless record.outcome.nil? && record.subject.is_a?(WorkPackage) && changed_subject?(conversation)

        offered = [record.action_id, *record.options.filter_map { it["action_id"] }].compact
        Assistant::Action.proposed.where(id: offered).update_all(status: "superseded")
        record.settle!("resolved", stale_reason: I18n.t("assistant.thread.settled_reason", ref: "##{record.subject_id}",
                                                                                         locale: record.recipient.language.presence || I18n.locale))
        true
      end

      def copies(user)
        Assistant::NoticeComponent::DENSITIES.map do |density|
          [Assistant::NoticeComponent.selector(record, density), Assistant::NoticeComponent.new(signal: record.reload, user:, density:)]
        end
      end

      private

      def changed_subject?(conversation)
        executed_in(conversation).any? do |action|
          action.steps.any? { it["op"] == "update_work_package" && it["id"].to_i == record.subject_id }
        end
      end

      def headline = say("headline", text: line(record.headline))

      def rule
        say("rule", detector: record.detector, nature: record.payload["nature"] || "object",
                    certainty: say(record.likely? ? "likely" : "certain"))
      end

      def why = record.why_me.presence&.then { say("why", text: it) }

      def subject_line = describe(record.subject)&.then { say("subject", text: it) }

      def basis
        lines = record.because.compact_blank.first(6).map { "- #{line(it)}" }
        [say("basis"), *lines].join("\n") if lines.any?
      end

      def facts
        pairs = record.payload["facts"].to_h.reject { |_, value| value.blank? || value.is_a?(Hash) }
        say("facts", text: pairs.map { |name, value| "#{name}: #{value}" }.join("; ")) if pairs.any?
      end

      def options(user)
        offered = record.options.select { it.is_a?(Hash) }.first(5)
        return say("no_options") if offered.empty?

        lines = offered.map { option_line(it, user) }
        [say("options"), *lines].join("\n")
      end

      def option_line(option, user)
        action = Assistant::Action.find_by(id: option["action_id"]) if option["action_id"]
        effect = option["consequence"].presence || option_summary(action, user)
        parts = [line(option["label"]), (effect && "would do: #{line(effect)}"),
                 (action && "action #{action.id}, #{action.status}, #{action.tier}"),
                 (action && affected(action, user))].compact
        "- #{parts.join(' | ')}"
      end

      def affected(action, user)
        names = action.affected_users.reject { it == user }.map(&:name)
        "touches #{names.to_sentence}" if names.any?
      end

      def state
        if record.outcome.present? then say("settled", outcome: record.outcome)
        elsif record.snoozed_until.present? then say("snoozed", until: record.snoozed_until.to_date.iso8601)
        end
      end
    end
  end
end
