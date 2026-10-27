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
  # The one way the assistant says "I noticed something" (L1): a sentence,
  # how sure it is, the basis, ways to act with their consequences, why this
  # person sees it, and later / not this kind of thing / this is wrong. Every
  # place draws it with this component, at the density the place has room for.
  class NoticeComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    DENSITIES = %i[line card].freeze
    OPTION_LIMIT = 3
    BASIS_LIMIT = 5
    REASONS = %w[wrong known not_mine bad_timing].freeze

    Choice = Data.define(:label, :consequence, :action, :url, :conversation_id, :reply_draft) do
      def text = consequence.present? ? "#{label} · #{consequence}" : label
    end

    BasisLine = Data.define(:kind, :text, :url)

    BASIS_KINDS = {
      quote: %w[said_change said_promise said_dependency said_split said_time_off said_time_spent said_risk said_knowledge
                meeting_decision_not_applied thread_settled repeated_question unanswered_forum_question
                document_conflicts_decision wiki_contradicts_decision weak_decision forum_request mention_answer
                missed_meeting recognition meeting_prep meeting_without_minutes meeting_unowned meeting_checklist
                meeting_related_decision],
      chain: %w[critical_slip date_change_cascade absence_ripple member_leaving deferred_still_in_version overlap],
      history: %w[third_reschedule assigned_with_history stalled commitment_ladder green_but_slipping time_entry_anomaly
                  said_done_still_open duty_sprint_carryover duty_timesheet_draft],
      external: %w[merged_not_advanced repeated_check_failure review_waiting duty_advance_merged_pr],
      statistic: %w[systematic_underestimate cross_sprint_pattern cross_project_reuse matchmaker pre_mortem
                    possible_duplicate retro_follow_up duty_weekly_status duty_release_watch duty_decision_log
                    duty_devils_advocate duty_onboarding duty_unused]
    }.freeze

    def initialize(signal:, user:, density: :card, heading_level: 3, reply: nil, step: nil, handled: false)
      super()
      @signal = signal
      @user = user
      @density = DENSITIES.include?(density&.to_sym) ? density.to_sym : :card
      @heading_level = heading_level.to_i.clamp(2, 6)
      @reply = reply
      @step = step&.to_sym
      @handled = handled
    end

    attr_reader :signal, :user, :density

    def self.selector(signal, density) = "[data-assistant-signal-id='#{signal.id}'][data-assistant-density='#{density}']"

    def self.dom_id(signal, density) = "assistant-notice-#{signal.id}-#{density}"

    def id = self.class.dom_id(signal, density)

    def title_id = "#{id}-title"

    def heading_tag = :"h#{@heading_level}"

    def card? = density == :card

    def line? = density == :line

    def update_path = url_helpers.assistant_signal_path(signal)

    def render? = !signal.stale? || lingering_stale?

    def lingering_stale? = signal.outcome_at.present? && signal.outcome_at > Assistant::Signal::STALE_LINGERS.ago

    def settled? = signal.outcome.present? || Assistant::Snooze.snoozed?(signal)

    def timing? = @step == :timing

    def fading? = @reply.present?

    def reply_text
      return @reply if @reply.present?
      return signal.reply if signal.reply.present?
      return t("assistant.notice.replies.snoozed", when: Assistant::Text.moment(signal.snoozed_until)) if signal.outcome.nil?

      t("assistant.notice.replies.#{signal.outcome}", default: t("assistant.notice.replies.resolved"))
    end

    def handled? = @handled && @reply.blank? && signal.outcome.in?(%w[adopted edited]) && lingering_stale?

    def handled_html
      done = receipt_action&.then { Receipts::Sentence.new(it, user:).call }
      return with_mark(t("assistant.notice.handled", what: done.text.sub(/\A已把?\s*/, "")), done) if done

      ref = stale_subject_ref
      ref ? t("assistant.notice.handled_in", ref:) : t("assistant.notice.handled_generic")
    end

    def stale_text
      reason = signal.payload["stale_reason"].presence || stale_subject
      t("assistant.notice.stale", reason:)
    end

    def receipt_action
      return unless signal.outcome.in?(%w[adopted edited])

      [signal.action, *choices.filter_map(&:action)].compact.find(&:executed?)
    end

    def answer? = signal.payload["nature"] == "answer"

    def intro? = signal.payload["nature"] == "intro"

    delegate :likely?, to: :signal

    delegate :headline, to: :signal

    def headline_html
      ids = headline.to_s.scan(/#(\d+)/).flatten.map(&:to_i).uniq
      return ERB::Util.html_escape(headline) if ids.empty?

      visible = WorkPackage.visible(user).where(id: ids).index_by(&:id)
      safe_join(headline.to_s.split(/(#\d+)/).map do |part|
        work_package = part.start_with?("#") && visible[part[1..].to_i]
        if work_package
          link_to(part, helpers.work_package_path(work_package), title: work_package.subject,
                                                                 data: { turbo_frame: "_top" })
        else
          part
        end
      end)
    end

    def why = Assistant::Notice::Why.new(signal, user).sentence

    def choices
      @choices ||= begin
        listed = signal.options.select { it.is_a?(Hash) }
        listed = [{ "label" => signal.action.title, "action_id" => signal.action_id }] if listed.empty? && signal.action
        listed.filter_map { build_choice(it) }.first(OPTION_LIMIT)
      end
    end

    def visible_choices = card? ? choices : choices.first(1)

    def hidden_choices = card? ? [] : choices.drop(1)

    def action_ids = choices.filter_map { it.action&.id }

    def basis
      @basis ||= signal.because.each_with_index.reject { |text, _| text.blank? }.first(BASIS_LIMIT).map do |text, index|
        BasisLine.new(basis_kind, text, basis_row_url(index) || basis_url)
      end
    end

    def basis_row_url(index)
      gid = Array(signal.payload["basis_links"])[index].presence or return
      Assistant::Provenance.url_for_basis("gid" => gid)
    end

    def basis_kind
      @basis_kind ||= BASIS_KINDS.find { |_, detectors| detectors.include?(signal.detector) }&.first || :calculation
    end

    def basis_label(kind) = t("assistant.notice.basis_kinds.#{kind}")

    PAIRED = %w[document_conflicts_decision].freeze
    TOLD = %w[missed_meeting].freeze

    def paired? = PAIRED.include?(signal.detector) && basis.size >= 2

    def told? = TOLD.include?(signal.detector) && basis.any?

    def mark = render(Primer::Beta::Octicon.new(icon: :"sparkle-fill", size: :small, color: :muted, "aria-hidden": true))

    def chevron
      render(Primer::Beta::Octicon.new(icon: :"chevron-right", size: :xsmall, classes: "assistant-notice--chevron",
                                       "aria-hidden": true))
    end

    def dismiss_label = answer? || intro? ? t("assistant.notice.got_it") : t("assistant.notice.leave")

    def controls? = !answer? && !intro?

    def foot? = !intro?

    def snooze_choices = Assistant::Snooze.choices(signal, user)

    def snooze_label(choice) = t("assistant.notice.snooze_choices.#{choice}")

    def snooze_hint(at) = Assistant::Text.moment(at)

    def mute_scopes = signal.project ? %w[project all] : %w[all]

    def mute_label(scope) = t("assistant.notice.mute_scopes.#{scope}", project: signal.project&.name)

    def reason_label(reason) = t("assistant.notice.reasons.#{reason}")

    def control_fields(outcome, **extra)
      safe_join([hidden_field_tag(:density, density, id: nil), hidden_field_tag(:heading_level, @heading_level, id: nil),
                 hidden_field_tag(:outcome, outcome, id: nil),
                 *extra.map { |name, value| hidden_field_tag(name, value, id: nil) }])
    end

    def control_form(outcome, label, scheme: :invisible, hint: nil, **extra)
      helpers.form_with(url: update_path, method: :patch, data: { turbo_stream: true }, class: "d-inline") do
        safe_join([control_fields(outcome, **extra),
                   render(Primer::Beta::Button.new(type: :submit, size: :small, scheme:, title: hint,
                                                   "aria-describedby": title_id)) { label }])
      end
    end

    def approve_form(choice)
      action = choice.action
      helpers.form_with(url: url_helpers.approve_assistant_action_path(action), method: :post, data: { turbo_stream: true },
                        class: "d-inline") do
        safe_join([hidden_field_tag(:variant, "compact", id: nil), hidden_field_tag(:heading_level, @heading_level + 1, id: nil),
                   *siblings_of(action).map { hidden_field_tag("siblings[]", it, id: nil) },
                   render(Primer::Beta::Button.new(type: :submit, size: :small, scheme: :default, "aria-describedby": title_id,
                                                   test_selector: "assistant-notice-option")) { choice.text }])
      end
    end

    def siblings_of(action) = action_ids - [action.id]

    def confirm_card(choice)
      render(Assistant::ActionCardComponent.new(action: choice.action, user:, variant: :compact, siblings: siblings_of(choice.action),
                                                heading_level: @heading_level + 1))
    end

    def open_label(choice) = "#{choice.text}…"

    def kind_of_button(choice)
      action = choice.action
      return :conversation if choice.conversation_id
      return :fill_reply if choice.reply_draft
      return :link if action.nil?
      return :none unless action.proposed? && action.decidable_by?(user)

      { "t0" => :open, "t1" => :direct, "t2" => :confirm, "t3" => :go_confirm }.fetch(action.tier, :direct)
    end

    def action_path(choice) = url_helpers.assistant_action_path(choice.action)

    def headline_block
      content_tag(heading_tag, id: title_id, class: "assistant-notice--headline",
                               data: { test_selector: "assistant-notice-headline" }) do
        safe_join([(guess_mark if likely?), headline_html].compact)
      end
    end

    def guess_mark
      content_tag(:span, "◌ ", class: "assistant-notice--guess", title: t("assistant.notice.guess"),
                               "aria-label": t("assistant.notice.guess"), data: { test_selector: "assistant-notice-guess" })
    end

    def basis_block
      return if basis.empty?
      return intro_block if intro?
      return told_block if card? && told?
      return paired_block if card? && paired?

      content_tag(:details, class: "assistant-notice--basis", data: { test_selector: "assistant-notice-basis" }) do
        safe_join([content_tag(:summary, safe_join([chevron, t("assistant.notice.basis", count: basis.size)]),
                               class: "assistant-notice--basis-summary"),
                   content_tag(:ul, class: "assistant-notice--basis-list") { safe_join(basis.map { basis_item(it) }) }])
      end
    end

    def basis_item(line)
      content_tag(:li, class: "assistant-notice--basis-item") do
        safe_join([content_tag(:span, basis_label(line.kind), class: "assistant-notice--basis-kind"), " ", basis_text(line)])
      end
    end

    def basis_text(line)
      return link_to(line.text, line.url, data: { turbo_frame: "_top" }) unless line.text.match?(Assistant::Linkify::BARE_WORK_PACKAGE)

      Assistant::Linkify.call(line.text, user:, project: signal.project)
    end

    def told_block
      content_tag(:div, class: "assistant-notice--told", data: { test_selector: "assistant-notice-told" }) do
        safe_join([content_tag(:p, basis.first.text, class: "assistant-notice--told-text"),
                   (if basis.size > 1
                      content_tag(:ul, class: "assistant-notice--told-yours") do
                        safe_join(basis.drop(1).map do
                          content_tag(:li, it.text)
                        end)
                      end
                    end)].compact)
      end
    end

    def intro_block
      content_tag(:div, class: "assistant-notice--told", data: { test_selector: "assistant-notice-intro" }) do
        safe_join(basis.map { content_tag(:p, it.text, class: "assistant-notice--told-text") })
      end
    end

    def paired_block
      content_tag(:ul, class: "assistant-notice--pairs", "aria-label": t("assistant.notice.pairs_label"),
                       data: { test_selector: "assistant-notice-pairs" }) do
        safe_join(basis.each_slice(2).map do |decided, file_says|
          content_tag(:li, class: "assistant-notice--pair") do
            safe_join([content_tag(:blockquote, decided.text, class: "assistant-notice--pair-side"),
                       (content_tag(:blockquote, file_says.text, class: "assistant-notice--pair-side") if file_says)].compact)
          end
        end)
      end
    end

    def options_block(list, inline: false, leave: false)
      buttons = list.filter_map { option_button(it, inline:) }
      buttons << control_form("rejected", dismiss_label) if leave
      return if buttons.empty?

      content_tag(:div, safe_join(buttons), class: "assistant-notice--options", role: "group",
                                            "aria-label": t("assistant.notice.options"))
    end

    def option_button(choice, inline:)
      case kind_of_button(choice)
      when :direct then approve_form(choice)
      when :confirm then inline ? link_button(choice.text + "…", action_path(choice)) : confirm_disclosure(choice)
      when :open then link_button(choice.text, action_path(choice))
      when :go_confirm then safe_join([content_tag(:span, choice.text, class: "assistant-notice--option-text"),
                                       link_button(t("assistant.notice.go_confirm"), action_path(choice))])
      when :link then link_button(choice.text, choice.url)
      when :conversation then conversation_button(choice)
      when :fill_reply then fill_reply_button(choice)
      end
    end

    def link_button(label, href)
      render(Primer::Beta::Button.new(tag: :a, href:, size: :small, scheme: :default, data: { turbo_frame: "_top" },
                                      test_selector: "assistant-notice-option")) { label }
    end

    def fill_reply_button(choice)
      controller = WorkPackages::ActivitiesTab::StimulusControllers.reply_draft_stimulus_controller
      editor = WorkPackages::ActivitiesTab::StimulusControllers.editor_stimulus_controller
      data = { controller:, action: "click->#{controller}#fill",
               "#{controller}-text-param": choice.reply_draft,
               "#{controller}-#{editor}-outlet": WorkPackages::ActivitiesTab::StimulusControllers.index_component_dom_selector,
               turbo_frame: "_top", test_selector: "assistant-notice-option" }
      data = with_second_draft(data, controller, choice) if asking?(choice)
      render(Primer::Beta::Button.new(tag: :a, href: subject_url, size: :small, scheme: :default, data:)) { choice.text }
    end

    def with_second_draft(data, controller, choice)
      data.merge(controller: "#{controller} assistant--reveal", action: "#{data[:action]} click->assistant--reveal#show",
                 "assistant--reveal-id-param": ask_id(choice))
    end

    def asking?(choice) = choice.reply_draft && choice.action && Assistant::Drafts.draft?(choice.action, user)

    def ask_id(choice) = "#{id}-ask-#{choice.action.id}"

    def asks_block
      asking = choices.select { asking?(it) }
      return if asking.empty?

      safe_join(asking.map do |choice|
        content_tag(:div, render(Assistant::DraftComponent.new(action: choice.action, user:, heading_level: @heading_level + 1)),
                    id: ask_id(choice), hidden: true, class: "assistant-notice--ask", data: { test_selector: "assistant-notice-ask" })
      end)
    end

    def conversation_button(choice)
      render(Primer::Beta::Button.new(type: :button, size: :small, scheme: :default,
                                      data: { assistant_panel_open: true, assistant_conversation: choice.conversation_id,
                                              test_selector: "assistant-notice-option" })) { t("assistant.signal.open_conversation") }
    end

    def confirm_disclosure(choice)
      content_tag(:details, class: "assistant-notice--confirm", data: { test_selector: "assistant-notice-confirm" }) do
        safe_join([content_tag(:summary, content_tag(:span, content_tag(:span, open_label(choice), class: "Button-label"),
                                                     class: "Button-content"),
                               class: "Button Button--small Button--secondary", data: { test_selector: "assistant-notice-option" }),
                   confirm_card(choice)])
      end
    end

    def controls_block
      content_tag(:div, class: "assistant-notice--controls", data: { test_selector: "assistant-notice-controls" }) do
        safe_join([say_button, snooze_menu, mute_menu, wrong_menu].compact)
      end
    end

    def say_button = render(Assistant::SayButtonComponent.new(record: signal, user:, describedby: title_id))

    def snooze_menu
      return if snooze_choices.empty?

      menu("snooze", t("assistant.notice.snooze")) do
        snooze_choices.map { |choice, at| control_form("snoozed", snooze_label(choice), hint: snooze_hint(at), until: choice) }
      end
    end

    def mute_menu
      menu("mute", t("assistant.notice.mute")) do
        mute_scopes.map { |scope| control_form("muted", mute_label(scope), scope:) }
      end
    end

    def wrong_menu
      menu("wrong", t("assistant.notice.wrong")) do
        REASONS.map { |reason| control_form(reason, reason_label(reason)) }
      end
    end

    def menu(key, label)
      content_tag(:details, class: "assistant-notice--menu", data: { test_selector: "assistant-notice-#{key}" }) do
        safe_join([content_tag(:summary, content_tag(:span, content_tag(:span, label, class: "Button-label"), class: "Button-content"),
                               class: "Button Button--small Button--invisible", "aria-describedby": title_id),
                   content_tag(:div, safe_join(yield), class: "assistant-notice--menu-items")])
      end
    end

    def css_classes
      ["assistant-notice", "assistant-notice--#{density}", ("assistant-notice--likely" if likely?)]
    end

    private

    def stale_subject
      ref = stale_subject_ref
      ref ? t("assistant.notice.stale_subject", ref:) : t("assistant.notice.stale_generic")
    end

    def stale_subject_ref
      subject = signal.subject
      case subject
      when WorkPackage then "##{subject.id}"
      when Version, Project then subject.name
      end
    end

    def with_mark(text, sentence)
      object = sentence.url ? link_to(sentence.label, sentence.url, data: { turbo_frame: "_top" }) : ERB::Util.html_escape(sentence.label.to_s)
      ERB::Util.html_escape(text).to_str.sub(Receipts::Sentence::MARK) { object.to_s }.html_safe
    end

    def build_choice(option)
      action = Assistant::Action.find_by(id: option["action_id"]) if option["action_id"]
      return if option["action_id"] && action.nil?

      label, tail = split_label(option["label"].to_s)
      consequence = option["consequence"].presence || tail || (action && summary_of(action))
      Choice.new(label:, consequence:, action:, url: option["url"].presence, conversation_id: option["conversation_id"].presence,
                 reply_draft: option["reply_draft"].presence)
    end

    def split_label(label)
      match = label.match(/\A(.+?)\s*[（(]([^（()）]+)[）)]\s*\z/)
      match ? [match[1], match[2]] : [label, nil]
    end

    def summary_of(action)
      Assistant::Consequences.new(Assistant::PreviewPresenter.new(action.preview), user:).summary.presence
    rescue StandardError
      nil
    end

    def basis_url
      @basis_url ||= source_url || subject_url
    end

    def source_url
      gid = signal.payload["source_gid"].presence or return
      Assistant::Provenance.url_for_basis("gid" => gid)
    end

    def subject_url
      subject = signal.subject
      case subject
      when WorkPackage then helpers.work_package_path(subject, tab: basis_kind == :chain ? "relations" : "activity")
      when Version then helpers.version_path(subject)
      when Meeting then helpers.meeting_path(subject)
      when Project then helpers.project_path(subject)
      else signal.project ? helpers.project_path(signal.project) : helpers.my_page_path
      end
    end
  end
end
