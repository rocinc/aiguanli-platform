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

module AssistantSeed
  class TimeLog
    DAILY_LIMIT = 8.0

    def initialize(ctx)
      @ctx = ctx
      @booked = Hash.new(0.0)
    end

    def call
      WORK_PACKAGE_ROWS.each { |row| log(row) }
    end

    private

    def log(row)
      key = REASSIGNED_TODAY[row[:id]] || row[:who]
      hours = hours_for(row)
      return if key.nil? || key == :quinn || hours.nil? || hours <= 0

      days = days_for(row, key)
      return if days.empty?

      shares(hours, days.size).each_with_index do |share, index|
        record(row, key, days[index], share)
      end
    end

    def hours_for(row)
      return nil if %i[epic milestone].include?(row[:ty]) || row[:est].nil?

      case row[:st]
      when :closed then [(row[:est] * 1.1 * 2).round / 2.0, 1].max
      when :doing, :testing then row[:est] - row[:rem].to_f
      when :devdone then row[:est]
      end
    end

    def days_for(row, key)
      from = @ctx.forward(@ctx.d(row[:s]))
      to = row[:st] == :closed ? @ctx.backward(@ctx.d(row[:d])) : @ctx.backward(@ctx.d(-1))
      to = [to, @ctx.d(-10)].min if %i[ben frank mia].include?(key)
      to = [to, @ctx.backward(@ctx.d(-1))].min
      (from..to).select { @ctx.weekday?(it) && !skipped?(key, it) }
    end

    def skipped?(key, day) = key == :bob && day == @ctx.d(-3)

    def shares(total, count)
      each = [(total / count * 2).round / 2.0, 0.5].max
      list = Array.new(count, each)
      list[-1] = [total - (each * (count - 1)), 0.5].max
      list
    end

    def record(row, key, day, hours)
      return if @booked[[key, day]] + hours > DAILY_LIMIT

      @booked[[key, day]] += hours
      user = @ctx.user(key)
      stamp = @ctx.at(day, "18:00")
      entry = TimeEntry.create!(project: @ctx.project, user:, logged_by: user, entity: WorkPackage.find(row[:id]), hours:, spent_on: day,
                                activity_id: activity(key), created_at: stamp, updated_at: stamp)
      @ctx.retime(entry, stamp, 1.minute)
    end

    def activity(key)
      case key
      when :sam then ACTIVITIES[:manage]
      when :ada then ACTIVITIES[:requirements]
      else ACTIVITIES[:development]
      end
    end
  end
end
