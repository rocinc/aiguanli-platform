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
  # Confirms, declines or takes back an action the assistant prepared, as the
  # token's owner. The same rules as the buttons on a card: only the person
  # it waits for may decide it, and undo stops at conflicts.
  class DecideAssistantAction < Base
    default_title "Assistant: decide an action"
    default_description "Approve, reject or undo an action that assistant_propose returned as waiting for confirmation " \
                        "(T2/T3). Only the person the action waits for may decide it."

    name "decide_assistant_action"
    annotations read_only: false, idempotent: false, destructive: false

    input_schema(
      additionalProperties: false,
    required: %w[action_id decision],
      properties: {
        action_id: { type: %w[string number], description: "The action_id returned by assistant_propose." },
        decision: { type: :string, enum: %w[approve reject undo] },
        option: { type: :string, description: "For approve: the key of the chosen way, when the action offered several." }
      }
    )

    def call(action_id:, decision:, option: nil)
      action = Assistant::Action.find_by(id: action_id.to_i)
      return Failure("The action was not found.") unless action&.visible_to?(current_user)

      decisions = Assistant::Decisions.new(action, user: current_user)
      result = case decision
               when "approve" then decisions.approve(option:)
               when "reject" then decisions.reject
               when "undo" then decisions.undo
               else return Failure("Unknown decision.")
               end
      return Failure(result.message || "It could not be done.") unless result.ok || result.conflicts.any?

      Success(Assistant::Reasoning::Tools::ProposeTool.summary(result.action.reload).except("cards")
                .merge("conflicts" => result.conflicts.presence).compact)
    end
  end
end
