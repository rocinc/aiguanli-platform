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
  # Goes back to the forum topics whose work shipped in a version that has
  # since been closed (06 S3 step 6).
  class FollowUpJob < ApplicationJob
    queue_with_priority :low

    def perform
      Assistant::FollowUp.open.includes(:work_package, :place).find_each do |follow_up|
        version = Assistant::Facts.version_of(follow_up.work_package)
        next unless version&.closed? && follow_up.place

        Assistant::Requests.new(follow_up.place.root).tell(follow_up)
      rescue StandardError => e
        Rails.logger.error("[assistant] follow-up #{follow_up.id}: #{e.class} #{e.message}")
      end
    end
  end
end
