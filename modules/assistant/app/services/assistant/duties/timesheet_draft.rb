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
    # The last working day of the week, mid-afternoon: for each member, time
    # entry drafts from what they said ("排查花了三小时") and, where they said
    # nothing, from the work packages they touched without logging, so one
    # click completes the week. Only the person themselves confirms their
    # time (T2 for the delegator's team, each draft offered to its owner).
    class TimesheetDraft < Base
      SAID = /(?:花了|用了|耗时|搞了|折腾了)\s*(\d+(?:\.\d+)?|半|一|两|三|四|五|六|七|八)\s*(?:个)?\s*(小时|h|钟头)|(\d+(?:\.\d+)?)\s*(?:h|hours?)\b/i
      WORDS = { "半" => 0.5, "一" => 1, "两" => 2, "三" => 3, "四" => 4, "五" => 5, "六" => 6, "七" => 7, "八" => 8 }.freeze

      def self.due?(duty, now = Time.current)
        date = local(duty, now).to_date
        last = date.end_of_week(:monday)
        last -= 1 until Assistant::Facts.working_day?(last) || last < date
        date == last && daily(duty, now, hour: 15)
      end

      def call
        week = today.beginning_of_week..today
        ids = Assistant::Proactive::Routing.people(project).flat_map { drafts_for(_1, week) }
        ids.any? ? Result.new(summary: "#{ids.size}", action_ids: ids, produced: true) : Result.nothing
      end

      # What one person's week is missing: [time entry steps from what they
      # said, work packages they touched without logging, because lines].
      def self.week_for(project, person, week)
        logged = TimeEntry.where(project:, user: person, spent_on: week).group(:entity_id).sum(:hours)
        said = said_hours(project, person, week)
        touched = touched(project, person, week) - logged.keys - said.keys
        steps = said.map do |wp_id, (hours, quote, on)|
          { "op" => "create_time_entry", "attributes" => { "work_package_id" => wp_id, "user_id" => person.id, "hours" => hours,
                                                          "spent_on" => on.iso8601, "comments" => quote.to_s.truncate(200) } }
        end
        unlogged = touched.first(5)
        because = [*said.map { |id, (h, q, _)| I18n.t("assistant.duties.timesheet_draft.said", ref: "##{id}", hours: h, quote: q.to_s.truncate(40)) },
                   (I18n.t("assistant.duties.timesheet_draft.unlogged", list: unlogged.map { "##{_1}" }.join("、")) if unlogged.any?)].compact
        [steps, unlogged, because]
      end

      def self.said_hours(project, person, week)
        Journal.where(journable_type: "WorkPackage", journable_id: WorkPackage.where(project:).select(:id), user_id: person.id)
               .where(created_at: week.first.beginning_of_day..week.last.end_of_day).where.not(notes: [nil, ""])
               .each_with_object({}) do |journal, found|
          text = Assistant::Text.plain(journal.notes)
          match = text.match(SAID) or next
          value = match[1] || match[3]
          hours = WORDS[value] || value.to_f
          next unless hours.positive? && hours <= 12

          found[journal.journable_id] = [hours, text[/[^。！？.!?\n]*#{Regexp.escape(match[0])}[^。！？.!?\n]*/] || text, journal.created_at.to_date]
        end
      end

      def self.touched(project, person, week)
        Journal.where(journable_type: "WorkPackage", journable_id: WorkPackage.where(project:, assigned_to_id: person.id).select(:id),
                      user_id: person.id).where(created_at: week.first.beginning_of_day..).distinct.pluck(:journable_id)
      end

      private

      def drafts_for(person, week)
        steps, unlogged, because = self.class.week_for(project, person, week)
        return [] if steps.empty? && unlogged.empty?
        return [] if Assistant::Signal.silenced?("duty_timesheet_draft", recipient: person, project:)

        action = steps.any? ? Assistant::Actions::Propose.call(
          kind: "timesheet_draft", title: I18n.t("assistant.duties.timesheet_draft.title", count: steps.size), steps:,
          on_behalf_of: person, project:, basis:, auto_execute: false
        ) : nil
        Assistant::Signal.create!(
          detector: "duty_timesheet_draft", fingerprint: "#{person.id}:#{today.cweek}", recipient: person, project:,
          subject: project, action:, channel: "brief", state: "pending", score: 0, deliver_at: now,
          payload: { "headline" => I18n.t("assistant.duties.timesheet_draft.headline", count: steps.size + unlogged.size),
                     "because" => because,
                     "options" => action ? [{ "label" => action.title, "action_id" => action.id }] : [] }
        )
        action ? [action.id] : []
      rescue ActiveRecord::RecordNotUnique
        []
      end
    end
  end
end
