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
  # "Remind me later" brings a signal back at the time the person picked
  # (this afternoon, tomorrow morning, next Monday, the day before it is due).
  # It is held, not settled, so it stays live and returns in the same place;
  # the count of snoozes is kept for the learning loop, and so is whether it
  # was said at the wrong time.
  module Snooze
    MORNING_HOUR = 9
    AFTERNOON_HOUR = 14
    CHOICES = %w[afternoon tomorrow monday before_due].freeze

    module_function

    def call(signal, user:, choice: nil, reason: nil)
      at = at_for(signal, user, choice) || until_for(user)
      payload = signal.payload.merge("snoozes" => signal.payload.fetch("snoozes", 0).to_i + 1,
                                     "last_snoozed_at" => Time.current.iso8601)
      payload["bad_timing"] = payload.fetch("bad_timing", 0).to_i + 1 if reason == "bad_timing"
      signal.update!(state: "held", snoozed_until: at, deliver_at: at, delivered_at: nil, payload:)
      at
    end

    # The choices open to this person for this signal, soonest first.
    def choices(signal, user, now: Time.current)
      CHOICES.filter_map do |choice|
        at = at_for(signal, user, choice, now:)
        [choice, at] if at && at > now
      end.sort_by(&:last).uniq(&:last)
    end

    def at_for(signal, user, choice, now: Time.current)
      zone = user.time_zone || Time.zone
      local = now.in_time_zone(zone)
      case choice.to_s
      when "afternoon" then zone.local(local.year, local.month, local.day, AFTERNOON_HOUR) if working_day?(local.to_date, user)
      when "tomorrow" then until_for(user, now:)
      when "monday" then morning(zone, next_monday(local.to_date))
      when "before_due" then before_due(signal, user, zone)
      end
    end

    def before_due(signal, user, zone)
      due = signal.payload.dig("facts", "act_by").presence or return
      day = Date.iso8601(due.to_s[0, 10]) - 1
      day -= 1 until working_day?(day, user)
      morning(zone, day)
    rescue Date::Error
      nil
    end

    def next_monday(date) = date + (8 - date.cwday)

    def morning(zone, day) = zone.local(day.year, day.month, day.day, MORNING_HOUR)

    def until_for(user, now: Time.current)
      zone = user.time_zone || Time.zone
      local = now.in_time_zone(zone)
      day = local.to_date + 1
      day += 1 until working_day?(day, user)
      zone.local(day.year, day.month, day.day, MORNING_HOUR)
    end

    def working_day?(date, user)
      workdays = Array(user.try(:pref)&.workdays).map(&:to_i).presence || Setting.working_days.map(&:to_i)
      workdays.include?(date.cwday)
    end

    def snoozed?(signal, now: Time.current) = signal.snoozed_until.present? && signal.snoozed_until > now
  end
end
