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
  class BriefMailJob < ApplicationJob
    queue_with_priority :notification

    include GoodJob::ActiveJobExtensions::Concurrency

    good_job_control_concurrency_with(total_limit: 1, key: -> { self.class.name })

    def perform
      Assistant::BriefMail.new.call
    end
  end
end
