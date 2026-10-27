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
    # A person's coming weeks side by side (04 A6): working hours they have,
    # the hours of their open work that fall in each week, and the work that
    # could move — not on the critical path, with slack beyond the move.
    class CalendarDensity
      Week = Data.define(:from, :to, :capacity, :load, :entries) do
        def ratio = capacity.positive? ? load / capacity : (load.positive? ? Float::INFINITY : 0.0)
      end

      def initialize(user, today: Date.current, weeks: 3)
        @user = user
        @today = today
        @weeks = weeks
      end

      def weeks
        @weeks_list ||= Array.new(@weeks) do |i|
          from = [@today.beginning_of_week + (i * 7), @today].max
          to = @today.beginning_of_week + (i * 7) + 4
          load = Load.new(@user, from, to)
          Week.new(from:, to:, capacity: Capacity.new(@user, from, to).hours, load: load.hours, entries: load.entries)
        end
      end

      def crunch(over:)
        weeks.find { it.ratio >= over && it.load - it.capacity >= 4 }
      end

      def room_after(week, under:)
        weeks.find { it.from > week.to && it.ratio <= under }
      end
    end
  end
end
