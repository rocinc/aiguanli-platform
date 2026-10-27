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
  # The first weeks in a project (06 M1): it watches before it speaks. The
  # assistant arrives when its membership is created, which is when the
  # module was enabled.
  module ColdStart
    module_function

    WORKING_DAYS = 10
    FIRST_WEEK = 7.days

    def arrived_at(project)
      return if project.nil?

      Member.where(project:, principal: Assistant.user).minimum(:created_at)
    end

    # From the 11th working day it runs as the dial says.
    def active?(project, today: Date.current)
      arrived = arrived_at(project)
      arrived.present? && Assistant::Facts.working_days_between(arrived.to_date, today) <= WORKING_DAYS
    end

    # Either side being new is enough for the quiet sentence (L6.4).
    def first_week?(project, user, now: Time.current)
      joined = Member.where(project:, principal: user).minimum(:created_at) if project && user
      [arrived_at(project), joined].compact.any? { it > now - FIRST_WEEK }
    end
  end
end
