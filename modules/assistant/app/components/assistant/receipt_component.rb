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
  # What the assistant did, in the voice of a colleague at the next desk: one
  # line with the sentence, on whose behalf and on what basis, when, and the
  # way back. What moved along with it opens below.
  class ReceiptComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    DENSITIES = %i[line full].freeze
    BASIS_LIMIT = 36

    def initialize(action:, user:, density: :line, conflicts: nil, notice: nil)
      super()
      @action = action
      @user = user
      @density = DENSITIES.include?(density&.to_sym) ? density.to_sym : :line
      @conflicts = conflicts
      @notice = notice
    end

    attr_reader :action, :user, :density, :conflicts, :notice

    def self.selector(action, density) = "[data-assistant-action-id='#{action.id}'][data-assistant-density='#{density}']"

    def id = "assistant-receipt-#{action.id}-#{density}"

    def sentence_id = "#{id}-sentence"

    def full? = density == :full

    def open? = full? || conflicts.present? || notice.present?

    delegate :undone?, to: :action

    def preview = @preview ||= PreviewPresenter.new(action.preview)

    def consequences = @consequences ||= Consequences.new(preview, user:)

    def sentence = @sentence ||= Receipts::Sentence.new(action, user:).call

    def sentence_html
      object = if sentence.url && !undone?
                 link_to(sentence.label, sentence.url, data: { turbo_frame: "_top" })
               else
                 ERB::Util.html_escape(sentence.label.to_s)
               end
      with_link(sentence.text, object)
    end

    def when_text = Assistant::Text.stamp(action.executed_at || action.created_at)

    def undone_text
      return t("assistant.receipt.undone") unless action.undone_by && action.undone_at

      t("assistant.receipt.undone_by", name: action.undone_by.name, when: Assistant::Text.stamp(action.undone_at))
    end

    def behalf_text
      return if action.on_behalf_of.nil? || action.on_behalf_of == user

      t("assistant.receipt.for", name: action.on_behalf_of.name)
    end

    def basis = @basis ||= action.basis_entries

    def basis_html
      entry = basis.first or return

      label = (entry.label.presence || t("assistant.card.source")).truncate(BASIS_LIMIT)
      url = basis_url(entry)
      source = url ? link_to(label, url, data: { turbo_frame: "_top" }) : ERB::Util.html_escape(label)
      text = t(basis.one? ? "assistant.receipt.basis" : "assistant.receipt.basis_more", source: Receipts::Sentence::MARK,
                                                                                        count: basis.size)
      with_link(text, source)
    end

    def reason_html = safe_join([behalf_text, basis_html].compact, t("assistant.card.separator"))

    def listed_changes
      direct = preview.direct_changes
      direct.size > 1 || (direct.first && !direct.first.created && direct.first.attributes.size > 1) ? direct : []
    end

    delegate :cascaded_changes, to: :preview

    LABEL_MARK = "\u0000"

    def change_line(change)
      label = change.url ? link_to(change.label, change.url, data: { turbo_frame: "_top" }) : ERB::Util.html_escape(change.label)
      ERB::Util.html_escape(consequences.line(change, label: LABEL_MARK)).to_str.sub(LABEL_MARK) { label.to_s }.html_safe
    end

    def undoable?
      return false unless action.undoable? && user.logged? && !user.is_a?(AssistantUser)
      return false if action.kind == Assistant::Duties::Onboarding::KIND && user.id != action.on_behalf_of_id

      user.id == action.decided_by_id || Assistant::Actions::Authority.new(action, user).may_decide?
    end

    def undo_with_preview? = action.undo_needs_preview?

    def decided_line
      return unless action.executed? || undone?

      action.decided_by ? t("assistant.card.executed_by", name: action.decided_by.name) : t("assistant.card.executed_itself")
    end

    def form_inputs = [{ name: "receipt", value: density.to_s }]

    def undo_path = url_helpers.undo_assistant_action_path(action)

    def show_path = url_helpers.assistant_action_path(action)

    def basis_url(entry) = Assistant::Provenance.url_for_basis(entry.to_h)

    private

    def with_link(text, link) = ERB::Util.html_escape(text).to_str.sub(Receipts::Sentence::MARK) { link.to_s }.html_safe
  end
end
