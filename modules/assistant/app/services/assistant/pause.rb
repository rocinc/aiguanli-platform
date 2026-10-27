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
  # "Let it be quiet for a while": until the end of the chosen day it does not
  # interrupt anyone, and what it would have said goes to the brief.
  module Pause
    LENGTHS = %w[today tomorrow week].freeze
    DAYS = { "today" => 0, "tomorrow" => 1, "week" => 7 }.freeze

    module_function

    def until_for(length, user, now: Time.current)
      zone = user.time_zone || Time.zone
      last_day = now.in_time_zone(zone).to_date + DAYS.fetch(length)
      zone.local(last_day.year, last_day.month, last_day.day).end_of_day
    end
  end
end
