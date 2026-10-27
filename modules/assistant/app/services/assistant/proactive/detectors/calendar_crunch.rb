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
    module Detectors
      # Someone's coming week holds far more work than their hours, while a
      # later one has room (04 A6 日程密度、错峰). Told privately, with the
      # piece that can move — off the critical path, with slack to spare —
      # moved into the lighter week.
      class CalendarCrunch < Base
        OVER_PERCENT = 130
        ROOM_PERCENT = 70

        def candidates
          Routing.people(project).filter_map do |person|
            density = Assistant::Facts::CalendarDensity.new(person, today:)
            week = density.crunch(over: OVER_PERCENT.fdiv(100)) or next
            room = density.room_after(week, under: ROOM_PERCENT.fdiv(100))
            build(person, week, room)
          end
        end

        private

        def build(person, week, room)
          movable = room && movable(week, room)
          candidate(
            fingerprint: "#{person.id}:#{week.from.cweek}", recipient: person, subject: project, nature: :own, channel: "brief",
            headline: t("headline", from: day(week.from), load: week.load, capacity: week.capacity),
            because: [t("week", load: week.load, capacity: week.capacity, count: week.entries.size),
                      (t("room", from: day(room.from), load: room.load, capacity: room.capacity) if room),
                      (t("movable", ref: "##{movable.id}", subject: movable.subject.truncate(40)) if movable)].compact,
            impact: { deadline: true, cascade: week.entries.size }, act_by: week.from, facts: { ratio: week.ratio.round(2) },
            steps_for: ->(_user) { movable ? [move_option(movable, room)] : [look_option(person, week)] }
          )
        end

        # Work of this project in the heavy week, latest-starting first, that
        # can slide into the light week without touching anything after it.
        def movable(week, room)
          days = Assistant::Facts.working_days_between(week.from, room.from)
          week.entries.map(&:work_package).select { it.project_id == project.id && it.due_date }
              .select { (graph.slack(it.id) || 0) > days && graph.downstream(it.id).empty? }
              .max_by { [it.start_date || it.due_date, it.id] }
        end

        def move_option(wp, room)
          days = Assistant::Facts.working_days_between(wp.start_date || wp.due_date, room.from)
          option(t("move", ref: "##{wp.id}", from: day(room.from)), t("move_consequence"), "spread_load", [step(wp, shift(wp, days))])
        end

        def look_option(person, week)
          props = { f: [{ n: "assignee", o: "=", v: [person.id.to_s] },
                        { n: "dueDate", o: "<>d", v: [week.from.iso8601, (week.from + 6).iso8601] }],
                    t: "dueDate:asc" }
          helpers = OpenProject::StaticRouting::StaticUrlHelpers.new
          url = helpers.project_work_packages_path(project, query_props: props.to_json)
          option(t("look"), t("look_consequence"), "look", []).merge(url:)
        end
      end
    end
  end
end
