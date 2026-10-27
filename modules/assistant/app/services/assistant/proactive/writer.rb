# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

module Assistant
  module Proactive
    # Writes the words of a notice that passed the gate: one neutral line,
    # and a short line per option. The facts and options themselves are
    # computed already; the model only phrases them. Without a model the
    # detector's own headline is used, so nothing is lost when it is off.
    class Writer
      HEADLINE_LIMIT = 40
      VERBATIM = %w[assigned_with_history].freeze

      SYSTEM = <<~PROMPT
        You phrase one notice from a project assistant to one person. You get computed facts, the
        reason this person is told, and options that are already prepared. Write in the given language.
        Return JSON: {"headline": "...", "options": ["...", ...]}.
        - headline: one sentence naming the object, the fact and what follows, at most 40 characters, neutral, no emotion words, no "urgent", no
          emojis, says what is the case and why it matters (e.g. "#69 在 v2.0 的关键路径上，已推迟两次，再推 3 天发布就会滑期").
        - options: one short label per given option, same order, imperative, with its consequence in
          a few words in parentheses.
        Never add facts that are not given. Never blame anyone.
      PROMPT

      def initialize(candidate, options, llm: nil)
        @candidate = candidate
        @options = options
        @llm = llm
      end

      def call
        fallback = { "headline" => @candidate.headline.to_s, "options" => @options.map { it[:label] } }
        return fallback if @candidate.detector.in?(VERBATIM)
        return fallback unless Assistant::Llm.configured? && !Assistant::Usage.near_budget?(project: @candidate.project)

        data = OpenProject::LocaleHelper.with_locale_for(@candidate.recipient) do
          llm.json(system: SYSTEM, user: JSON.generate(input), max_tokens: 1200)
        end
        headline = data["headline"].to_s.strip
        headline = fallback["headline"] if headline.blank? || headline.length > HEADLINE_LIMIT
        labels = Array(data["options"]).map(&:to_s)
        labels = fallback["options"] unless labels.size == @options.size
        { "headline" => headline.truncate(80), "options" => labels }
      rescue Assistant::Llm::Error
        fallback
      end

      private

      def llm = @llm ||= Assistant::Llm.new(purpose: "proactive", user: @candidate.recipient, project: @candidate.project)

      def input
        { "language" => @candidate.recipient.language.presence || I18n.locale.to_s,
          "draft_headline" => @candidate.headline, "facts" => @candidate.because,
          "why_you" => I18n.t("assistant.proactive.why.#{@candidate.nature}", default: ""),
          "options" => @options.map { { "label" => it[:label], "consequence" => it[:consequence] } } }
      end
    end
  end
end
