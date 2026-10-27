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

module OpenProject::Assistant
  # The assistant has no mailbox; mail addressed to it is dropped before it
  # leaves, whichever job or mailer produced it.
  module MailGuard
    SUFFIX = "@assistant.invalid"

    def self.delivering_email(message)
      recipients = %i[to cc bcc].index_with { Array(message.public_send(it)) }
      return if recipients.values.flatten.none? { it.end_with?(SUFFIX) }

      recipients.each { |field, list| message.public_send(:"#{field}=", list.reject { it.end_with?(SUFFIX) }) }
      message.perform_deliveries = false if recipients.keys.all? { message.public_send(it).blank? }
    end
  end
end
