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
    module Detectors
      # Someone raised the time left on a work package (04 A1 决策时刻).
      # Whoever did it sees what it does to the assignee: the room left in
      # the running sprint, or the hours before the due date, with the move
      # that restores it.
      class EstimateChangeEffect < Base
        def candidates
          events("work_package.updated").select {
 it.changed?("estimated_hours") || it.changed?("remaining_hours") }.filter_map do |event|
            wp = event.subject
            owner = wp.try(:assigned_to)
            next unless wp.is_a?(WorkPackage) && Assistant::Facts.open?(wp) && human?(event.actor) && human?(owner)

            added = added_hours(event, wp)
            next unless added.positive?

            effect = sprint_effect(wp, owner) || due_effect(wp, owner)
            build(event, wp, owner, added, effect) if effect
          end
        end

        private

        def added_hours(event, wp)
          key = if event.changed?("remaining_hours") then "remaining_hours"
                elsif wp.remaining_hours.nil? then "estimated_hours"
                end
          key ? event.after(key).to_f - event.before(key).to_f : 0
        end

        def sprint_effect(wp, owner)
          sprint = wp.try(:sprint)
          return unless sprint&.start_date && sprint.finish_date && (sprint.start_date..sprint.finish_date).cover?(today)

          free = Assistant::Facts::SprintFacts.new(sprint, today:).per_person.find { it["user_id"] == owner.id }&.dig("free")
          { kind: :sprint, sprint:, free: } if free&.negative?
        end

        def due_effect(wp, owner)
          return unless wp.due_date && wp.due_date >= today

          load = Assistant::Facts::Load.new(owner, today, wp.due_date, exclude: [wp.id], today:)
          short = (Assistant::Facts.remaining_hours(wp) - load.free_hours).round(1)
          { kind: :due, short:, load: } if short.positive?
        end

        def build(event, wp, owner, added, effect)
          candidate(
            fingerprint: event.journal_id.to_s, recipient: event.actor, subject: wp, nature: :decision, channel: "inline",
            headline: headline(wp, owner, effect),
            because: [t("added", ref: "##{wp.id}", hours: Assistant::Text.hours(added), left: Assistant::Text.hours(Assistant::Facts.remaining_hours(wp))),
                      (effect[:load].because if effect[:load]&.entries&.any?)].compact,
            impact: { people: 1, cascade: graph.downstream(wp.id).size }, facts: { journal_id: event.journal_id, field: event.changed?("estimated_hours") ? "estimatedTime" : "remainingTime" },
            steps_for: ->(_user) { options(wp, owner, effect) }
          )
        end

        def headline(wp, owner, effect)
          if effect[:kind] == :sprint
            t("headline_sprint", ref: "##{wp.id}", hours: Assistant::Text.hours(Assistant::Facts.remaining_hours(wp)),
                                 sprint: effect[:sprint].name, name: Assistant::Text.first_name(owner),
                                 free: Assistant::Text.hours(effect[:free]))
          else
            t("headline_due", ref: "##{wp.id}", name: Assistant::Text.first_name(owner), date: day(wp.due_date),
                              short: Assistant::Text.hours(effect[:short]))
          end
        end

        def options(wp, owner, effect)
          effect[:kind] == :sprint ? sprint_options(wp, effect) : due_options(wp, owner, effect)
        end

        def sprint_options(wp, effect)
          following = Assistant::Facts.next_sprint(effect[:sprint])
          return [] unless following

          back = (effect[:free] + Assistant::Facts.remaining_hours(wp)).round(1)
          [option(t("next_sprint", ref: "##{wp.id}", name: following.name), t("next_sprint_consequence", hours: Assistant::Text.hours(back)),
                  "cut_scope", [step(wp, { "sprint_id" => following.id })])]
        end

        def due_options(wp, owner, effect)
          capacity = Assistant::Facts::Capacity.new(owner, today, wp.due_date).hours
          daily = capacity / [Assistant::Facts.working_days_between(today, wp.due_date), 1].max
          return [] unless daily.positive?

          days = (effect[:short] / daily).ceil
          moved = shift(wp, days)
          return [] if moved.empty?

          [option(t("push_due", date: day(Date.iso8601(moved["due_date"]))),
                  t("push_due_consequence", count: graph.downstream(wp.id).size), "reschedule", [step(wp, moved)])]
        end
      end
    end
  end
end
