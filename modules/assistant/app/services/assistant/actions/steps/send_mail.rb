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
      # Mail to addresses outside the team (07 E4 release_watch, 04 S8 channel 7),
      # sent through the platform's mail delivery. Only the system proposes it, never
      # the model (see SYSTEM_OPS); it goes out signed "AI assistant (for X)" and
      # cannot be taken back, so it is always T3.
      class SendMail < Base
        ADDRESS = URI::MailTo::EMAIL_REGEXP

        def project = Project.find_by(id: attributes["project_id"])

        def recipients = Array(attributes["to"]).map { it.to_s.strip }.compact_blank.uniq

        def call(user:, cause:) # rubocop:disable Lint/UnusedMethodArgument
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless project
          return Outcome.failure(I18n.t("assistant.actions.errors.no_recipient")) if recipients.empty?
          return Outcome.failure(I18n.t("assistant.actions.errors.bad_address")) unless recipients.all? { ADDRESS.match?(it) }
          return Outcome.new(success: true, errors: [], touches: []) if cause.nil?

          recipients.each do |address|
            Assistant::ExternalMailer.notice(address, subject: attributes["subject"].to_s, body: attributes["body"].to_s,
                                                      signed_for: attributes["signed_for"].to_s,
                                                      project_id: project.id).deliver_later
          end
          Outcome.new(success: true, errors: [], touches: [])
        end
      end
    end
  end
end
