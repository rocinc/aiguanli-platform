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
  # The verbs of one remembered thing (a promise, a deferral, a decision, a
  # question, an objection) as a row under its line: the one or two used most
  # next to it, the rest behind "…", and whatever a verb produced right
  # there: a receipt, a draft to send, a sentence saying why not.
  class IntentVerbsComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    def self.frame_id(intent) = "assistant-verbs-#{intent.id}"

    def self.panel_id(intent) = "assistant-verb-panel-#{intent.id}"

    DENSITIES = %i[regular compact].freeze

    def initialize(intent:, user:, meeting: nil, result: nil, density: :regular, lead: nil)
      super()
      @intent = intent
      @user = user
      @meeting = meeting
      @result = result
      @density = DENSITIES.include?(density.to_s.to_sym) ? density.to_s.to_sym : :regular
      @lead = lead
    end

    attr_reader :intent, :user, :meeting, :result, :density, :lead

    def compact? = density == :compact

    def verbs
      @verbs ||= begin
        Assistant::IntentVerbs::Effects.reconcile(intent)
        Assistant::IntentVerbs.new(intent, user, meeting:, lead:)
      end
    end

    def render? = user&.logged? && (result.present? || verbs.verbs.any? || verbs.scheduled.any? || drafts.any? || say.render?)

    def call
      helpers.turbo_frame_tag(self.class.frame_id(intent), class: ["assistant-verbs", ("assistant-verbs--compact" if compact?)],
                                                           data: { controller: "assistant--verbs",
                                                                   test_selector: "assistant-intent-verbs",
                                                                   "assistant--verbs-open-class": "is-open" }) do
        safe_join([scheduled_lines, outcome, drafts.map { render(draft_card(it)) }, bar, panel].flatten.compact)
      end
    end

    private

    def say = @say ||= Assistant::SayButtonComponent.new(record: intent, user:, menu: compact?)

    def direct_limit = compact? ? 1 : Assistant::IntentVerbs::DIRECT

    def drafts = @drafts ||= verbs.drafts.reject { it.id == result&.action&.id }.to_a

    def draft_card(action) = Assistant::DraftComponent.new(action:, user:, density: :card, heading_level: 5)

    def scheduled_lines
      verbs.scheduled.map do |entry|
        date = I18n.l(entry.meeting.start_time.to_date, format: "%-m/%-d")
        content_tag(:p, class: "assistant-verbs--state", data: { test_selector: "assistant-intent-scheduled" }) do
          safe_join([render(Primer::Beta::Octicon.new(icon: :calendar, size: :xsmall, color: :muted, "aria-hidden": true)),
                     link_to(t("assistant.verbs.scheduled", date:, title: entry.meeting.title.truncate(40)),
                             helpers.meeting_path(entry.meeting), data: { turbo_frame: "_top" })])
        end
      end
    end

    def outcome
      return unless result

      case result.state
      when :done then render(Assistant::ReceiptComponent.new(action: result.action, user:, density: :line))
      when :draft then render(draft_card(result.action))
      when :shelved then shelved
      when :refused then refused
      end
    end

    def shelved
      content_tag(:p, class: "assistant-verbs--state", role: "status", data: { test_selector: "assistant-intent-shelved" }) do
        safe_join([t("assistant.verbs.shelved", title: intent.title.truncate(50)),
                   helpers.button_to(t("assistant.verbs.undo"), helpers.assistant_shelved_intent_path(intent, context_meeting_id: meeting&.id, density:, lead:),
                                     method: :post, class: "Button Button--link Button--small",
                                     form_class: "assistant-verbs--inline-form")], " ")
      end
    end

    def refused
      content_tag(:p, result.message, class: "assistant-verbs--state assistant-verbs--refused", role: "status")
    end

    def bar
      return if (verbs.verbs.empty? && !say.render?) || result&.state == :shelved

      content_tag(:div, class: "assistant-verbs--bar", role: "group", "aria-label": t("assistant.verbs.label"),
                        data: { test_selector: "assistant-intent-verbs-bar" }) do
        safe_join([*verbs.direct(direct_limit).map { verb_button(it) }, more_menu, (render(say) unless compact?)])
      end
    end

    def verb_label(verb)
      key = verb == "assign" && !intent.commitment_like? ? "assign_question" : verb
      t("assistant.verbs.labels.#{key}")
    end

    def verb_path(verb) = helpers.assistant_intent_verb_path(intent, verb, context_meeting_id: meeting&.id, density:, lead:)

    def verb_button(verb, menu: false)
      return shelve_button(menu:) if verb == "shelve"

      render(Primer::Beta::Button.new(tag: :a, href: verb_path(verb), scheme: :invisible, size: :small,
                                      role: (:menuitem if menu), aria: { expanded: false, controls: self.class.panel_id(intent) },
                                      data: { turbo_frame: self.class.panel_id(intent), verb:, test_selector: "assistant-verb-#{verb}",
                                              action: "click->assistant--verbs#open",
                                              "assistant--verbs-target": "trigger" })) do |button|
        button.with_trailing_visual_icon(icon: :"triangle-down") unless menu
        verb_label(verb)
      end
    end

    def shelve_button(menu:)
      helpers.button_to(verb_label("shelve"), verb_path("shelve"), method: :post, role: (:menuitem if menu),
                                                                   class: "Button Button--invisible Button--small",
                                                                   form_class: "assistant-verbs--inline-form",
                                                                   data: { test_selector: "assistant-verb-shelve" })
    end

    def more_menu
      items = verbs.more(direct_limit).map { verb_button(it, menu: true) }
      items << render(say) if compact? && say.render?
      return if items.empty?

      content_tag(:details, class: "assistant-verbs--more", data: { "assistant--verbs-target": "more" }) do
        safe_join([content_tag(:summary, render(Primer::Beta::Octicon.new(icon: :"kebab-horizontal", size: :small)),
                               class: "Button Button--invisible Button--small", "aria-label": t("assistant.verbs.more"),
                               data: { test_selector: "assistant-verbs-more" }),
                   content_tag(:div, safe_join(items), class: "assistant-verbs--menu", role: "menu")])
      end
    end

    def panel
      content_tag(:div, class: "assistant-verbs--panel", inert: true, data: { "assistant--verbs-target": "panel" }) do
        content_tag(:div, helpers.turbo_frame_tag(self.class.panel_id(intent), data: { "assistant--verbs-target": "frame" }),
                    class: "assistant-verbs--panel-inner")
      end
    end
  end
end
