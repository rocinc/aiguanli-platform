# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Assistant
  module Actions
    module Steps
      # A starting outline for a new project (04 E4): phases with their work
      # packages under them and milestones at their ends, created as one step
      # so a child can point at a parent that does not exist yet. Each node:
      #   { "subject", "description", "start_date", "due_date", "milestone", "children" => [...] }
      class CreateWorkBreakdown < Base
        MAX_NODES = 150

        def project = Project.find_by(id: attributes["project_id"])

        def call(user:, cause:)
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless project

          nodes = Array(attributes["nodes"])
          return Outcome.failure(I18n.t("assistant.actions.errors.too_large", count: MAX_NODES)) if count(nodes) > MAX_NODES

          touches = []
          errors = create_all(nodes, nil, user:, cause:, touches:)
          errors.empty? ? Outcome.new(success: true, errors: [], touches:) : Outcome.failure(errors)
        end

        private

        def create_all(nodes, parent, user:, cause:, touches:)
          nodes.each do |node|
            node = node.to_h.stringify_keys
            wp = WorkPackage.new
            wp.journal_cause = cause
            call = ::WorkPackages::CreateService.new(user:).call(**params_for(node, parent).symbolize_keys, work_package: wp)
            return errors_of(call) unless call.success?

            touches.concat(outcome_from(call).touches)
            errors = create_all(Array(node["children"]), call.result, user:, cause:, touches:)
            return errors if errors.any?
          end
          []
        end

        def params_for(node, parent)
          type = node["milestone"] ? milestone_type : task_type
          { "project_id" => project.id, "type_id" => type&.id, "subject" => node["subject"].to_s.truncate(255),
            "description" => node["description"], "parent_id" => parent&.id,
            "start_date" => node["milestone"] ? node["due_date"] : node["start_date"], "due_date" => node["due_date"] }.compact
        end

        def task_type = @task_type ||= project.enabled_types.find { !it.is_milestone? } || project.enabled_types.first

        def milestone_type = @milestone_type ||= project.enabled_types.find(&:is_milestone?) || task_type

        def count(nodes) = nodes.sum { 1 + count(Array(it.to_h.stringify_keys["children"])) }
      end
    end
  end
end
