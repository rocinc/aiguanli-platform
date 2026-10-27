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
  # What an empty place says: its own sentence, or in the first week the one
  # sentence that is true everywhere (L6.4). Where a page has several empty
  # places, only the first of them says it.
  module QuietWords
    def quiet(key, first_week: first_week?)
      first_week ? t("assistant.quiet.first_week") : t(key)
    end

    def first_week?
      return @first_week if defined?(@first_week)

      @first_week = Assistant::ColdStart.first_week?(project, user)
    end
  end
end
