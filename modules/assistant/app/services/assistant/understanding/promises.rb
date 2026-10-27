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
  module Understanding
    # A firm promise about one's own work puts its date on the work package
    # (02 §2.1 承诺, D12): "我周五前搞定" said by the assignee of the work
    # package it is said on. The date lives where everyone reads it; the
    # ledger keeps only the words. Later than the planned date, or someone
    # else's work, it is offered instead of done.
    class Promises
      def self.for(items) = new(items).call

      def initialize(items)
        @items = Array(items)
      end

      def call
        @items.filter_map do |item|
          next unless item.kind == "commitment" && item.strength == "firm" && item.said_due_on && item.live?

          wp = item.subject
          next unless wp.is_a?(WorkPackage) && item.owner.is_a?(User) && wp.assigned_to_id == item.owner_id
          next if wp.due_date == item.said_due_on || (wp.start_date && item.said_due_on < wp.start_date)

          OpenProject::LocaleHelper.with_locale_for(item.owner) { propose(item, wp) }
        end
      end

      private

      def propose(item, wp)
        sooner = wp.due_date.nil? || item.said_due_on < wp.due_date
        asked_first = Assistant::Preference.for(item.owner).asks_first?("promise_date")
        action = Assistant::Actions::Propose.call(
          kind: "promise_date", on_behalf_of: item.owner, project: item.project, subject: wp, auto_execute: sooner && !asked_first,
          title: I18n.t("assistant.understanding.promise", ref: "##{wp.id}", date: Assistant::Text.day(item.said_due_on)),
          steps: [{ "op" => "update_work_package", "type" => "WorkPackage", "id" => wp.id,
                    "attributes" => { "due_date" => item.said_due_on.iso8601 } }],
          basis: [Assistant::Basis.for(item.source, quote: item.quote)]
        )
        ask(item, wp, action) if action.proposed?
        action
      end

      # Not done by itself, so it waits for the speaker where they said it.
      def ask(item, wp, action)
        %w[inline brief].each do |channel|
          Assistant::Signal.offer!(
            detector: "said_promise", fingerprint: "#{item.source.to_gid}|#{action.id}|#{channel}", recipient: item.owner,
            project: item.project, subject: wp, action:, channel:, state: "pending", score: 30, deliver_at: Time.current,
            payload: { "headline" => I18n.t("assistant.understanding.promise_ask", ref: "##{wp.id}", date: Assistant::Text.day(item.said_due_on),
                                                                                    was: wp.due_date ? Assistant::Text.day(wp.due_date) : "–"),
                       "because" => ["“#{item.quote}”"], "why_me" => I18n.t("assistant.understanding.why"), "nature" => "decision",
                       "certainty" => "fact", "source_gid" => item.source.to_gid.to_s, "work_package_id" => wp.id,
                       "options" => [{ "label" => I18n.t("assistant.understanding.promise_keep"), "action_id" => action.id }] }
          )
        rescue ActiveRecord::RecordNotUnique
          nil
        end
      end
    end
  end
end
