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
  module Actions
    # A person edits a draft before it goes out: the words of one step, and
    # for news its title and summary. Only those attributes change; the action
    # is previewed and tiered again, since new words can touch new things.
    class Revise
      FIELDS = {
        "publish_news" => %w[title summary description],
        "send_mail" => %w[subject body],
        "update_project_status" => %w[status_code status_explanation],
        "comment" => %w[notes],
        "create_forum_reply" => %w[content],
        "create_news_comment" => %w[comments],
        "create_wiki_page" => %w[text],
        "create_work_package" => %w[subject description],
        "update_work_package" => %w[description],
        "create_time_entry" => %w[hours comments],
        "create_meeting_outcome" => %w[notes]
      }.freeze
      MAX_LENGTH = 30_000
      EDITS_KEPT = 5
      EDIT_TEXT = 600
      MENTIONING = %w[notes content comments description text summary status_explanation].freeze
      WORDS = (MENTIONING + %w[body]).freeze

      def self.call(...) = new(...).call

      # `edits` is { step index => { attribute => value } }.
      def initialize(action, user:, edits:)
        @action = action
        @user = user
        @edits = edits.to_h
      end

      def call
        steps = action.steps.each_with_index.map { |step, index| revise(step, @edits[index.to_s] || @edits[index]) }
        return action if steps == action.steps

        preview = Preview.new(steps:, user: action.on_behalf_of || user).call
        return failed(preview) unless preview.success

        made = edits_between(action.steps, steps)
        action.plan = action.plan.merge("steps" => steps, "revised_by_id" => user.id,
                                        "edits" => (Array(action.plan["edits"]) + made).last(EDITS_KEPT))
        action.preview = preview.to_h
        action.tier = Tiering.lowered_by_grant(action, Tiering.call(action:, preview: action.preview))
        action.save!
        Assistant::Revisions.record(user:, key: Assistant::Revisions.key_for(action), edits: made)
        action
      end

      private

      attr_reader :action, :user

      # What the person changed in the words, kept for the next draft of its kind (L5).
      def edits_between(before, after)
        before.zip(after).flat_map do |was, now|
          now.fetch("attributes", {}).filter_map do |attribute, value|
            old = was.dig("attributes", attribute)
            next if old == value || !FIELDS.fetch(now["op"].to_s, []).include?(attribute)

            { "attribute" => attribute, "before" => old.to_s.first(EDIT_TEXT), "after" => value.to_s.first(EDIT_TEXT) }
          end
        end
      end

      def revise(step, edit)
        allowed = FIELDS[step["op"].to_s]
        return step unless allowed && edit.respond_to?(:to_h)

        changes = edit.to_h.stringify_keys.slice(*allowed)
                      .transform_values { it.to_s.gsub("\r\n", "\n").strip.first(MAX_LENGTH) }
        changes.each { |key, value| changes[key] = with_mentions(value, step, key) if MENTIONING.include?(key) }
        changes.delete("status_code") unless ::Project.status_codes.key?(changes["status_code"].to_s)
        changes.reject! { |key, value| value.blank? && %w[title subject].include?(key) }
        step.merge("attributes" => step.fetch("attributes", {}).merge(changes))
      end

      def with_mentions(text, step, attribute)
        Assistant::Mentions.from_text(text, original: step.dig("attributes", attribute), project: action.project)
      end

      def failed(preview)
        action.errors.add(:base, preview.errors.join("; "))
        action
      end
    end
  end
end
