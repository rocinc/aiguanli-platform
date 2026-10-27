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
    # How far a project's plans miss, per type of work (04 A2): for work
    # finished in the window, the working days it actually took against the
    # days first planned for it (first start to first due date), and the
    # hours logged against its estimate. A ratio of 1.6 means it took 60%
    # longer than planned.
    class EstimateBias
      WINDOW = 180.days
      MIN_SAMPLES = 4

      Row = Data.define(:type, :samples, :duration_ratio, :hours_ratio, :examples)

      def initialize(project, today: Date.current)
        @project = project
        @today = today
      end

      def rows
        @rows ||= finished.group_by(&:type).filter_map do |type, wps|
          durations = wps.filter_map { duration_ratio(it) }
          hours = wps.filter_map { hours_ratio(it) }
          next if [durations.size, hours.size].max < MIN_SAMPLES

          Row.new(type:, samples: [durations.size, hours.size].max,
                  duration_ratio: durations.size >= MIN_SAMPLES ? median(durations) : nil,
                  hours_ratio: hours.size >= MIN_SAMPLES ? median(hours) : nil,
                  examples: wps.sort_by { -(duration_ratio(it) || 0) }.first(3).map(&:id))
        end
      end

      def to_h
        rows.map do |row|
          { "type" => row.type.name, "samples" => row.samples, "duration_ratio" => row.duration_ratio,
            "hours_ratio" => row.hours_ratio, "examples" => row.examples }
        end
      end

      private

      attr_reader :project, :today

      def finished
        @finished ||= WorkPackage.where(project:, status_id: Facts.closed_status_ids)
                                 .where(updated_at: (today - WINDOW).beginning_of_day..)
                                 .includes(:type, journals: :data).to_a
      end

      def duration_ratio(wp)
        @duration_ratios ||= {}
        return @duration_ratios[wp.id] if @duration_ratios.key?(wp.id)

        @duration_ratios[wp.id] = begin
          start, due = first_plan(wp)
          closed = closed_on(wp)
          planned = start && due && Facts.working_days_between(start, due)
          actual = start && closed && Facts.working_days_between(start, closed)
          planned&.positive? && actual&.positive? ? (actual.to_f / planned).round(2) : nil
        end
      end

      def hours_ratio(wp)
        @logged ||= TimeEntry.where(entity_type: "WorkPackage", entity_id: finished.map(&:id)).group(:entity_id).sum(:hours)
        logged = @logged[wp.id].to_f
        wp.estimated_hours.to_f.positive? && logged.positive? ? (logged / wp.estimated_hours).round(2) : nil
      end

      # The plan as it was first made: the first journal that had both dates.
      def first_plan(wp)
        journal = wp.journals.sort_by(&:version).find { it.data.try(:start_date) && it.data.try(:due_date) }
        journal ? [journal.data.start_date, journal.data.due_date] : nil
      end

      def closed_on(wp)
        closing = wp.journals.sort_by(&:version).each_cons(2).find do |before, after|
          closed = Facts.closed_status_ids
          closed.exclude?(before.data.try(:status_id)) && closed.include?(after.data.try(:status_id))
        end
        closing&.last&.created_at&.to_date
      end

      def median(values)
        sorted = values.sort
        mid = sorted.size / 2
        (sorted.size.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0).round(2)
      end
    end
  end
end
