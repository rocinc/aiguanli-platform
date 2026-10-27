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
      class PreviewTool < Base
        STEP_SCHEMA = {
          type: "object",
          properties: {
            op: { type: "string", enum: Assistant::Actions::Steps::OPS - %w[revert] },
            work_package: { type: "string", description: "For update_work_package and comment: \"#69\"" },
            version: { type: "string", description: "For update_version: the version's name, e.g. \"v1.1\"; attributes: effective_date, start_date, status, description" },
            attributes: {
              type: "object",
              description: "update/create_work_package: subject, description, start_date, due_date (YYYY-MM-DD), " \
                           "assignee (name), responsible, version (name), sprint (name), status (name), priority, " \
                           "estimated_hours, remaining_hours, parent. comment: notes (write @Name to mention). " \
                           "create_relation: from_id, to_id, relation_type (follows|precedes|blocks|relates), lag. " \
                           "update_project_status: status_code (on_track|at_risk|off_track|not_started|finished|discontinued), " \
                           "status_explanation. create_time_entry: work_package_id, user, hours, spent_on, comments. " \
                           "create_non_working_time: user, start_date, end_date. create_wiki_page: title, text. " \
                           "create_reminder: work_package, remind_at (YYYY-MM-DD or YYYY-MM-DDTHH:MM), note."
            }
          },
          required: %w[op]
        }.freeze

        define "preview",
               "Dry-run changes as the asking person and see every consequence (rescheduled successors, version " \
               "slips, people affected) without changing anything.",
               { steps: { type: "array", items: STEP_SCHEMA } }, required: %w[steps]

        def call(args)
          steps = StepBuilder.new(context).call(args["steps"])
          result = Assistant::Actions::Preview.new(steps:, user:).call.to_h
          tier = if result["success"]
                   Assistant::Actions::Tiering.call(
                     action: Assistant::Action.new(plan: { "steps" => steps }, on_behalf_of: user), preview: result
                   )
                 end
          result.merge("tier" => tier, "affected_people" => User.where(id: result["affected_user_ids"]).map(&:name))
                .except("affected_user_ids")
        end
      end
    end
  end
end
