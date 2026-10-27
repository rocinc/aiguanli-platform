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
    # When the job that runs duties will next pick this one up: the first
    # quarter hour at which `due?` holds, found by trying the hour each kind
    # looks at on the coming days.
    class NextRun
      TICK = 15.minutes
      LOOKAHEAD_DAYS = 60
      INTERVALS = { "decision_log" => 1.hour, "meeting_followup" => 30.minutes, "advance_merged_pr" => 10.minutes,
                    "onboarding" => 15.minutes }.freeze
      HOURS = { "sprint_carryover" => 10, "release_watch" => 9, "timesheet_draft" => 15, "devils_advocate" => 9 }.freeze

      def self.call(duty, now = Time.current) = new(duty, now).call

      def initialize(duty, now)
        @duty = duty
        @now = now
      end

      def call
        return tick_after(@now) if @duty.due?(@now)
        return tick_after([@now, @duty.last_run_at + INTERVALS.fetch(@duty.kind)].max) if INTERVALS.key?(@duty.kind)

        slots.find { @duty.due?(it) }
      end

      private

      def hour = HOURS.fetch(@duty.kind) { (@duty.scope.to_h["hour"] || 16).to_i }

      def zone = @duty.delegator.time_zone || Time.zone.name

      def slots
        today = @now.in_time_zone(zone).beginning_of_day
        (0..LOOKAHEAD_DAYS).lazy.map { today + it.days + hour.hours }.select { it > @now }
      end

      def tick_after(time) = Time.zone.at((time.to_i + 1).fdiv(TICK.to_i).ceil * TICK.to_i)
    end
  end
end
