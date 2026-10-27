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
      # A meeting series (04 E4 会议节奏): a weekly planning, a daily stand-up.
      # The host makes the series and its template the same way the meeting
      # form does; the person it is for becomes its organiser.
      class CreateRecurringMeeting < Base
        FREQUENCIES = %w[daily working_days weekly].freeze

        def project = Project.find_by(id: attributes["project_id"])

        def call(user:, cause:) # rubocop:disable Lint/UnusedMethodArgument
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless project

          frequency = attributes["frequency"].presence_in(FREQUENCIES) || "weekly"
          call = ::RecurringMeetings::CreateService.new(user:).call(
            project:, title: attributes["title"], frequency:, interval: (attributes["interval"].presence || 1).to_i,
            start_date: attributes["start_date"], start_time_hour: attributes["start_time_hour"].presence || "10:00",
            duration: (attributes["duration_minutes"].presence || 30).to_f / 60, end_after: "never",
            time_zone: user.time_zone&.name || Time.zone.name, notify: false
          )
          call.success? ? outcome_from(call) : Outcome.failure(errors_of(call))
        end
      end
    end
  end
end
