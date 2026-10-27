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
  class BriefMailer < ApplicationMailer
    def daily(user, brief)
      @digest = Assistant::BriefDigest.new(brief)

      message_id user, user

      send_localized_mail(user) do
        I18n.t("assistant.brief_mail.subject", day: brief.day)
      end
    end
  end
end
