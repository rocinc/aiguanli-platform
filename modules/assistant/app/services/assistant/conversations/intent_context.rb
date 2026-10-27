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
    # One thing someone said that the assistant keeps (a promise, a deferral,
    # a decision, a question), as the person pressed "say something" on it.
    # Whoever can open the words it came from may talk about it.
    class IntentContext < Context
      def visible_to?(user)
        Assistant::Intent.visible(user).exists?(record.id) && Assistant::IntentVerbs.source_visible?(record, user)
      end

      def title(_user) = line(record.title).truncate(70)

      def chips(_user) = I18n.t("assistant.thread.chips.intent")

      def material(user)
        text = [I18n.t("assistant.thread.material.intent_lead", locale: :en), body(user)].join("\n")
        text.truncate(MATERIAL_LIMIT, separator: "\n")
      end

      def body(user)
        work_package = work_package_for(user)
        [headline, source, people, subject_line, dates(work_package), moves, links(user), state].compact.join("\n")
      end

      private

      def work_package_for(user)
        candidate = record.work_package || (record.subject if record.subject.is_a?(WorkPackage))
        candidate if candidate&.visible?(user)
      end

      def headline
        say("intent_headline", kind: Assistant::IntentVerbs.kind_of(record), strength: record.strength, status: record.status,
                               quote: line(record.quote), title: line(record.title))
      end

      def source
        say("intent_source", text: Assistant::Basis.describe(record.source), day: record.stated_at.to_date.iso8601)
      rescue StandardError
        nil
      end

      def people
        owner = record.owner
        other = record.counterparty
        return say("intent_nobody") unless owner || other

        parts = [(say("intent_owner", name: owner.name) if owner), (say("intent_other", name: other.name) if other)]
        parts.compact.join(" ")
      end

      def subject_line = describe(record.subject)&.then { say("intent_about", text: it) }

      def dates(work_package)
        named = [record.said_due_on&.iso8601, record.said_due_expression.presence&.then { "\"#{it}\"" }].compact.join(" ")
        named = "none" if named.empty?
        return say("intent_said_date", date: named) unless work_package

        say("intent_work_package", text: describe(work_package), said: named)
      end

      def moves
        say("intent_moves", count: record.moves) if record.moves.positive?
      end

      def links(user)
        scheduled = Assistant::IntentVerbs.new(record, user).scheduled.map { "\"#{line(it.meeting.title)}\" on #{it.meeting.start_time.to_date.iso8601}" }
        lines = []
        lines << say("intent_scheduled", text: scheduled.to_sentence) if scheduled.any?
        answered = record.answered_by
        lines << say("intent_answered", text: describe(answered) || answered.class.name) if answered
        lines << say("intent_objections", count: record.open_objections.count) if record.open_objections.exists?
        lines << say("intent_replaces", text: line(record.supersedes.title)) if record.supersedes
        lines.presence&.join(" ")
      end

      def state
        say("intent_closed", status: record.status) unless record.live?
      end
    end
  end
end
