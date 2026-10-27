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
  # The small panel a verb opens in place: the fewest choices that decide it,
  # then, where the change touches others, what it would do before anything
  # is done. It answers inside its own frame; the result lands in the row.
  class IntentVerbPanelComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    def initialize(verbs:, verb:, user:, params: {}, trial: nil, message: nil, density: :regular, lead: nil)
      super()
      @verbs = verbs
      @verb = verb.to_s
      @user = user
      @params = params.to_h.symbolize_keys
      @trial = trial
      @message = message
      @density = density
      @lead = lead
    end

    attr_reader :verbs, :verb, :user, :params, :trial, :message, :density, :lead

    delegate :intent, :meeting, to: :verbs

    def call
      helpers.turbo_frame_tag(Assistant::IntentVerbsComponent.panel_id(intent), data: { "assistant--verbs-target": "frame" }) do
        safe_join([message_line, (trial ? confirmation : choices)].compact)
      end
    end

    private

    def message_line
      return unless message

      content_tag(:p, message, class: "assistant-verbs--refused", role: "alert",
                               data: { test_selector: "assistant-verb-message" })
    end

    def choices
      case verb
      when "schedule" then schedule
      when "assign" then assign
      when "remind" then remind
      when "answer", "record" then record
      end
    end

    def act_path = helpers.assistant_intent_verb_path(intent, verb)

    def preview_path = helpers.assistant_preview_intent_verb_path(intent, verb)

    def form(path, **, &)
      helpers.form_with(url: path, method: :post, class: "assistant-verbs--form",
                        data: { action: "keydown->assistant--verbs#key", test_selector: "assistant-verb-form-#{verb}" }, **, &)
    end

    def context_field
      safe_join([helpers.hidden_field_tag(:context_meeting_id, meeting&.id, id: nil),
                 helpers.hidden_field_tag(:density, density, id: nil),
                 (helpers.hidden_field_tag(:lead, lead, id: nil) if lead)].compact)
    end

    def actions(label, ready: true)
      content_tag(:div, class: "assistant-verbs--actions") do
        safe_join([render(Primer::Beta::Button.new(type: :submit, scheme: :primary, size: :small, disabled: !ready,
                                                   data: { "assistant--verbs-target": "submit", test_selector: "assistant-verb-submit" })) { label },
                   render(Primer::Beta::Button.new(type: :button, scheme: :invisible, size: :small,
                                                   data: { action: "assistant--verbs#close" })) { t("assistant.verbs.cancel") }])
      end
    end

    def schedule
      form(act_path) do
        safe_join([context_field,
                   content_tag(:fieldset, class: "assistant-verbs--choices") do
                     safe_join([content_tag(:legend, t("assistant.verbs.panel.schedule.legend")),
                                *verbs.schedule_targets.each_with_index.map do |entry, index|
                                  meeting_choice(entry, index.zero?)
                                end])
                   end,
                   actions(t("assistant.verbs.panel.schedule.confirm"))])
      end
    end

    def meeting_choice(entry, checked)
      date = Assistant::Text.day(entry.meeting.start_time.to_date)
      lead = entry.here ? t("assistant.verbs.panel.schedule.here") : nil
      choice("meeting_id", entry.meeting.id, checked:, label: lead || entry.meeting.title.truncate(48),
                                             hint: [date, (entry.meeting.title.truncate(40) if lead)].compact.join(" · "))
    end

    def choice(name, value, label:, hint: nil, checked: false, avatar: nil, **data)
      content_tag(:label, class: "assistant-verbs--choice", data: { "assistant--verbs-target": "choice", **data }) do
        safe_join([helpers.radio_button_tag(name, value, checked, id: nil, data: { action: "change->assistant--verbs#chosen" }),
                   avatar,
                   content_tag(:span, label, class: "assistant-verbs--choice-label"),
                   (content_tag(:span, hint, class: "assistant-verbs--choice-hint") if hint)].compact)
      end
    end

    def assign
      form(intent.commitment_like? ? preview_path : act_path) do
        safe_join([context_field, finder, list, actions(assign_label, ready: false)])
      end
    end

    def assign_label
      intent.commitment_like? ? t("assistant.verbs.panel.assign.preview") : t("assistant.verbs.panel.assign.draft")
    end

    def finder
      content_tag(:div, class: "assistant-verbs--find") do
        safe_join([helpers.search_field_tag(:q, nil, id: nil, autocomplete: "off", "aria-label": t("assistant.verbs.panel.assign.filter"),
                                                     placeholder: t("assistant.verbs.panel.assign.filter"), class: "FormControl-input FormControl-small",
                                                     data: { "assistant--verbs-target": "filter", action: "input->assistant--verbs#filter" }),
                   helpers.button_tag(t("assistant.verbs.panel.assign.sort_free"), type: :button, class: "Button Button--invisible Button--small",
                                                                                   "aria-pressed": false,
                                                                                   data: { action: "assistant--verbs#sort", "assistant--verbs-target": "sorter",
                                                                                           alt: t("assistant.verbs.panel.assign.sort_name") })])
      end
    end

    def list
      content_tag(:fieldset, class: "assistant-verbs--choices assistant-verbs--people") do
        safe_join([content_tag(:legend, t("assistant.verbs.panel.assign.legend")),
                   *verbs.people.map { person_choice(it) }])
      end
    end

    def person_choice(entry)
      choice("person_id", entry.user.id, label: entry.user.name, hint: person_hint(entry),
                                         avatar: render(Users::AvatarComponent.new(user: entry.user, size: "mini", show_name: false, link: false,
                                                                                   hover_card: { active: false })),
                                         name: entry.user.name.downcase, free: entry.away_until ? -1 : entry.free_hours)
    end

    def person_hint(entry)
      reading = Assistant::PersonLoad::Reading.new(free_hours: entry.free_hours, away_until: entry.away_until)
      render(Assistant::PersonLoadHintComponent.new(person: entry.user, reading:))
    end

    def remind
      targets = verbs.remind_targets
      form(act_path) do
        safe_join([context_field,
                   content_tag(:p, t("assistant.verbs.panel.remind.help"), class: "assistant-verbs--help"),
                   (target_choices(targets) if targets.size > 1),
                   (helpers.hidden_field_tag(:target_id, targets.first.id, id: nil) if targets.one?),
                   actions(t("assistant.verbs.panel.remind.confirm"))].compact)
      end
    end

    def target_choices(targets)
      choices = targets.each_with_index.map { |person, index| choice("target_id", person.id, label: person.name, checked: index.zero?) }
      content_tag(:fieldset, safe_join([content_tag(:legend, t("assistant.verbs.panel.remind.legend")), *choices]),
                  class: "assistant-verbs--choices")
    end

    def record
      reason = verbs.outcome_reason if outcome_path?
      if reason
        return content_tag(:p, t("assistant.verbs.refused.outcome_#{reason}"), class: "assistant-verbs--help",
                                                                               role: "status")
      end

      form(act_path) do
        safe_join([context_field, (agenda_item_select if outcome_path?), words_field,
                   content_tag(:p, record_help, class: "assistant-verbs--help"), actions(record_label, ready: false)].compact)
      end
    end

    def outcome_path? = intent.kind == "decision" || verbs.place.nil?

    def record_label = t("assistant.verbs.panel.record.#{outcome_path? ? 'outcome' : 'draft'}")

    def record_help = t("assistant.verbs.panel.record.#{outcome_path? ? 'outcome_help' : 'draft_help'}")

    def words_field
      key = intent.kind == "decision" ? "conclusion" : "answer"
      helpers.text_area_tag(:text, params[:text], rows: 3, id: nil, class: "FormControl-textarea",
                                                  "aria-label": t("assistant.verbs.panel.record.#{key}"),
                                                  placeholder: t("assistant.verbs.panel.record.#{key}"),
                                                  data: { "assistant--verbs-target": "words", action: "input->assistant--verbs#chosen" })
    end

    def agenda_item_select
      items = verbs.agenda_items
      return if items.size < 2

      selected = verbs.agenda_item_for(meeting)&.id || items.first.id
      options = helpers.options_for_select(items.map { |item| [item_label(item), item.id] }, selected)
      content_tag(:div, class: "assistant-verbs--where") do
        safe_join([helpers.label_tag(nil, t("assistant.verbs.panel.record.where")),
                   helpers.select_tag(:agenda_item_id, options, id: nil, class: "FormControl-select FormControl-small")])
      end
    end

    def item_label(item)
      (item.work_package ? "##{item.work_package_id} #{item.work_package.subject}" : item.title).to_s.truncate(48)
    end

    def confirmation
      consequences = Assistant::Consequences.new(trial.preview, user:)
      form(act_path) do
        safe_join([context_field, *params.except(:q).map { |key, value| helpers.hidden_field_tag(key, value, id: nil) },
                   helpers.hidden_field_tag(:confirm, "1", id: nil),
                   content_tag(:p, trial.title, class: "assistant-verbs--lead"),
                   content_tag(:p, consequence_text(consequences), class: "assistant-verbs--help",
                                                                   data: { test_selector: "assistant-verb-consequence" }),
                   actions(t("assistant.verbs.panel.confirm"))])
      end
    end

    def consequence_text(consequences)
      parts = [consequences.summary]
      presenter = consequences.presenter
      parts << t("assistant.verbs.panel.affects", names: consequences.affected_names) if presenter.affected_users.any?
      parts.compact_blank.join(t("assistant.card.sentence_separator"))
    end
  end
end
