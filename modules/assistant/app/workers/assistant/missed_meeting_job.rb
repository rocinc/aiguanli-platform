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
  # Run a while after a meeting closes, once its agenda has been read.
  class MissedMeetingJob < ApplicationJob
    queue_with_priority :low

    def perform(meeting)
      Assistant::MissedMeeting.new(meeting).call
    end
  end
end
