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
  module Understanding
    # Turns the model's reading of a time expression into a date. The model only
    # classifies ("two working days", "end of this sprint"); every date is
    # computed here, against the instance's working-day calendar and the
    # project's own sprints and versions.
    class DueResolver
      Result = Data.define(:due_on, :anchor) do
        def self.none = new(due_on: nil, anchor: nil)
      end

      KINDS = %w[
        none today tomorrow working_days calendar_days weekday end_of_week
        absolute_date end_of_sprint next_sprint next_version next_week_start next_week_end
      ].freeze

      def initialize(project:, stated_on:, work_package: nil)
        @project = project
        @stated_on = stated_on.to_date
        @work_package = work_package
      end

      def call(due)
        due = Hash(due).stringify_keys
        case due["kind"].to_s
        when "today" then dated(stated_on)
        when "tomorrow" then dated(add_working_days(1))
        when "working_days" then dated(add_working_days(positive(due["value"])))
        when "calendar_days" then dated(stated_on + positive(due["value"]))
        when "weekday" then dated(due["next_week"] ? weekday_next_week(due["value"]) : next_weekday(due["value"]))
        when "next_week_start" then dated(first_working_day(next_monday))
        when "next_week_end" then dated(last_working_day(next_monday + 6))
        when "end_of_week" then dated(last_working_day_of_week)
        when "absolute_date" then dated(absolute(due["value"]))
        when "end_of_sprint" then sprint_end(current_sprint)
        when "next_sprint" then sprint_end(next_sprint)
        when "next_version" then version_due(next_version)
        else Result.none
        end
      end

      private

      attr_reader :project, :stated_on, :work_package

      def dated(date) = date ? Result.new(due_on: date, anchor: nil) : Result.none

      def positive(value)
        Integer(value.to_s).clamp(1, 365)
      rescue ArgumentError, TypeError
        1
      end

      def working?(date)
        Setting.working_days.include?(date.cwday) && non_working_dates.exclude?(date)
      end

      def non_working_dates
        @non_working_dates ||= NonWorkingDay.where(date: stated_on..(stated_on + 400)).pluck(:date).to_set
      end

      def add_working_days(count)
        date = stated_on
        remaining = count
        guard = 0
        while remaining.positive? && guard < 800
          date += 1
          guard += 1
          remaining -= 1 if working?(date)
        end
        date
      end

      # "下周三": that weekday in the calendar week after this one, whatever
      # day today is.
      def weekday_next_week(value)
        cwday = Integer(value.to_s)
        cwday.between?(1, 7) ? next_monday + (cwday - 1) : nil
      rescue ArgumentError, TypeError
        nil
      end

      def next_monday = stated_on.beginning_of_week(:monday) + 7

      def first_working_day(from)
        date = from
        date += 1 until working?(date) || date > from + 6
        date
      end

      def last_working_day(to)
        date = to
        date -= 1 until working?(date) || date < to - 6
        date
      end

      def next_weekday(value)
        cwday = Integer(value.to_s)
        return nil unless cwday.between?(1, 7)

        offset = (cwday - stated_on.cwday) % 7
        stated_on + (offset.zero? ? 7 : offset)
      rescue ArgumentError, TypeError
        nil
      end

      def last_working_day_of_week
        date = stated_on.end_of_week
        date -= 1 while date > stated_on && !working?(date)
        date
      end

      def absolute(value)
        date = Date.iso8601(value.to_s)
        date < stated_on - 1 ? nil : date
      rescue Date::Error
        nil
      end

      def sprints
        return Sprint.none unless defined?(::Sprint)

        Sprint.where(project:)
      end

      def current_sprint
        own = work_package.respond_to?(:sprint) ? work_package.sprint : nil
        return own if own&.finish_date && own.finish_date >= stated_on

        sprints.where(start_date: ..stated_on, finish_date: stated_on..).order(:start_date).first ||
          sprints.where(status: "active").where.not(finish_date: nil).order(:finish_date).first
      end

      def next_sprint
        reference = current_sprint&.finish_date || stated_on
        sprints.where("start_date > ?", reference).order(:start_date).first
      end

      def sprint_end(sprint)
        return Result.none unless sprint&.finish_date

        Result.new(due_on: sprint.finish_date, anchor: sprint)
      end

      def next_version
        own = work_package&.target_versions&.first
        return own if own&.effective_date && own.effective_date >= stated_on

        project.shared_versions.where(status: "open")
               .where(effective_date: stated_on..).order(:effective_date).first
      end

      def version_due(version)
        return Result.new(due_on: nil, anchor: version) if version && version.effective_date.nil?
        return Result.none unless version

        Result.new(due_on: version.effective_date, anchor: version)
      end
    end
  end
end
