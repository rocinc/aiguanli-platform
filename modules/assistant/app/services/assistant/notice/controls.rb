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
    Reply = Data.define(:sentence, :step) do
      def initialize(sentence:, step: nil) = super
    end

    # What the three controls on a notice do (L4.6) and what the assistant
    # says back (L5). Every answer is one sentence that replaces the notice
    # where it stood; the outcome it leaves on the signal is what the
    # learning loop reads.
    class Controls
      MAX_REROUTES = 3

      def initialize(signal, user)
        @signal = signal
        @user = user
      end

      def leave
        settle("rejected", t("replies.rejected"))
      end

      def snooze(choice = nil, reason: nil)
        at = Assistant::Snooze.call(signal, user:, choice:, reason:)
        Reply.new(sentence: t("replies.snoozed", when: Assistant::Text.moment(at)))
      end

      def mute(scope)
        preference = Assistant::Preference.for(user)
        in_project = scope.to_s == "project" && signal.project
        in_project ? preference.mute_in!(signal.detector, signal.project) : preference.mute!(signal.detector)
        settle("muted", muted_sentence(in_project), muted_scope: (in_project ? "project" : "all"))
      end

      def wrong
        settle("wrong", [t("replies.wrong"), Mistake.new(signal).sentence].compact.join(" "))
      end

      def known
        settle("known", t("replies.known"))
      end

      def not_mine
        sentence, rerouted = reroute
        settle("not_mine", sentence, rerouted_to: rerouted&.id)
      end

      def timing
        Reply.new(sentence: t("replies.timing"), step: :timing)
      end

      private

      attr_reader :signal, :user

      def settle(outcome, sentence, **notes)
        signal.settle!(outcome, reply: sentence, **notes)
        Reply.new(sentence:)
      end

      def t(key, **) = I18n.t("assistant.notice.#{key}", **)

      def muted_sentence(in_project)
        rule = rule_title
        key = in_project ? "replies.muted_in_project" : "replies.muted"
        t(key, rule: rule ? "#{rule}这类事" : "这类事", project: signal.project&.name)
      end

      def rule_title
        I18n.t("assistant.insights.detectors.#{signal.detector}.title", default: nil)
      end

      def reroute
        target = next_in_line
        return [t("replies.not_mine_nobody"), nil] unless target

        offered = offered_to(target)
        return [t("replies.not_mine_nobody"), nil] unless offered

        [t("replies.not_mine", name: target.name), target]
      end

      def next_in_line
        subject = signal.subject
        project = signal.project || subject.try(:project)
        return unless project

        owners = subject.is_a?(WorkPackage) ? [subject.assigned_to, subject.responsible] : []
        line = (owners + Assistant::Proactive::Routing.leads(project)).uniq
        told = Assistant::Signal.where(detector: signal.detector, fingerprint: signal.fingerprint).pluck(:recipient_id)
        line.find { eligible?(it, project, told) }
      end

      def eligible?(person, project, told)
        person.is_a?(User) && person.logged? && person.active? && !person.is_a?(AssistantUser) &&
          told.exclude?(person.id) && Assistant::Surface.available?(project, person)
      end

      # The same notice for the next person: the options they may decide stay.
      def offered_to(person)
        options = signal.options.select do |option|
          action = option["action_id"] && Assistant::Action.find_by(id: option["action_id"])
          action.nil? || action.decidable_by?(person)
        end
        return if options.empty? && signal.options.any?

        Assistant::Signal.create!(
          detector: signal.detector, fingerprint: signal.fingerprint, recipient: person, project: signal.project,
          subject: signal.subject, action: signal.action, channel: "brief", state: "pending", score: signal.score,
          deliver_at: Time.current,
          payload: signal.payload.except("reply", "snoozes", "bad_timing", "last_snoozed_at")
                         .merge("options" => options, "rerouted_from" => user.id, "waiting_id" => nil)
        )
      rescue ActiveRecord::RecordNotUnique
        nil
      end
    end
  end
end
