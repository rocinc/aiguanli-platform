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
  # A promise to go back: the place where someone asked for something, the
  # work package it became, and what they have been told so far ("recorded",
  # "done", "released"), so each is said exactly once.
  class FollowUp < ApplicationRecord
    STATES = %w[waiting done released].freeze

    belongs_to :project
    belongs_to :place, polymorphic: true
    belongs_to :work_package
    belongs_to :asker, class_name: "User", optional: true

    validates :state, inclusion: { in: STATES }

    scope :open, -> { where.not(state: "released") }

    def told?(what) = told.include?(what.to_s)

    def told!(what) = update!(told: (told | [what.to_s]))
  end
end
