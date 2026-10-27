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
      # The due date of a work package moved later for the third time. The
      # cause is rarely the date: it is said to the owner, with the likely
      # causes the data shows (an open blocker, size, load) and a way to act on
      # each.
      class ThirdReschedule < Base
        MIN_RESCHEDULES = 3

        def candidates
          events("work_package.updated").select { it.changed?("due_date") }.filter_map do |event|
            wp = event.subject
            next unless wp.is_a?(WorkPackage) && Assistant::Facts.open?(wp)

            reschedules = Assistant::Facts::History.new(wp).reschedules
            next unless reschedules.size >= MIN_RESCHEDULES

            owner = Routing.owner_of(wp) or next
            build(wp, reschedules, owner)
          end
        end

        private

        def build(wp, reschedules, owner)
          causes = causes(wp, owner)
          candidate(
            fingerprint: "#{wp.id}:#{reschedules.size}", recipient: owner, subject: wp, nature: :own,
            headline: t("headline", ref: "##{wp.id}", count: reschedules.size),
            because: [t("dates", list: reschedules.map { "#{day(it.from)}→#{day(it.to)}" }.join("、")), *causes.map do
              it[:because]
            end],
            impact: { critical_path: graph.slack(wp.id)&.<=(0) || false, cascade: graph.downstream(wp.id).size },
            steps_for: ->(_user) { causes.filter_map { it[:option] } }
          )
        end

        def causes(wp, owner)
          list = []
          blocker = blocker_of(wp)
          if blocker
            list << { because: t("blocked_by", ref: "##{blocker.id}", status: blocker.status.name),
                      option: option(t("ask_blocker", ref: "##{blocker.id}"), t("ask_blocker_consequence"), "ask_blocker",
                                     [comment(blocker, t("ask_blocker_comment", who: blocker.assigned_to ? mention(blocker.assigned_to) : "", ref: "##{wp.id}"))]) }
          end
          remaining = Assistant::Facts.remaining_hours(wp)
          if wp.children.none? && (remaining >= 16 || wp.story_points.to_i >= 8)
            list << { because: t("big", hours: remaining, points: wp.story_points.to_i),
                      option: option(t("split"), t("split_consequence"), "split",
                                     [{ "op" => "create_work_package", "attributes" => { "project_id" => project.id, "parent_id" => wp.id,
                                                                                         "subject" => t("split_child", subject: wp.subject),
                                                                                         "assigned_to_id" => wp.assigned_to_id } }]) }
          end
          load = Assistant::Facts::Load.new(owner, today, Assistant::Facts.add_working_days(today, 9), exclude: [wp.id], today:)
          if load.overloaded?
            list << { because: t("loaded", because: load.because), option: nil }
          end
          list
        end

        def blocker_of(wp)
          ids = Relation.where(to_id: wp.id, relation_type: %w[blocks precedes]).pluck(:from_id) +
                Relation.where(from_id: wp.id, relation_type: "follows").pluck(:to_id)
          WorkPackage.where(id: ids).where.not(status_id: Assistant::Facts.closed_status_ids).first
        end
      end
    end
  end
end
