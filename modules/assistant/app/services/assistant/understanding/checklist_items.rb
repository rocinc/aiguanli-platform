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
    # The agenda items the assistant wrote as a list of causes or patterns
    # (the pre-mortem, a problem that keeps coming back): under the item, one
    # line offering to turn the list into work packages in one go, each listed
    # in the preview, none assigned yet.
    class ChecklistItems
      DETECTOR = "meeting_checklist"
      KINDS = %w[pre_mortem pattern_agenda].freeze
      LIMIT = 5
      ENTRY = /\A\s*[-*]\s+\[[ xX]\]\s+(?<text>.+?)\s*\z/
      WORK_PACKAGE_REFERENCE = /(?<![A-Za-z0-9_&\/])#\d+/

      def self.offer(action) = new(action).call

      def initialize(action)
        @action = action
      end

      def call
        return unless KINDS.include?(@action.kind) && @action.executed?

        item = agenda_item or return
        recipient = [@action.on_behalf_of, item.meeting.author].find { allowed?(it, item.meeting.project) } or return
        return if Assistant::Signal.silenced?(DETECTOR, recipient:, project: item.meeting.project)

        entries = entries(item)
        return if entries.empty?

        OpenProject::LocaleHelper.with_locale_for(recipient) do
          proposed = propose(item, entries, recipient)
          signal!(item, recipient, proposed, entries.size) unless proposed.status == "failed"
        end
      end

      private

      def agenda_item
        entry = @action.inverse.detect { it["type"] == "MeetingAgendaItem" && it["created"] }
        MeetingAgendaItem.includes(:meeting).find_by(id: entry["id"]) if entry
      end

      def allowed?(user, project)
        user.is_a?(User) && user.active? && !user.is_a?(AssistantUser) && user.allowed_in_project?(:add_work_packages, project)
      end

      # Only checkbox lines are tasks. A line that names a work package is a
      # fact about it (overdue, unowned), not something to do.
      def entries(item)
        item.notes.to_s.lines.filter_map { ENTRY.match(it)&.[](:text) }.grep_v(WORK_PACKAGE_REFERENCE).first(LIMIT)
      end

      def propose(item, entries, recipient)
        Assistant::Actions::Propose.call(
          kind: "meeting_action_item", title: I18n.t("assistant.meeting_recap.checklist.option", count: entries.size),
          steps: entries.map { step(item, it) }, on_behalf_of: recipient, project: item.meeting.project, subject: item.meeting,
          basis: [Assistant::Basis.for(item)], auto_execute: false
        )
      end

      def step(item, text)
        { "op" => "create_work_package",
          "attributes" => { "project_id" => item.meeting.project_id, "subject" => text.truncate(200) } }
      end

      def signal!(item, recipient, proposed, count)
        options = [{ "label" => proposed.title, "action_id" => proposed.id,
                     "consequence" => I18n.t("assistant.meeting_recap.checklist.consequence", count:) }]
        Assistant::Signal.offer!(
          detector: DETECTOR, fingerprint: "#{item.to_gid}|inline", recipient:, project: item.meeting.project,
          subject: item.meeting, action: proposed, channel: "inline", state: "pending", score: 15, deliver_at: Time.current,
          payload: { "headline" => I18n.t("assistant.meeting_recap.checklist.headline", count:), "because" => [item.title],
                     "why" => "leads", "nature" => "decision", "options" => options, "source_gid" => item.to_gid.to_s }
        )
        Assistant::SourceSignalsComponent.broadcast_reload(item, [recipient])
      rescue ActiveRecord::RecordNotUnique
        nil
      end
    end
  end
end
