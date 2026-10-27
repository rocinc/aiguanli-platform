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
  # What a person rewrote in the assistant's drafts (L5), kept in their own
  # preferences by kind of draft, and read back when the next one of that kind
  # is written. Only heavy rewrites are kept, and only the person who made
  # them ever sees them.
  module Revisions
    HEAVY = 0.3
    KEPT = 5
    SHOWN = 3
    TEXT = 300
    LEARNED = Assistant::Actions::Revise::FIELDS.values.flatten.uniq - %w[hours status_code]

    class << self
      def record(user:, key:, edits:)
        heavy = edits.select { LEARNED.include?(it["attribute"]) && heavy?(it["before"], it["after"]) }
        return if heavy.empty?

        preference = Assistant::Preference.for(user)
        kept = Array(preference.thresholds.dig("revisions", key)) + heavy.map { it.slice("attribute", "before", "after") }
        preference.update!(thresholds: preference.thresholds.deep_merge("revisions" => { key => kept.last(KEPT) }))
      end

      # The last few rewrites of these kinds, newest first, cut to what a prompt needs.
      def examples(user, *keys)
        return [] if user.nil?

        stored = Assistant::Preference.find_by(owner: user)&.thresholds.to_h["revisions"].to_h
        keys.flat_map { Array(stored[it]) }.last(SHOWN).reverse.map do |edit|
          edit.merge("before" => edit["before"].to_s.first(TEXT), "after" => edit["after"].to_s.first(TEXT))
        end
      end

      def key_for(action)
        gid = action.basis.filter_map { (it["gid"] || it[:gid]).presence }.filter_map { GlobalID.parse(it) }
                    .find { it.model_name == "Assistant::Duty" }
        (gid && Assistant::Duty.find_by(id: gid.model_id)&.kind) || action.kind
      end

      def heavy?(before, after) = change(before, after) > HEAVY

      # Share of the text that is not found again in the other, by pairs of letters, so that
      # it works for languages written without spaces.
      def change(before, after)
        was = pairs(before)
        now = pairs(after)
        return (was.empty? && now.empty? ? 0.0 : 1.0) if was.empty? || now.empty?

        shared = was.tally.sum { |pair, count| [count, now.count(pair)].min }
        1.0 - (2.0 * shared / (was.size + now.size))
      end

      private

      def pairs(text)
        letters = text.to_s.gsub(/\s+/, " ").strip.chars
        letters.size < 2 ? letters : letters.each_cons(2).to_a
      end
    end
  end
end
