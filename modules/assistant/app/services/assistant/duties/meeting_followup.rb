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
  module Duties
    # After a meeting closes: minutes drafted from its agenda, notes and
    # outcomes into the meeting's own wiki page. Action items nobody took are
    # offered under their agenda item (UnownedItems). The next meeting's
    # "last time" list is read off the same intents.
    class MeetingFollowup < Base
      SYSTEM = <<~PROMPT
        You write the minutes of a meeting from its agenda items, notes, outcomes and the coordination
        acts recorded from it. Return {"minutes": "Markdown"} with: attendees if given; per agenda item
        2–3 lines of what was discussed, decisions (exact words), action items with owner and date;
        open questions; next meeting if known. Only what the material says.
      PROMPT

      def self.due?(duty, now = Time.current) = every(duty, now, 30.minutes)

      def call
        meetings = ::Meeting.where(project:, state: closed_states).where(updated_at: (duty.last_run_at || 2.days.ago)..)
        ids = meetings.flat_map { follow_up(it) }
        ids.any? ? Result.new(summary: "#{meetings.size}", action_ids: ids, produced: true) : Result.nothing
      end

      private

      def closed_states = ::Meeting.states.slice("closed").values.presence || [5]

      def follow_up(meeting)
        return [] if Assistant::Action.where(kind: "meeting_minutes", subject: meeting).exists?

        actions = []
        minutes_action = self.class.minutes_action(meeting, user: delegator, llm: @llm, basis:)
        if minutes_action
          offer(minutes_action, headline: minutes_action.title, subject: meeting)
          actions << minutes_action
        end
        actions.map(&:id)
      end

      # The minutes of one meeting as a wiki page waiting for the host.
      def self.minutes_action(meeting, user:, llm: nil, basis: [])
        minutes = OpenProject::LocaleHelper.with_locale_for(user) { minutes_text(meeting, user:, llm:) }
        return if minutes.blank?

        action = Assistant::Actions::Propose.call(
          kind: "meeting_minutes", subject: meeting, project: meeting.project, on_behalf_of: user, auto_execute: false,
          title: I18n.t("assistant.duties.meeting_followup.title", meeting: meeting.title, locale: user.language.presence),
          steps: [minutes_step(meeting, minutes, user:)],
          basis: [Assistant::Basis.for(meeting.agenda_items.first || meeting), *basis].uniq
        )
        action.status == "failed" ? nil : action
      end

      def self.minutes_step(meeting, text, user:)
        date = meeting.start_time ? Assistant::Text.day(meeting.start_time.to_date) : ""
        page = I18n.t("assistant.duties.meeting_followup.page", meeting: meeting.title, date:, locale: user.language.presence)
        { "op" => "create_wiki_page",
          "attributes" => { "project_id" => meeting.project_id, "title" => page.truncate(250), "text" => text } }
      end

      def self.minutes_text(meeting, user:, llm: nil)
        material = minutes_material(meeting)
        return outline(material) unless Assistant::Llm.configured? && !Assistant::Usage.near_budget?(project: meeting.project)

        llm ||= Assistant::Llm.new(purpose: "duty_meeting_followup", user:, project: meeting.project)
        edits = Assistant::Revisions.examples(user, "meeting_followup", "meeting_minutes")
        material = material.merge("earlier_edits" => edits) if edits.any?
        text = llm.json(system: "#{SYSTEM}\nWrite in this language: #{I18n.locale}. Never quote the field names of the material; " \
                                "say what they mean. Answer as JSON.#{EDITS_HINT if edits.any?}", user: JSON.generate(material),
                        max_tokens: 3500)["minutes"]
        text.to_s.strip.presence || outline(material)
      rescue Assistant::Llm::Error
        outline(material)
      end

      def self.minutes_material(meeting)
        { "meeting" => meeting.title, "on" => meeting.start_time&.to_date&.iso8601,
          "participants" => meeting.participants.includes(:user).filter_map { it.user&.name },
          "items" => meeting.agenda_items.map do |item|
            { "title" => item.title, "presenter" => item.presenter&.name, "notes" => Assistant::Text.plain(item.notes),
              "outcomes" => item.outcomes.map do |outcome|
                { "kind" => outcome.kind, "notes" => Assistant::Text.plain(outcome.notes), "work_package" => outcome.work_package_id }
              end }
          end,
          "said" => Assistant::Intent.where(subject: meeting).map do |item|
            { "kind" => item.kind, "title" => item.title, "owner" => item.owner&.name, "due" => item.said_due_on&.iso8601 }
          end }
      end

      # Without a model: the agenda as headings, with what was written under each.
      def self.outline(material)
        items = material["items"].map do |item|
          lines = [item["notes"], *item["outcomes"].map { it["notes"] }].compact_blank.map { "- #{it}" }
          ["### #{item['title']}#{" (#{item['presenter']})" if item['presenter']}", *lines].join("\n")
        end
        said = material["said"].map { "- #{it['title']}#{" (#{it['owner']})" if it['owner']}#{", #{it['due']}" if it['due']}" }
        ["## #{material['meeting']} #{material['on']}", *items,
         (["### #{I18n.t('assistant.duties.meeting_followup.said')}", *said].join("\n") if said.any?)]
          .compact.join("\n\n")
      end
    end
  end
end
