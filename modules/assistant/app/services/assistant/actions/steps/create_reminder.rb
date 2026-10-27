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
      # "下周一提醒我看这个" (04 D6): a platform reminder on a work package, which
      # belongs to the person who asked, so it is set in their name.
      class CreateReminder < Base
        def self.in_deciders_name? = true

        def target = WorkPackage.find_by(id: attributes["work_package_id"])

        def call(user:, cause:) # rubocop:disable Lint/UnusedMethodArgument
          return Outcome.failure(I18n.t("assistant.actions.errors.gone")) unless target

          call = ::Reminders::CreateService.new(user:).call(
            remindable: target, creator: user, remind_at: Time.zone.parse(attributes["remind_at"].to_s),
            note: attributes["note"].to_s.truncate(128).presence
          )
          call.success? ? outcome_from(call) : Outcome.failure(errors_of(call))
        end
      end
    end
  end
end
