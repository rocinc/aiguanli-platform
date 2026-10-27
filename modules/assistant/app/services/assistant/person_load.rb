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
  # How much of a person's week is left, or that they are away: the one
  # reading every place that suggests a person for something shares.
  class PersonLoad
    Reading = Data.define(:free_hours, :away_until)

    def self.of(person, today: Date.current) = new(person, today).reading

    def initialize(person, today)
      @person = person
      @today = today
    end

    def reading = Reading.new(free_hours:, away_until:)

    private

    def free_hours
      free = Assistant::Facts::Load.new(@person, @today, @today.end_of_week, today: @today).free_hours
      [free, 0].max
    end

    def away_until
      UserNonWorkingTime.where(user: @person).where("start_date <= :day AND end_date >= :day", day: @today).maximum(:end_date)
    end
  end
end
