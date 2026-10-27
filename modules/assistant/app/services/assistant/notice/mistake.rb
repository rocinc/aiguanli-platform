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
  module Notice
    # Where a notice that was called wrong went wrong, when that can be read
    # off the facts it was written from and the object as it is now. Nothing
    # is guessed: no difference found, nothing said.
    class Mistake
      DATES = %w[start_date due_date].freeze

      def initialize(signal)
        @signal = signal
      end

      def sentence
        gone || closed || moved
      end

      private

      attr_reader :signal

      def subject = signal.subject

      def facts = signal.payload["facts"].to_h

      def ref = subject.is_a?(WorkPackage) ? "##{subject.id}" : subject.try(:name) || subject.try(:title)

      def gone
        return unless signal.subject_type.present? && subject.nil?

        I18n.t("assistant.notice.mistakes.gone")
      end

      def closed
        return unless subject.is_a?(WorkPackage) && subject.closed?

        I18n.t("assistant.notice.mistakes.closed", ref:)
      end

      def moved
        return unless subject.is_a?(WorkPackage)

        key = DATES.find do
          facts[it].present? && subject.public_send(it).present? && facts[it].to_s[0, 10] != subject.public_send(it).iso8601
        end
        return unless key

        I18n.t("assistant.notice.mistakes.moved", ref:, field: WorkPackage.human_attribute_name(key),
                                                  was: Assistant::Text.day(Date.iso8601(facts[key].to_s[0, 10])),
                                                  now: Assistant::Text.day(subject.public_send(key)))
      rescue Date::Error
        nil
      end
    end
  end
end
