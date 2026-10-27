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
  # Words written for a person to send (L2): where they land, who signs them,
  # the text itself (editable here), why, and what happens when they go out.
  # Shown as a card only where the target is not on the screen; it becomes a
  # receipt once sent and a quiet line once declined.
  class DraftComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    DENSITIES = %i[card line].freeze
    TEXT_LIMIT = 600

    def initialize(action:, user:, density: :card, notice: nil, heading_level: 3)
      super()
      @action = action
      @user = user
      @density = DENSITIES.include?(density&.to_sym) ? density.to_sym : :card
      @notice = notice
      @heading_level = heading_level.to_i.clamp(2, 6)
    end

    attr_reader :action, :user, :density, :notice

    def self.selector(action, density) = "[data-assistant-draft-id='#{action.id}'][data-assistant-density='#{density}']"

    def id = "assistant-draft-#{action.id}-#{density}"

    def title_id = "#{id}-title"

    def toggle_id = "#{id}-edit"

    def acknowledge_id = "#{id}-acknowledge"

    def heading_tag = :"h#{@heading_level}"

    def line? = density == :line

    def state
      return :open if action.proposed?

      { "executed" => :sent, "undone" => :sent, "failed" => :failed }.fetch(action.status, :declined)
    end

    def mark = render(Primer::Beta::Octicon.new(icon: :"sparkle-fill", size: :small, color: :muted, "aria-hidden": true))

    def targets = @targets ||= action.steps.map { Assistant::Drafts::Target.for(it, user) }

    def lead_html
      step = action.steps.first
      target = targets.first
      link = target ? link_to(target.label, target.url, data: { turbo_frame: "_top" }) : ""
      sentence = t("assistant.draft.leads.#{step['op']}", target: Assistant::Receipts::Sentence::MARK)
      ERB::Util.html_escape(sentence).to_str.sub(Assistant::Receipts::Sentence::MARK) { link.to_s }.html_safe
    end

    def lead_text = ActionController::Base.helpers.strip_tags(lead_html)

    def project_name = action.project&.name

    def signature
      if action.steps.any? { Assistant::Actions::Steps.for(it).in_deciders_name? }
        t("assistant.draft.signature.person")
      else
        behalf = action.on_behalf_of
        return t("assistant.draft.signature.assistant_you") if behalf.nil? || behalf == user

        t("assistant.draft.signature.assistant", name: behalf.name)
      end
    end

    def body
      @body ||= action.steps.flat_map { step_lines(it) }.compact_blank.map { it.to_s.truncate(TEXT_LIMIT) }
    end

    def fields
      action.steps.each_with_index.flat_map do |step, index|
        Assistant::Actions::Revise::FIELDS.fetch(step["op"].to_s, []).map do |attribute|
          { index:, attribute:, op: step["op"].to_s, value: field_value(step, attribute),
            name: "edits[#{index}][#{attribute}]", input_id: "#{id}-#{index}-#{attribute}" }
        end
      end
    end

    def field_label(field)
      fallback = t("assistant.draft.fields.#{field[:attribute]}", default: field[:attribute].humanize)
      t("assistant.draft.fields.#{field[:op]}.#{field[:attribute]}", default: fallback)
    end

    def words?(field) = Assistant::Drafts::Refinement.words?(field[:attribute])

    def rows(field) = %w[description text].include?(field[:attribute]) ? 10 : 6

    def field_value(step, attribute)
      value = step.dig("attributes", attribute).to_s
      Assistant::Drafts::Refinement.words?(attribute) ? Assistant::Mentions.to_text(value) : value
    end

    def refinement
      return @refinement if defined?(@refinement)

      @refinement = if Assistant::Drafts::Refinement.available? && fields.any? { words?(it) }
                      Assistant::Drafts::Refinement.new(action:, url: url_helpers.assistant_writings_path, lead: lead_text,
                                                        signer: (action.on_behalf_of || user), basis: basis.map { basis_label(it) })
                    end
    end

    def form_data
      { turbo_stream: true, test_selector: "assistant-draft-form" }.merge(refinement&.form_data || {})
    end

    def reread = t("assistant.draft_loop.reread")

    def status_options(selected)
      labels = Assistant::DraftFormComponent::STATUS_CODES.map { [I18n.t("activerecord.attributes.project.status_codes.#{it}"), it] }
      helpers.options_for_select(labels, selected)
    end

    def basis = @basis ||= action.basis_entries

    def basis_label(entry) = (entry.label.presence || t("assistant.card.source")).truncate(60)

    def basis_url(entry) = Assistant::Provenance.url_for_basis(entry.to_h)

    def preview = @preview ||= PreviewPresenter.new(action.preview)

    def outcome
      others = (preview.affected_users + preview.notified_users).reject { it == user }
      told = if action.steps.any? { it["op"] == "send_mail" }
               nil
             elsif others.any?
               names = others.map(&:name).to_sentence(two_words_connector: t("assistant.card.and"),
                                                      words_connector: t("assistant.card.separator"),
                                                      last_word_connector: t("assistant.card.and"))
               t("assistant.draft.after.told", names:)
             else
               t("assistant.draft.after.told_nobody")
             end
      [told, *action.steps.map { t("assistant.draft.after.changes.#{it['op']}") }.uniq].compact.join(" ")
    end

    def level_text = t("assistant.draft.after.#{action.tier == 't3' ? 'final' : 'undoable'}")

    def public? = action.tier == "t3"

    def approve_path = url_helpers.approve_assistant_action_path(action)

    def revise_path = url_helpers.revise_assistant_action_path(action)

    def reject_path = url_helpers.reject_assistant_action_path(action)

    def show_path = url_helpers.assistant_action_path(action)

    def declined_text = t("assistant.draft.declined", what: lead_text)

    def failed_text
      t("assistant.draft.failed", what: lead_text, reason: action.error.presence || t("assistant.card.failed_generic"))
    end

    private

    def step_lines(step)
      attrs = step["attributes"].to_h
      case step["op"]
      when "create_time_entry"
        [t("assistant.draft.time_entry", hours: attrs["hours"], date: date(attrs["spent_on"])), plain(attrs["comments"])]
      when "update_project_status"
        [I18n.t("activerecord.attributes.project.status_codes.#{attrs['status_code']}", default: nil),
         plain(attrs["status_explanation"])]
      when "publish_news"
        [attrs["title"], plain(attrs["summary"]), plain(attrs["description"])]
      when "send_mail"
        [attrs["subject"], plain(attrs["body"])]
      else
        key = Assistant::ActionCardComponent::SPOKEN[step["op"].to_s] || Assistant::Actions::Revise::FIELDS[step["op"].to_s]&.first
        [plain(attrs[key])]
      end
    end

    def plain(markup) = markup.present? ? Assistant::Text.plain(markup.to_s) : nil

    def date(raw) = raw.present? ? Assistant::Text.day(Date.iso8601(raw.to_s[0, 10])) : Assistant::Text.day(Date.current)
  end
end
