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
  class Drafts
    # What a draft form tells the writing runs it starts (rewrite the whole
    # text, rewrite one passage): where the words go, who signs them and what
    # they were based on, so a new version is still the same draft. Only the
    # words are rewritten; the target, the signature and the basis stay as
    # they are, since the form posts nothing but the text fields.
    class Refinement
      TEXTS = %w[revising refining revise_failed refine_failed empty_result stopped_kept leave_confirm reread
                 revised refined version_position failed].freeze

      def self.available? = Assistant::Llm.configured?

      def self.words?(attribute) = Assistant::Actions::Revise::WORDS.include?(attribute.to_s)

      def initialize(action:, url:, lead:, signer: nil, basis: [])
        @action = action
        @url = url
        @lead = lead
        @signer = signer
        @basis = basis
      end

      def form_data
        {
          controller: "assistant--draft-refine",
          action: "keydown->assistant--draft-refine#keydown",
          "assistant--draft-refine-url-value": @url,
          "assistant--draft-refine-scope-value": scope.to_json,
          "assistant--draft-refine-texts-value": texts.to_json
        }
      end

      def task(label)
        about = ["这是 AI 助理替人写好、等署名的人看过再发出的一份草稿里的「#{label}」", "用途：#{@lead}", signed].compact_blank
        "#{about.join('。')}。要像署名的人自己在说话；人名、以 @ 开头的提及、数字、日期、链接和文件名原样保留；" \
          "不要编造原稿和依据里没有的事实、数字或日期；不要加署名、落款或寒暄。"
      end

      def material(text)
        parts = ["草稿原文：\n#{text}"]
        parts << "依据：\n#{@basis.map { "- #{it}" }.join("\n")}" if @basis.any?
        parts.join("\n\n")
      end

      private

      def signed = @signer && "署名的人是 #{@signer.name}，稿子用这个人的口吻写"

      def scope = { project_id: @action.project_id }.compact

      def texts = TEXTS.index_with { I18n.t("assistant.draft_loop.texts.#{it}") }
    end
  end
end
