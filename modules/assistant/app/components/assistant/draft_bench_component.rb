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
  # The words of a draft as something to keep working on: a text box to edit in,
  # a line to say what else should change, versions to go back to, and a bar
  # for a selected passage. Without a language model it is just the text box.
  # The `assistant--draft-refine` controller on the form brings it to life.
  class DraftBenchComponent < ApplicationComponent
    CHIPS = %w[shorter specific rephrase formal].freeze

    def initialize(field:, label:, refinement: nil, rows: 6)
      super()
      @field = field
      @label = label
      @refinement = refinement
      @rows = rows
    end

    attr_reader :field, :label, :rows

    def refinable? = @refinement.present?

    def data
      return {} unless refinable?

      { "assistant--draft-refine-target": "field", task: @refinement.task(label), material: @refinement.material(field[:value]) }
    end

    def chips = CHIPS.map { t("assistant.draft_loop.chip_#{it}") }

    def revise_id = "#{field[:input_id]}-revise"
  end
end
