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
      # A running sprint whose remaining work is 30% or more above its ideal
      # line (03 §3.1, 04 A3): told to whoever leads, with the two ways out —
      # take the least important open items out of the sprint, or let someone
      # with room take one over.
      class BurndownDrift < Base
        DRIFT = 30

        def candidates
          return [] unless defined?(::Sprint)

          ::Sprint.where(project:).where.not(start_date: nil).where.not(finish_date: nil)
                  .where("start_date <= :today AND finish_date > :today", today:).flat_map do |sprint|
            burn = Assistant::Facts::SprintBurn.new(sprint, today:)
            next [] unless burn.running? && burn.elapsed.positive? && burn.drift && burn.drift >= DRIFT.fdiv(100)

            leads.map { build(sprint, burn, it) }
          end
        end

        private

        def build(sprint, burn, lead)
          percent = (burn.drift * 100).round
          candidate(
            fingerprint: "#{sprint.id}:#{percent / 10}", recipient: lead, subject: project, nature: :team,
            headline: t("headline", sprint: sprint.name, percent:),
            because: [t("line", unit: t("units.#{burn.unit}"), remaining: burn.remaining, ideal: burn.ideal_remaining,
                                total: burn.total),
                      t("days", elapsed: burn.elapsed, left: burn.left_days)],
            impact: { deadline: true, people: burn.open.filter_map(&:assigned_to_id).uniq.size, cascade: burn.open.size },
            act_by: sprint.finish_date, effort_days: 1,
            facts: burn.to_h.merge(sprint_id: sprint.id),
            steps_for: ->(_user) { options(sprint, burn) }
          )
        end

        def options(sprint, burn)
          list = []
          cut = to_cut(burn)
          following = Assistant::Facts.next_sprint(sprint)
          if cut.any?
            target = following ? { "sprint_id" => following.id } : { "sprint_id" => nil }
            list << option(t("cut", list: cut.map { "##{it.id}" }.join(t("separator")), to: following&.name || t("backlog")),
                           t("cut_consequence", amount: cut.sum { burn_size(burn, it) }.round(1), unit: t("units.#{burn.unit}")),
                           "cut_scope", cut.map { step(it, target) })
          end
          heaviest = burn.open.select(&:assigned_to_id).max_by { Assistant::Facts.remaining_hours(it) }
          if heaviest
            hours = Assistant::Facts.remaining_hours(heaviest).nonzero? || 8.0
            helper, free = free_member(today, sprint.finish_date, hours, except: [heaviest.assigned_to_id])
            if helper
              list << option(t("reassign", ref: "##{heaviest.id}", name: helper.name),
                             t("reassign_consequence", name: helper.name, free:), "reassign",
                             [step(heaviest, { "assigned_to_id" => helper.id })])
            end
          end
          list
        end

        # Lowest priority first, then the latest due, until the overshoot is covered.
        def to_cut(burn)
          over = burn.remaining - burn.ideal_remaining
          picked = []
          burn.open.sort_by { [it.priority&.position.to_i, -(it.due_date || today).jd] }.each do |wp|
            break if picked.sum { burn_size(burn, it) } >= over

            picked << wp
          end
          picked.first(3)
        end

        def burn_size(burn, wp) = burn.unit == "points" ? wp.story_points.to_f : Assistant::Facts.remaining_hours(wp)
      end
    end
  end
end
