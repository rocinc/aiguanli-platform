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
  # The one question after someone takes back what the assistant did under a
  # grant: should that kind of thing wait for them from now on? Answered, it
  # turns into the sentence that says what changed.
  class HandoverAskComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    def self.dom_id(action) = "assistant-handover-#{action.id}"

    def initialize(action:, sentence: nil)
      super()
      @action = action
      @sentence = sentence
    end

    attr_reader :action, :sentence

    def id = self.class.dom_id(action)

    def path = url_helpers.handover_assistant_action_path(action)

    def answer_form(answer, label, scheme)
      helpers.form_with(url: path, method: :post, data: { turbo_stream: true }, class: "d-inline") do
        safe_join([hidden_field_tag(:answer, answer, id: nil),
                   render(Primer::Beta::Button.new(type: :submit, size: :small, scheme:,
                                                   test_selector: "assistant-handover-#{answer}")) { label }])
      end
    end

    def call
      content_tag(:div, id:, class: "assistant-notice assistant-notice--settled", role: "group",
                        "aria-label": t("assistant.notice.handover.label")) do
        sentence ? answered : question
      end
    end

    private

    def mark = render(Primer::Beta::Octicon.new(icon: :"sparkle-fill", size: :small, color: :muted, "aria-hidden": true))

    def question
      safe_join([content_tag(:p, safe_join([mark, content_tag(:span, t("assistant.notice.handover.ask"))]),
                             class: "assistant-notice--reply", role: "status"),
                 content_tag(:div, safe_join([answer_form("yes", t("assistant.notice.handover.yes_button"), :default),
                                              answer_form("no", t("assistant.notice.handover.no_button"), :invisible)]),
                             class: "assistant-notice--choices")])
    end

    def answered
      content_tag(:p, safe_join([mark, content_tag(:span, sentence, class: "assistant-notice--reply-text")]),
                  class: "assistant-notice--reply assistant-notice--fading", role: "status")
    end
  end
end
