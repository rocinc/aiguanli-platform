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
    # The one line under a notice that says how this person stands to the
    # thing (L4.5). It can only be one of a closed set; "you might be
    # interested" is not among them.
    class Why
      KEYS = %w[owns awaits awaited leads editing duty watches returned hosts member].freeze
      RETURNED = %w[missed_meeting].freeze
      AWAITING = %w[mention_answer].freeze

      def initialize(signal, user)
        @signal = signal
        @user = user
      end

      def key
        @key ||= explicit || from_source || from_subject || "leads"
      end

      def sentence = I18n.t("assistant.notice.why.#{key}", name: lead_of_name)

      private

      attr_reader :signal, :user

      def payload = signal.payload

      def subject = signal.subject

      def explicit = payload["why"].presence_in(KEYS)

      def from_source
        return "duty" if payload["duty_id"].present?
        return "returned" if RETURNED.include?(signal.detector)
        return "awaits" if AWAITING.include?(signal.detector)
        return "awaited" if payload["waiting_id"].present?

        "editing" if signal.channel == "inline" && payload["nature"] == "decision" && subject.is_a?(WorkPackage)
      end

      def from_subject
        return "owns" if payload["nature"] == "own" || owns?
        return "leads" if leads?
        return "watches" if watches?

        "owns" if subject.is_a?(WorkPackage) && payload["nature"] == "object"
      end

      def owns?
        subject.is_a?(WorkPackage) && [subject.assigned_to_id, subject.responsible_id].include?(user.id)
      end

      def leads?
        project && Assistant::Proactive::Routing.leads(project).include?(user)
      end

      def watches? = subject.respond_to?(:watched_by?) && subject.watched_by?(user)

      def project = signal.project || subject.try(:project)

      def lead_of_name
        case subject
        when Version, Project then subject.name
        else project&.name
        end
      end
    end
  end
end
