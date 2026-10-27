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
  module Facts
    # Where a running sprint stands against its ideal line: what was in it at
    # the start, what is left today, and what a straight line from start to
    # finish says should be left by now. Story points when the sprint has
    # them, remaining hours otherwise.
    class SprintBurn
      def initialize(sprint, today: Date.current)
        @sprint = sprint
        @today = today
      end

      attr_reader :sprint, :today

      def running?
        sprint.start_date.present? && sprint.finish_date.present? && (sprint.start_date...sprint.finish_date).cover?(today)
      end

      def unit = points? ? "points" : "hours"

      def days = @days ||= working_days(sprint.start_date, sprint.finish_date)

      def elapsed = working_days(sprint.start_date, today - 1)

      def left_days = working_days(today, sprint.finish_date)

      def total = @total ||= work_packages.sum { size(it) }.round(1)

      def remaining = @remaining ||= open.sum { remaining_of(it) }.round(1)

      def ideal_remaining
        return total if days.zero?

        (total * (1 - (elapsed.to_f / days))).round(1)
      end

      # How far above the ideal line the actual one is, as a share of the
      # ideal remaining; nil when the ideal says nothing should be left.
      def drift
        ideal = ideal_remaining
        return nil unless ideal.positive?

        ((remaining - ideal) / ideal).round(2)
      end

      def open = work_packages.select { Facts.open?(it) }

      def work_packages = @work_packages ||= sprint.work_packages.includes(:status, :assigned_to).to_a

      def to_h
        { "sprint" => sprint.name, "unit" => unit, "total" => total, "remaining" => remaining,
          "ideal_remaining" => ideal_remaining, "drift" => drift, "working_days" => days, "elapsed" => elapsed,
          "left" => left_days }
      end

      private

      def points? = @points ||= work_packages.any? { it.story_points.to_i.positive? }

      def size(wp) = points? ? wp.story_points.to_f : wp.estimated_hours.to_f

      def remaining_of(wp) = points? ? wp.story_points.to_f : Facts.remaining_hours(wp)

      def working_days(from, to) = Facts.working_days_between(from, to)
    end
  end
end
