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
      # One person with three or more due dates on the same day, a week ahead
      # (04 A6): told privately, with the one that matters least moved to
      # their next free working day — across every project they are in,
      # since that is what their day actually holds.
      class DeadlineCluster < Base
        HORIZON = 7
        MIN_DUE = 3

        def candidates
          Routing.people(project).flat_map do |person|
            clusters(person).map { |date, wps| build(person, date, wps) }
          end
        end

        private

        # Said by the project the lowest of them belongs to, so it is said once.
        # A parent's dates only sum up its children, so only leaves count.
        def clusters(person)
          leaves(WorkPackage.where(assigned_to_id: person.id, due_date: (today + 1)..(today + HORIZON)))
            .where.not(status_id: Assistant::Facts.closed_status_ids).includes(:project, :priority).to_a
            .group_by(&:due_date)
            .select { |_, wps| wps.size >= MIN_DUE && wps.min_by(&:id).project_id == project.id }
        end

        def build(person, date, wps)
          movable = wps.select { it.project_id == project.id }.min_by { [it.priority&.position.to_i, -it.id] }
          candidate(
            fingerprint: "#{person.id}:#{date}", recipient: person, subject: project, nature: :own, channel: "brief",
            headline: t("headline", count: wps.size, date: day(date)),
            because: wps.sort_by { -it.priority&.position.to_i }.map do
              t("line", ref: "##{it.id}", subject: it.subject.truncate(40), project: it.project.name)
            end,
            impact: { deadline: true, cascade: wps.size }, act_by: date, effort_days: 1,
            facts: { date:, ids: wps.map(&:id) },
            steps_for: ->(_user) { movable ? [move_option(person, movable, date)] : [] }
          )
        end

        def move_option(person, wp, date)
          target = Assistant::Facts.next_working_day(date)
          target = Assistant::Facts.next_working_day(target) while busy?(person, target)
          days = Assistant::Facts.working_days_between(date + 1, target)
          option(t("move", ref: "##{wp.id}", date: day(target)), t("move_consequence"), "spread_deadlines", [step(wp, shift(wp, days))])
        end

        def busy?(person, date)
          date < today + 30 &&
            leaves(WorkPackage.where(assigned_to_id: person.id, due_date: date))
              .where.not(status_id: Assistant::Facts.closed_status_ids).exists?
        end

        def leaves(scope) = scope.where.not(id: WorkPackage.where.not(parent_id: nil).select(:parent_id))
      end
    end
  end
end
