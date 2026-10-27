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
  # A new forum topic: is it asking for something, and what is there already.
  class RequestJob < ApplicationJob
    queue_with_priority :low

    retry_on Assistant::Llm::Error, wait: :polynomially_longer, attempts: 3
    discard_on Assistant::Llm::NotConfigured, Assistant::Llm::OverBudget, ActiveJob::DeserializationError

    def perform(message)
      Assistant::Requests.for(message).call
    end
  end
end
