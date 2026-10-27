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

module McpTools
  # The assistant's fact and action tools over MCP (04 F3), so an outside
  # agent works with the same computed conclusions and under the same tiers
  # as the panel: it acts as the token's owner, a change is previewed as them,
  # T1 is done and T2/T3 comes back waiting for that person to confirm in
  # the web interface or through decide_assistant_action.
  #
  # One subclass per reasoning tool, built from it, so the two never drift.
  class AssistantTool < Base
    PROJECT_PROPERTY = {
      project_id: { type: "string", description: "Project id or identifier the question is about." }
    }.freeze

    # What an outside agent changes is recorded as coming from it, so the
    # journal says where the change came from.
    class Context < Assistant::Reasoning::Tools::Context
      def basis = [Assistant::Basis.new(kind: "mcp", gid: nil, quote: nil, label: I18n.t("assistant.basis.mcp"))]
    end

    class << self
      attr_reader :reasoning_tool

      def for(reasoning_tool)
        Class.new(self) do
          @reasoning_tool = reasoning_tool
          name "assistant_#{reasoning_tool.tool_name}"
          default_title "Assistant: #{reasoning_tool.tool_name.humanize}"
          default_description reasoning_tool.description
          read_only = reasoning_tool != Assistant::Reasoning::Tools::ProposeTool
          annotations read_only:, idempotent: read_only, destructive: false
          params = reasoning_tool.parameters
          input_schema(type: "object", properties: PROJECT_PROPERTY.merge(params[:properties] || {}),
                       required: ["project_id", *params[:required]])
        end
      end

      def all
        Assistant::Reasoning::Tools.all.map { |tool| AssistantTools.const_get(constant_for(tool)) } + [DecideAssistantAction]
      end

      def constant_for(tool) = tool.tool_name.camelize
    end

    def call(project_id:, **args)
      project = Project.visible(current_user).find_by(id: project_id) ||
                Project.visible(current_user).find_by(identifier: project_id.to_s)
      return Failure("The project was not found.") unless project
      return Failure("The assistant is not available to you in this project.") unless Assistant::Surface.available?(project, current_user)

      context = Context.new(user: current_user, project:)
      result = User.execute_as(current_user) { self.class.reasoning_tool.new(context).call(args.deep_stringify_keys) }
      Success(result.is_a?(Hash) ? result.except("cards") : { result: })
    rescue Assistant::Reasoning::Tools::Refused => e
      Failure(e.message)
    rescue ActiveRecord::RecordNotFound
      Failure("Not found.")
    end
  end
end
