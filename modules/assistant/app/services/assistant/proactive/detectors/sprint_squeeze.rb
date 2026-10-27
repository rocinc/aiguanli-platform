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

module Assistant
  module Proactive
    module Detectors
      # Work was pulled into a running sprint and its people now have more to
      # do than time left (04 A3). Whoever added it sees, on that work package,
      # what it crowds out: the least important open work of the same people
      # that no longer fits, with the move to the next sprint ready.
      class SprintSqueeze < Base
        def candidates
          return [] unless defined?(::Sprint)

          events("work_package.updated").select { it.changed?("sprint_id") && it.after("sprint_id") }.filter_map do |event|
            wp = event.subject
            sprint = ::Sprint.find_by(id: event.after("sprint_id"))
            actor = event.actor
            next unless wp.is_a?(WorkPackage) && actor.is_a?(User) && running?(sprint)

            squeeze = crowded_out(sprint, wp)
            next if squeeze[:over] <= 0

            build(event, wp, sprint, actor, squeeze)
          end
        end

        private

        def running?(sprint) = sprint&.start_date && sprint.finish_date && (sprint.start_date..sprint.finish_date).cover?(today)

        # For the people on the added work: hours over their time left, and
        # their lowest priority open work in the sprint that would cover it.
        def crowded_out(sprint, added)
          facts = Assistant::Facts::SprintFacts.new(sprint, today:)
          people = [added.assigned_to_id].compact
          over = facts.per_person.select { people.include?(it["user_id"]) }.sum { [-it["free"], 0].max }
          others = facts.open.select { people.include?(it.assigned_to_id) && it.id != added.id }
                        .sort_by { [it.priority&.position.to_i, -(it.due_date || sprint.finish_date).jd] }
          out = []
          others.each do |wp|
            break if out.sum { Assistant::Facts.remaining_hours(it) } >= over

            out << wp
          end
          { over: over.round(1), out: out.first(3) }
        end

        def build(event, wp, sprint, actor, squeeze)
          following = Assistant::Facts.next_sprint(sprint)
          candidate(
            fingerprint: "#{event.journal_id || event.id}", recipient: actor, subject: wp, nature: :decision, channel: "inline",
            headline: t("headline", ref: "##{wp.id}", sprint: sprint.name, hours: squeeze[:over]),
            because: [t("over", name: wp.assigned_to&.name || "–", hours: squeeze[:over], date: day(sprint.finish_date)),
                      (t("out", list: squeeze[:out].map { "##{it.id}" }.join(t("separator"))) if squeeze[:out].any?)].compact,
            impact: { cascade: squeeze[:out].size, people: 1 }, act_by: sprint.finish_date,
            facts: { since: event.created_at, sprint_id: sprint.id, over_hours: squeeze[:over] },
            steps_for: lambda do |_user|
              next [] if squeeze[:out].empty?

              target = { "sprint_id" => following&.id }
              [option(t("move", list: squeeze[:out].map do
                "##{it.id}"
              end.join(t("separator")), to: following&.name || t("backlog")),
                      t("move_consequence"), "cut_scope", squeeze[:out].map { step(it, target) })]
            end
          )
        end
      end
    end
  end
end
