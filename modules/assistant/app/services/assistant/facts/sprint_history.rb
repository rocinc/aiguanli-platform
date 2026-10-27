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
  module Facts
    # The last finished sprints of a project side by side (03 §6.4): for each,
    # what was in it and still open when it ended, and when its defects were
    # found — how many in the last two working days. Membership is read from
    # the journals too, so work moved out later still counts where it was.
    class SprintHistory
      LAST = 4
      LATE_WORKING_DAYS = 2
      DEFECT_TYPES = %w[bug defect 缺陷 故障].freeze

      Row = Data.define(:sprint, :planned, :unfinished, :done_points, :defects, :late_defects) do
        def carryover_share = planned.zero? ? 0.0 : unfinished.size.fdiv(planned)

        def late_share = defects.empty? ? nil : late_defects.size.fdiv(defects.size)
      end

      def initialize(project, today: Date.current)
        @project = project
        @today = today
      end

      def rows
        @rows ||= sprints.map do |sprint|
          ids = ids_in(sprint)
          defects = defects_in(sprint)
          late_from = Facts.add_working_days(sprint.finish_date, -LATE_WORKING_DAYS)
          unfinished = ids.reject { closed_by?(it, sprint.finish_date) }
          Row.new(sprint:, planned: ids.size, unfinished:,
                  done_points: WorkPackage.where(id: ids - unfinished).sum(:story_points).to_i,
                  defects:, late_defects: defects.select { it.created_at.to_date > late_from })
        end
      end

      # Story points finished per sprint, the middle of the last three.
      def velocity
        points = rows.last(3).map(&:done_points).select(&:positive?).sort
        points.empty? ? nil : points[points.size / 2]
      end

      def defect_type_ids
        @defect_type_ids ||= Type.all.select { |type| DEFECT_TYPES.any? { type.name.downcase.include?(it) } }.map(&:id)
      end

      private

      def sprints
        return [] unless defined?(::Sprint)

        ::Sprint.where(project: @project).where.not(start_date: nil).where(finish_date: ...@today)
                .order(finish_date: :desc).limit(LAST).to_a.reverse
      end

      def ids_in(sprint)
        Journal::WorkPackageJournal.where(sprint_id: sprint.id).joins(:journal)
                                   .where(journals: { journable_type: "WorkPackage" })
                                   .where(journals: { created_at: ..sprint.finish_date.end_of_day })
                                   .distinct.pluck("journals.journable_id") | sprint.work_packages.pluck(:id)
      end

      def defects_in(sprint)
        return [] if defect_type_ids.empty?

        WorkPackage.where(project: @project, type_id: defect_type_ids)
                   .where(created_at: sprint.start_date.beginning_of_day..sprint.finish_date.end_of_day).to_a
      end

      # Closed on or before the date, as the journals say; a work package
      # closed and then reopened later still counts as finished then.
      def closed_by?(id, date)
        Journal::WorkPackageJournal.joins(:journal)
                                   .where(journals: { journable_type: "WorkPackage", journable_id: id })
                                   .where(journals: { created_at: ..date.end_of_day })
                                   .order("journals.version DESC").pick(:status_id)
                                   .then { Facts.closed_status_ids.include?(it) }
      end
    end
  end
end
