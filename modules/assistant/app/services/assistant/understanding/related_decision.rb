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
  module Understanding
    # While a meeting runs, an agenda item that reads like a decision already
    # on record (S6.2): one line for the host asking whether it is the same
    # matter, and if so, a note under the item that it continues that decision.
    # Only the host can say; the others see nothing.
    class RelatedDecision
      DETECTOR = "meeting_related_decision"

      def self.offer(agenda_item) = new(agenda_item).call

      def initialize(agenda_item)
        @agenda_item = agenda_item
      end

      def call
        return unless meeting.in_progress?

        host = decider or return
        return if Assistant::Signal.silenced?(DETECTOR, recipient: host, project:)

        decision = related(host) or return
        return if Assistant::Signal.exists?(detector: DETECTOR, fingerprint: fingerprint(decision))

        OpenProject::LocaleHelper.with_locale_for(host) do
          action = propose(decision, host)
          signal!(decision, host, action) unless action.status == "failed"
        end
      end

      private

      def meeting = @agenda_item.meeting

      def project = meeting.project

      def decider
        [meeting.author, @agenda_item.presenter].find do
          it.is_a?(User) && it.active? && !it.is_a?(AssistantUser) && it.allowed_in_project?(:manage_outcomes, project)
        end
      end

      def related(host)
        text = "#{@agenda_item.title} #{Assistant::Text.plain(@agenda_item.notes)}"
        Assistant::Said.new(host).related_decisions(project, text, limit: 3).detect do |decision|
          decision.subject != meeting && [decision.source, decision.source.try(:meeting_agenda_item)].exclude?(@agenda_item)
        end
      end

      def fingerprint(decision, channel = "inline") = "#{@agenda_item.to_gid}|#{decision.id}|#{channel}"

      def day(decision) = Assistant::Text.day(decision.stated_at.to_date)

      def propose(decision, host)
        Assistant::Actions::Propose.call(
          kind: "meeting_decision_link", title: I18n.t("assistant.meeting_recap.related.option"),
          steps: [{ "op" => "create_meeting_outcome",
                    "attributes" => { "agenda_item_id" => @agenda_item.id, "kind" => "information",
                                      "notes" => I18n.t("assistant.meeting_recap.related.note", date: day(decision),
                                                                                                title: decision.title.truncate(80)) } }],
          on_behalf_of: host, project:, subject: meeting, basis: [Assistant::Basis.for(decision.source, quote: decision.quote)],
          auto_execute: false
        )
      end

      def signal!(decision, host, action)
        Assistant::Signal.offer!(
          detector: DETECTOR, fingerprint: fingerprint(decision), recipient: host, project:, subject: meeting, action:,
          channel: "inline", state: "pending", score: 15, deliver_at: Time.current,
          payload: { "headline" => I18n.t("assistant.meeting_recap.related.headline", date: day(decision),
                                                                                       title: decision.title.truncate(30)),
                     "because" => ["“#{decision.quote}”"], "why" => "hosts", "nature" => "decision",
                     "options" => [{ "label" => action.title, "action_id" => action.id,
                                     "consequence" => I18n.t("assistant.meeting_recap.related.consequence", date: day(decision)) }],
                     "source_gid" => @agenda_item.to_gid.to_s }
        )
        Assistant::SourceSignalsComponent.broadcast_reload(@agenda_item, [host])
      rescue ActiveRecord::RecordNotUnique
        nil
      end
    end
  end
end
