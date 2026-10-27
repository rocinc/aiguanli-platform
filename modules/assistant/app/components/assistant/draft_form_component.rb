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
  # A draft the assistant wrote for someone to put out (04 D3, E1, A4): the
  # words are theirs to change before anything happens. Saving keeps the
  # draft; going ahead saves and publishes. Public and permanent (T3) needs
  # the person to say they read it.
  class DraftFormComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    STATUS_CODES = %w[on_track at_risk off_track not_started finished discontinued].freeze

    def initialize(action:, id:, title_id:, form_inputs:, approve_path:, reject_path:, revise_path:, confirm_label:)
      super()
      @action = action
      @id = id
      @title_id = title_id
      @form_inputs = form_inputs
      @approve_path = approve_path
      @reject_path = reject_path
      @revise_path = revise_path
      @confirm_label = confirm_label
    end

    attr_reader :action, :id, :title_id, :form_inputs, :approve_path, :reject_path, :revise_path, :confirm_label

    def fields
      action.steps.each_with_index.flat_map do |step, index|
        next [] unless Assistant::ActionCardComponent::DRAFT_OPS.include?(step["op"].to_s)

        Assistant::Actions::Revise::FIELDS[step["op"].to_s].map do |attribute|
          { index:, op: step["op"].to_s, attribute:, value: field_value(step, attribute),
            name: "edits[#{index}][#{attribute}]", input_id: "#{id}-edit-#{index}-#{attribute}" }
        end
      end
    end

    def label(field)
      fallback = t("assistant.draft.fields.#{field[:attribute]}", default: field[:attribute].humanize)
      t("assistant.draft.fields.#{field[:op]}.#{field[:attribute]}", default: fallback)
    end

    def words?(field) = Assistant::Drafts::Refinement.words?(field[:attribute])

    def field_value(step, attribute)
      value = step.dig("attributes", attribute).to_s
      Assistant::Drafts::Refinement.words?(attribute) ? Assistant::Mentions.to_text(value) : value
    end

    def refinement
      return @refinement if defined?(@refinement)

      @refinement = if Assistant::Drafts::Refinement.available? && fields.any? { words?(it) }
                      Assistant::Drafts::Refinement.new(action:, url: url_helpers.assistant_writings_path, lead: action.title)
                    end
    end

    def form_data = { turbo_stream: true, test_selector: "assistant-draft-form" }.merge(refinement&.form_data || {})

    def reread = t("assistant.draft_loop.reread")

    def rows(field) = %w[description text].include?(field[:attribute]) ? 14 : 6

    def status_options(selected)
      labels = STATUS_CODES.map { [I18n.t("activerecord.attributes.project.status_codes.#{it}"), it] }
      helpers.options_for_select(labels, selected)
    end

    def public? = action.tier == "t3"

    def lead = t(public? ? "assistant.draft.lead_public" : "assistant.draft.lead")

    def acknowledge_id = "#{id}-acknowledge"

    def revised_by = (User.find_by(id: action.plan["revised_by_id"]) if action.plan["revised_by_id"])
  end
end
