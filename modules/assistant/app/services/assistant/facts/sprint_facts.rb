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
    # Planned versus available hours, done versus remaining, and carry-over for
    # a sprint, per person and in total.
    class SprintFacts
      def initialize(sprint, today: Date.current)
        @sprint = sprint
        @today = today
      end

      attr_reader :sprint

      def work_packages = @work_packages ||= sprint.work_packages.includes(:status, :assigned_to).to_a

      def open = work_packages.reject { Facts.closed_status_ids.include?(it.status_id) }

      def people = work_packages.filter_map(&:assigned_to).select { it.is_a?(User) }.uniq

      # From today while it runs; a finished or future sprint is counted whole.
      def from
        start = sprint.start_date || @today
        running = sprint.finish_date.nil? || (start..sprint.finish_date).cover?(@today)
        running ? [start, @today].max : start
      end

      def to = sprint.finish_date || (from + 14)

      def remaining_hours = open.sum { (it.remaining_hours || it.estimated_hours).to_f }.round(1)

      def capacity_hours = people.sum { Capacity.new(it, from, to).hours }.round(1)

      def per_person
        people.map do |user|
          mine = open.select { it.assigned_to_id == user.id }
          remaining = mine.sum { (it.remaining_hours || it.estimated_hours).to_f }.round(1)
          capacity = Capacity.new(user, from, to)
          { "user_id" => user.id, "name" => user.name, "remaining" => remaining, "capacity" => capacity.hours,
            "free" => (capacity.hours - remaining).round(1), "absent_days" => capacity.absences.size }
        end
      end

      def to_h
        { "sprint" => sprint.name, "from" => from.iso8601, "to" => to.iso8601,
          "items" => work_packages.size, "open" => open.size,
          "remaining_hours" => remaining_hours, "capacity_hours" => capacity_hours,
          "points_total" => work_packages.sum { it.story_points.to_i },
          "points_done" => (work_packages - open).sum { it.story_points.to_i },
          "people" => per_person }
      end
    end
  end
end
