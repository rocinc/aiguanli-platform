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
    # Work already on a person's plate in a date range: remaining hours of the
    # open work packages assigned to them, spread over the working days each
    # one spans, plus confirmed resource allocations. Overdue open work counts
    # as due today.
    class Load
      Entry = Data.define(:work_package, :hours_in_range, :remaining, :due_date)

      def initialize(user, from, to, exclude: [], today: Date.current)
        @user = user
        @from = from.to_date
        @to = to.to_date
        @exclude = Array(exclude).map(&:to_i)
        @today = today
      end

      def entries
        @entries ||= open_work_packages.filter_map do |wp|
          remaining = Facts.remaining_hours(wp)
          next if remaining.zero?

          start = [wp.start_date || wp.due_date || wp.sprint&.start_date || @from, @today].max
          finish = wp.due_date || wp.sprint&.finish_date || start
          finish = deadline_today if finish < @today
          share = overlap_share(start, finish)
          next if share.zero?

          Entry.new(work_package: wp, hours_in_range: (remaining * share).round(1), remaining:, due_date: wp.due_date)
        end
      end

      def hours = entries.sum(&:hours_in_range).round(1)

      def free_hours = (Capacity.new(@user, @from, @to).hours - hours).round(1)

      def overloaded? = free_hours.negative?

      def because
        I18n.t("assistant.facts.load.because", count: entries.size, hours:,
                                               capacity: Capacity.new(@user, @from, @to).hours)
      end

      def fact = Fact.new(value: { "load" => hours, "free" => free_hours }, because:)

      private

      def open_work_packages
        WorkPackage.where(assigned_to_id: @user.id).where.not(status_id: Facts.closed_status_ids)
                   .where.not(id: @exclude)
                   .where("COALESCE(work_packages.due_date, work_packages.start_date) >= :from " \
                          "OR work_packages.due_date IS NULL OR work_packages.due_date < :today", from: @from, today: @today)
                   .includes(:project, :status, :sprint).to_a
      end

      # Overdue work is still on the plate: it has to be done from today on.
      def deadline_today = Facts.working_day?(@today) ? @today : Facts.next_working_day(@today)

      def overlap_share(start, finish)
        span = Facts.working_days_between(start, finish)
        return 1.0 if span.zero? && (@from..@to).cover?(finish)
        return 0.0 if span.zero?

        overlap = Facts.working_days_between([start, @from].max, [finish, @to].min)
        overlap.to_f / span
      end
    end
  end
end
