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
  module Reasoning
    module Tools
      class CapacityTool < Base
        include DateRange

        define "capacity",
               "Hours a person can work in a date range, after their working hours, holidays and days off.",
               { person: { type: "string", description: "Name, login or id; empty = the asking person" },
                 from: { type: "string", description: "YYYY-MM-DD, default today" },
                 to: { type: "string", description: "YYYY-MM-DD, default two weeks on" } }

        def call(args)
          person = context.person(args["person"])
          from, to = range(args)
          capacity = Assistant::Facts::Capacity.new(person, from, to)
          { "person" => person.name, "from" => iso(from), "to" => iso(to), "hours" => capacity.hours,
            "days_off" => capacity.absences.map(&:iso8601), "because" => capacity.because }
        end
      end
    end
  end
end
