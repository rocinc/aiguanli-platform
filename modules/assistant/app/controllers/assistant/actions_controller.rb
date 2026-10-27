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
  # The landing page of "what and why" links in the activity, and the target
  # of every button on an action card. Buttons answer with Turbo Streams that
  # replace every copy of the card on the page.
  class ActionsController < ApplicationController
    include OpTurbo::ComponentStream

    before_action :find_action
    before_action :authorize_view
    authorization_checked! :show, :approve, :reject, :undo, :revise, :handover

    layout -> { @project ? "base" : "global" }

    menu_item :assistant

    def show
      respond_to do |format|
        format.html { render :show }
        format.turbo_stream { render turbo_stream: card_streams }
      end
    end

    def approve
      return respond_with(unacknowledged) if @action.tier == "t3" && params[:acknowledged] != "1"
      return respond_with(revision_failed) unless edits_applied?

      respond_with(decisions.approve(option: params[:option].presence, siblings: siblings))
    end

    # Keeps the edited draft without going ahead.
    def revise
      unless @action.decidable_by?(current_user)
        return respond_with(Assistant::Decisions::Result.new(action: @action, ok: false, conflicts: [], declined: [],
                                                             message: t("assistant.card.not_yours")))
      end
      return respond_with(revision_failed) unless edits_applied?

      respond_with(Assistant::Decisions::Result.new(action: @action, ok: true, conflicts: [], declined: [],
                                                    message: t("assistant.draft.saved")))
    end

    def reject
      respond_with(decisions.reject(siblings:))
    end

    def undo
      result = decisions.undo(keep: params[:keep].present?, confirmed: params[:confirm].present?)
      @handover_ask = result.ok && Assistant::Notice::Handover.new(result.action, current_user).ask!
      respond_with(result)
    end

    # The answer to "should I ask you first from now on?" after an undo.
    def handover
      return head(:forbidden) unless @action.undone? && @action.visible_to?(current_user)

      sentence = Assistant::Notice::Handover.new(@action, current_user).answer(params[:answer] == "yes")
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(Assistant::HandoverAskComponent.dom_id(@action),
                                                    Assistant::HandoverAskComponent.new(action: @action, sentence:))
        end
        format.html { redirect_to assistant_action_path(@action) }
      end
    end

    private

    def find_action
      @action = Assistant::Action.includes(:on_behalf_of, :decided_by, :undone_by, :project).find(params.expect(:id))
      @project = @action.project
    end

    def authorize_view
      deny_access(not_found: true) unless User.current.logged? && @action.visible_to?(User.current)
    end

    def decisions = Assistant::Decisions.new(@action, user: current_user)

    def siblings = Array(params[:siblings]).compact_blank

    def edits_applied?
      return true if params[:edits].blank? || !@action.decidable_by?(current_user)

      edits = params.require(:edits).permit!.to_h
      @revision_errors = Assistant::Actions::Revise.call(@action, user: current_user, edits:).errors.full_messages
      @revision_errors.empty?
    end

    def revision_failed
      Assistant::Decisions::Result.new(action: @action.reload, ok: false, conflicts: [], declined: [],
                                       message: @revision_errors.to_sentence.presence || t("assistant.card.failed_generic"))
    end

    def unacknowledged
      Assistant::Decisions::Result.new(action: @action, ok: false, conflicts: [], declined: [],
                                       message: t("assistant.draft.acknowledge_missing"))
    end

    def respond_with(result)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: card_streams(result), status: result.ok || result.conflicts.any? || result.undo_preview ? :ok : :unprocessable_entity
        end
        format.html do
          flash[:error] = result.message if result.message
          redirect_to assistant_action_path(@action)
        end
      end
    end

    def card_streams(result = nil)
      action = result&.action || @action
      streams = replace_cards(action, conflicts: result&.conflicts.presence, notice: result&.message, undo_preview: result&.undo_preview)
      Array(result&.declined).each { streams.concat(replace_cards(it)) }
      streams.concat(replace_notices(action, *Array(result.declined))) if result
      streams << handover_ask(action) if @handover_ask
      streams << live_region(result) if result
      streams
    end

    # The clicked copy gets the conflicts and the notice; copies of the other
    # variant elsewhere on the page are simply brought up to date.
    def replace_cards(action, conflicts: nil, notice: nil, undo_preview: nil)
      clicked = Assistant::ActionCardComponent::VARIANTS.include?(params[:variant]&.to_sym) ? params.expect(:variant).to_sym : :full
      clicked = nil if params[:receipt].present?
      cards = Assistant::ActionCardComponent::VARIANTS.map do |variant|
        here = variant == clicked
        card = Assistant::ActionCardComponent.new(action:, user: current_user, variant:, siblings:,
                                                  conflicts: (conflicts if here), notice: (notice if here),
                                                  undo_preview: (undo_preview if here), heading_level: params[:heading_level] || 3)
        turbo_stream.replace_all(Assistant::ActionCardComponent.selector(action, variant), card)
      end
      cards + replace_drafts(action, notice:) + replace_receipts(action, conflicts:, notice:)
    end

    def replace_drafts(action, notice:)
      return [] unless action.steps.any? && action.steps.all? { Assistant::Drafts::WORD_OPS.include?(it["op"].to_s) }

      Assistant::DraftComponent::DENSITIES.map do |density|
        draft = Assistant::DraftComponent.new(action:, user: current_user, density:, notice: (notice if density == :card))
        turbo_stream.replace_all(Assistant::DraftComponent.selector(action, density), draft)
      end
    end

    def replace_notices(*actions)
      signals = actions.flat_map { Assistant::Signal.offering(it).where(recipient: current_user).to_a }.uniq
      signals.flat_map do |signal|
        Assistant::NoticeComponent::DENSITIES.map do |density|
          notice = Assistant::NoticeComponent.new(signal:, user: current_user, density:)
          turbo_stream.replace_all(Assistant::NoticeComponent.selector(signal, density), notice)
        end
      end
    end

    def handover_ask(action)
      selector = if params[:receipt].present?
                   Assistant::ReceiptComponent.selector(action, params[:receipt])
                 else
                   Assistant::ActionCardComponent.selector(action, params[:variant].presence || :full)
                 end
      turbo_stream.after_all(selector, Assistant::HandoverAskComponent.new(action:))
    end

    def replace_receipts(action, conflicts:, notice:)
      Assistant::ReceiptComponent::DENSITIES.map do |density|
        here = params[:receipt].to_s == density.to_s
        receipt = Assistant::ReceiptComponent.new(action:, user: current_user, density:,
                                                  conflicts: (conflicts if here), notice: (notice if here))
        turbo_stream.replace_all(Assistant::ReceiptComponent.selector(action, density), receipt)
      end
    end

    def live_region(result)
      message = if result.conflicts.any? then t("assistant.card.announce.conflicts")
                elsif !result.ok then result.message || t("assistant.card.failed_generic")
                elsif result.message && result.action.proposed? then result.message
                else t("assistant.card.announce.#{result.action.status}", title: result.action.title)
                end
      OpTurbo::StreamComponent.new(action: :liveRegion, message:, politeness: "polite", delay: nil, target: nil)
                              .render_in(view_context)
    end
  end
end
