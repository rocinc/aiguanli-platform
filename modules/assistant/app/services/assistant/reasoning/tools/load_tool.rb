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
      class LoadTool < Base
        include DateRange

        define "load",
               "What is already on a person's plate in a date range (open work packages spread over their dates), " \
               "against their capacity: committed hours, free hours, overloaded or not.",
               { person: { type: "string" }, from: { type: "string" }, to: { type: "string" },
                 sprint: { type: "string", description: "Use this sprint's dates instead of from/to" } }

        def call(args)
          person = context.person(args["person"])
          from, to = if args["sprint"].present?
                       sprint = context.sprint(args["sprint"])
                       [[sprint.start_date, Date.current].max, sprint.finish_date]
                     else
                       range(args)
                     end
          load = Assistant::Facts::Load.new(person, from, to)
          capacity = Assistant::Facts::Capacity.new(person, from, to)
          unestimated = WorkPackage.where(assigned_to_id: person.id).where.not(status_id: Assistant::Facts.closed_status_ids)
                                   .where(estimated_hours: nil, remaining_hours: nil)
                                   .where("due_date IS NULL OR due_date >= ?", from).where("start_date IS NULL OR start_date <= ?", to)
          {
            "person" => person.name, "from" => iso(from), "to" => iso(to),
            "capacity_hours" => capacity.hours, "capacity_because" => capacity.because,
            "committed_hours" => load.hours, "free_hours" => load.free_hours, "overloaded" => load.overloaded?,
            "because" => load.because,
            "entries" => load.entries.map do |e|
              wp_ref(e.work_package).merge("hours_in_range" => e.hours_in_range, "remaining" => e.remaining, "due" => iso(e.due_date))
            end,
            "open_without_estimate" => unestimated.limit(10).map { wp_ref(it).merge("due" => iso(it.due_date)) }
          }
        end
      end
    end
  end
end
