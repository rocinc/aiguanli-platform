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
  # Mail to someone outside the team (S8 channel 7): a deadline or a gate that
  # must not be missed. The text is what a person read and confirmed; the
  # assistant adds only whom it was written for.
  class ExternalMailer < ApplicationMailer
    def notice(address, subject:, body:, signed_for:, project_id:) # rubocop:disable Lint/UnusedMethodArgument
      @body = body

      send_localized_mail(recipient_for(address)) do
        @signature = I18n.t("assistant.external_mail.signature", name: signed_for)
        subject
      end
    end

    private

    # The host only mails user records; the address is not a member of anything.
    def recipient_for(address) = User.new(mail: address, language: Setting.default_language)
  end
end
