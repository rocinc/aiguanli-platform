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
    # When a person may be told something (03 §3.4): on their working days,
    # inside working hours in their time zone, never while reminders are
    # paused, and at most `cap` interruptions a day. What cannot interrupt
    # now waits for their next daily reminder time and goes in the brief.
    class Timing
      WORK_START = 9
      WORK_END = 18

      def initialize(user, now: Time.current)
        @user = user
        @now = now.in_time_zone(zone)
        @pref = user.pref
      end

      def zone = ActiveSupport::TimeZone[@user.pref.time_zone] || Time.zone

      def paused?(date = @now.to_date)
        pause = @pref.pause_reminders
        return false unless ActiveRecord::Type::Boolean.new.cast(pause["enabled"])

        first = pause["first_day"].presence && Date.parse(pause["first_day"].to_s)
        last = pause["last_day"].presence && Date.parse(pause["last_day"].to_s)
        (first.nil? || date >= first) && (last.nil? || date <= last)
      end

      def working_day?(date) = @pref.workdays.include?(date.cwday) && Assistant::Facts.working_day?(date) && !absent?(date)

      def working_now?
        working_day?(@now.to_date) && !paused? && @now.hour >= WORK_START && @now.hour < WORK_END
      end

      def interruptions_left(cap)
        cap - Assistant::Signal.interruptions_today(@user).count
      end

      def may_interrupt?(cap) = working_now? && interruptions_left(cap).positive?

      # The next moment the brief is read: their first daily reminder time on
      # their next working, unpaused day.
      def next_brief_at
        date = @now.to_date
        time = brief_time
        date += 1 if @now >= zone.local(date.year, date.month, date.day, time.hour, time.min)
        date += 1 until (working_day?(date) && !paused?(date)) || date > @now.to_date + 60
        zone.local(date.year, date.month, date.day, time.hour, time.min)
      end

      def brief_clock = brief_time.strftime("%H:%M")

      def brief_today
        date = @now.to_date
        zone.local(date.year, date.month, date.day, brief_time.hour, brief_time.min)
      end

      private

      def brief_time
        reminders = @pref.daily_reminders
        raw = Array(reminders["times"]).first.presence || "08:00:00+00:00"
        hour, min = raw.to_s.split(":").map(&:to_i)
        utc = Time.utc(2000, 1, 1, hour.to_i, min.to_i)
        utc.in_time_zone(zone)
      end

      def absent?(date)
        @absences ||= UserNonWorkingTime.where(user: @user).pluck(:start_date, :end_date)
        @absences.any? { |from, to| (from..to).cover?(date) }
      end
    end
  end
end
