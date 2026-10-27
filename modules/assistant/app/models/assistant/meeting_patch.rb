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
  # What the assistant does when a meeting changes: reads its minutes as they
  # are written and when it closes, and tells those who missed it.
  module MeetingPatch
    extend ActiveSupport::Concern

    included do
      after_commit :read_and_tell, on: :update, if: -> { saved_change_to_state? && closed? && !template? }
    end

    module Outcome
      extend ActiveSupport::Concern

      included do
        after_commit :read_outcome, on: %i[create update]
        after_commit :answer_if_called, on: %i[create update]
        after_commit :forget_outcome, on: :destroy
      end

      private

      def read_outcome = Assistant::Understanding::MeetingCapture.outcome_saved(self)

      def forget_outcome = Assistant::Understanding::MeetingCapture.outcome_destroyed(self)

      def answer_if_called = Assistant::Events::Dispatch.outcome_written(self)
    end

    module AgendaItem
      extend ActiveSupport::Concern

      included do
        after_commit :read_while_running, on: %i[create update]
        after_commit :answer_if_called, on: %i[create update]
      end

      private

      def read_while_running = Assistant::Understanding::MeetingCapture.agenda_item_saved(self)

      def answer_if_called = Assistant::Events::Dispatch.agenda_item_written(self)
    end

    def self.install!
      ::MeetingAgendaItem.include(AgendaItem) unless ::MeetingAgendaItem < AgendaItem
      ::MeetingOutcome.include(Outcome) unless ::MeetingOutcome < Outcome
      ::Meeting.include(self) unless ::Meeting < self
    end

    private

    def read_and_tell
      Assistant::Understanding::MeetingCapture.meeting_closed(self)
      return unless project&.module_enabled?(:assistant)

      Assistant::MissedMeetingJob.set(wait: 10.minutes).perform_later(self)
    end
  end
end
