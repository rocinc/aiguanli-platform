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
    # Hours a person can work in a date range: their working hours per weekday
    # and availability, minus personal and instance-wide non-working days.
    class Capacity
      DEFAULT_MINUTES = 8 * 60

      def initialize(user, from, to)
        @user = user
        @from = from.to_date
        @to = to.to_date
      end

      def hours = (minutes / 60.0).round(1)

      def minutes = days.sum { it[:minutes] }

      def days
        @days ||= (@from..@to).map do |date|
          reason = absence_reason(date)
          { date:, minutes: reason ? 0 : minutes_on(date), reason: }
        end
      end

      def absences = days.select { it[:reason] == :absence }.map { it[:date] }

      def absence_ranges
        personal_absences.filter_map do |range|
          from = [range.begin, @from].max
          to = [range.end, @to].min
          [from, to] if days.any? { it[:reason] == :absence && it[:date].between?(from, to) }
        end
      end

      def because
        absent = absences
        parts = [I18n.t("assistant.facts.capacity.base", from: Assistant::Text.day(@from),
                                                         to: Assistant::Text.day(@to), hours: hours)]
        parts << I18n.t("assistant.facts.capacity.absent", days: absent.size) if absent.any?
        parts << I18n.t("assistant.facts.capacity.partial", percent: schedule&.availability_factor) if partial?
        parts.join(" ")
      end

      def fact = Fact.new(value: hours, because:)

      private

      def schedule = @schedule ||= UserWorkingHours.for_user(@user).valid_for_date(@to)

      def partial? = schedule && schedule.availability_factor.to_i < 100

      def minutes_on(date)
        return 0 unless Facts.working_day?(date)

        hours = UserWorkingHours.for_user(@user).valid_for_date(date)
        hours ? hours.effective_minutes_on(date) : DEFAULT_MINUTES
      end

      def absence_reason(date)
        return :holiday unless Facts.working_day?(date)

        :absence if personal_absences.any? { |range| range.cover?(date) }
      end

      def personal_absences
        @personal_absences ||= UserNonWorkingTime.where(user: @user).where("start_date <= ? AND end_date >= ?", @to, @from)
                                                 .map { it.start_date..it.end_date }
      end
    end
  end
end
