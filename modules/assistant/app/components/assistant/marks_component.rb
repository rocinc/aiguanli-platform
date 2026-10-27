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
  # S5.1 and S5.3: the decisions on record that bear on this object, and who
  # has said they would do it, as facts that stay on the page. Not notices: no
  # snooze, no "this is wrong", and no place in the notice capacity. Nothing
  # to show, nothing rendered.
  class MarksComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    def initialize(object:, user:, parts: %i[decisions promises])
      super()
      @object = object
      @user = user
      @parts = parts
    end

    attr_reader :object, :user

    def marks = @marks ||= @parts.include?(:decisions) ? Assistant::Marks.for(object, user) : []

    def promises = @promises ||= @parts.include?(:promises) ? Assistant::PromiseMarks.for(object, user) : []

    def render? = marks.any? || promises.any?

    def record_page = @record_page ||= Assistant::DecisionRecord.page(object.try(:project) || object, user)

    def sentence(mark)
      return t("assistant.marks.sentence_here", day: mark.day, title: mark.decision.title) unless mark.where

      t("assistant.marks.sentence", day: mark.day, where: mark.where, title: mark.decision.title)
    end

    def summary
      first = marks.first
      return sentence(first) if marks.one?

      t("assistant.marks.summary_many", sentence: sentence(first), count: marks.size - 1)
    end

    def promise_sentence(promise)
      key = promise.said ? "promise" : "promise_plain"
      Assistant::PersonInText.call(self, "assistant.marks.#{key}.#{promise.kind}", { name: promise.person || promise.speaker },
                                   day: promise.day, said: promise.said)
    end

    def call
      safe_join([(decisions if marks.any?), (promised if promises.any?)].compact)
    end

    private

    def promised
      content_tag(:div, class: "assistant-object-line assistant-promises", role: "region",
                        "aria-label": t("assistant.marks.promises_label"), data: { test_selector: "assistant-promises" }) do
        safe_join(promises.map do |promise|
          content_tag(:div, class: "assistant-promises--item", data: { test_selector: "assistant-promise" }) do
            safe_join([content_tag(:p, safe_join([sparkle, promise_sentence(promise)]), class: "assistant-promises--sentence"),
                       verbs(promise.intent)])
          end
        end)
      end
    end

    def sparkle = render(Primer::Beta::Octicon.new(icon: :"sparkle-fill", size: :small, color: :muted, "aria-hidden": true))

    def decisions
      content_tag(:div, class: "assistant-object-line assistant-marks", role: "region",
                        "aria-label": t("assistant.marks.label"), data: { test_selector: "assistant-marks" }) do
        content_tag(:details, class: "assistant-notice assistant-notice--line assistant-notice--fold") do
          safe_join([summary_row, content_tag(:div, safe_join([*marks.each_with_index.map { |mark, index| entry(mark, headline: index.zero?) }, record_link]),
                                              class: "assistant-notice--main assistant-marks--entries")])
        end
      end
    end

    def summary_row
      content_tag(:summary, class: "assistant-notice--row assistant-notice--summary") do
        safe_join([render(Primer::Beta::Octicon.new(icon: :"sparkle-fill", size: :small, color: :muted, "aria-hidden": true)),
                   content_tag(:div, content_tag(:p, summary, class: "assistant-notice--headline"),
                               class: "assistant-notice--body"),
                   content_tag(:span, chevron, class: "assistant-notice--toggle")])
      end
    end

    def entry(mark, headline:)
      content_tag(:div, class: "assistant-marks--entry", data: { test_selector: "assistant-mark" }) do
        safe_join([(content_tag(:p, mark.decision.title, class: "assistant-marks--title") unless headline),
                   content_tag(:blockquote, mark.decision.quote, class: "assistant-marks--quote"),
                   content_tag(:p, origin(mark), class: "assistant-marks--origin"),
                   verbs(mark.decision)].compact)
      end
    end

    def verbs(intent) = render(Assistant::IntentVerbsComponent.new(intent:, user:, density: :compact))

    def origin(mark)
      who = mark.person ? Assistant::PersonInText.call(self, "assistant.marks.said_by", { name: mark.person }, day: mark.day) : mark.day
      return who unless mark.url

      label = mark.where ? t("assistant.marks.original", where: mark.where) : t("assistant.marks.original_here")
      safe_join([who, link_to(label, mark.url, data: { turbo_frame: "_top" })], " · ")
    end

    def record_link
      return unless record_page

      content_tag(:p, link_to(t("assistant.marks.record", title: record_page.title),
                              project_wiki_path(record_page.project, record_page), data: { turbo_frame: "_top" }),
                  class: "assistant-marks--record")
    end

    def chevron
      render(Primer::Beta::Octicon.new(icon: :"chevron-right", size: :xsmall, classes: "assistant-notice--chevron",
                                       "aria-hidden": true))
    end
  end
end
