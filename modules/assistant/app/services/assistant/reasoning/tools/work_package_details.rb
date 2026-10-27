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
      class WorkPackageDetails < Base
        define "work_package",
               "Everything about one work package: fields, dates, people, relations, what was said and decided " \
               "on it, how often it was rescheduled, slack before it pushes something else, and what it lacks " \
               "(acceptance criteria, estimate, owner) or where its hours run over.",
               { ref: { type: "string", description: "Work package id, e.g. \"#69\" or \"69\"" } },
               required: %w[ref]

        def call(args)
          wp = context.work_package(args["ref"])
          graph = Assistant::Facts::ScheduleGraph.new(wp.project)
          history = Assistant::Facts::History.new(wp)
          version = Assistant::Facts.version_of(wp)

          {
            "id" => wp.id, "subject" => wp.subject, "type" => wp.type&.name, "status" => wp.status&.name,
            "project" => wp.project.name, "assignee" => person_ref(wp.assigned_to), "accountable" => person_ref(wp.responsible),
            "start_date" => iso(wp.start_date), "due_date" => iso(wp.due_date), "estimated_hours" => wp.estimated_hours,
            "remaining_hours" => wp.remaining_hours, "story_points" => wp.story_points, "priority" => wp.priority&.name,
            "version" => version && { "name" => version.name, "date" => iso(version.effective_date) },
            "sprint" => wp.sprint && { "name" => wp.sprint.name, "finish" => iso(wp.sprint.finish_date) },
            "parent" => wp.parent && wp_ref(wp.parent),
            "description" => Assistant::Text.plain(wp.description).truncate(1500),
            "relations" => relations(wp),
            "slack_working_days" => graph.slack(wp.id),
            "downstream" => graph.downstream(wp.id).first(10).filter_map do
              graph.nodes[it]&.then do |n|
                "##{n.id} #{n.subject}"
              end
            end,
            "history" => history.to_h,
            "quality" => Assistant::Facts::WorkPackageQuality.new(wp).to_h,
            "said" => said(wp)
          }
        end

        private

        def relations(wp)
          Relation.where(from_id: wp.id).or(Relation.where(to_id: wp.id)).includes(:from, :to).map do |r|
            other = r.from_id == wp.id ? r.to : r.from
            next unless other&.visible?(user)

            direction = r.from_id == wp.id ? r.relation_type : "#{r.relation_type} (from the other side)"
            { "type" => direction, "lag" => r.lag, "other" => wp_ref(other) }
          end.compact
        end

        def said(wp)
          Assistant::Said.new(user).on_subject(wp).limit(20).map do |item|
            { "kind" => item.kind, "status" => item.status, "title" => item.title, "quote" => item.quote,
              "owner" => item.owner&.name, "waiting" => item.counterparty&.name, "due" => iso(item.said_due_on),
              "strength" => item.strength }
          end
        end
      end
    end
  end
end
