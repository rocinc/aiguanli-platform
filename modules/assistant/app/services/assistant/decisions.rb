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
  # What happens when a person presses a button on a card or a signal. The
  # outcome is written back to every signal that offered the action, so the
  # learning loop sees the answer no matter where it was given.
  class Decisions
    Result = Data.define(:action, :ok, :conflicts, :message, :declined, :undo_preview) do
      def initialize(undo_preview: nil, **rest) = super
    end

    def initialize(action, user:)
      @action = action
      @user = user
    end

    attr_reader :action, :user

    def approve(option: nil, siblings: [])
      return refused unless action.decidable_by?(user)
      return reject(siblings:) if option.present? && choose(option).nil?

      Assistant::Actions::Execute.call(action, decided_by: user)
      action.reload
      declined = decline_siblings(siblings)
      settle(action.executed? ? "adopted" : nil)
      Result.new(action:, ok: action.executed?, conflicts: [], message: action.executed? ? nil : action.error,
                 declined:)
    end

    def reject(siblings: [])
      return refused unless action.decidable_by?(user)

      action.update!(status: "rejected", decided_by: user)
      siblings_rejected = decline_siblings(siblings)
      settle("rejected")
      Result.new(action:, ok: true, conflicts: [], message: nil, declined: siblings_rejected)
    end

    # Past the undo window the person first reads what it would do.
    def undo(keep: false, confirmed: false)
      if action.undoable? && action.undo_needs_preview? && !confirmed
        return Result.new(action:, ok: false, conflicts: [], message: nil, declined: [],
                          undo_preview: Assistant::Actions::UndoPreview.new(action, user:).call)
      end

      undo = Assistant::Actions::Undo.new(action, user:)
      conflicts = undo.conflicts
      return Result.new(action:, ok: false, conflicts:, message: nil, declined: []) if conflicts.any? && !keep

      outcome = Assistant::Actions::Undo.call(action, user:, keep: keep ? conflicts.pluck("attribute") : [])
      action.reload
      settle_undone if outcome.success
      Result.new(action:, ok: outcome.success, conflicts: [], message: outcome.errors.join("; ").presence, declined: [])
    end

    private

    def refused
      Result.new(action:, ok: false, conflicts: [], message: I18n.t("assistant.card.not_yours"), declined: [])
    end

    # Picking a way is choosing its steps; the "leave it" way has none and
    # amounts to declining.
    def choose(key)
      option = action.options.find { _1.is_a?(Hash) && _1["key"].to_s == key.to_s }
      return if option.nil? || Array(option["steps"]).empty?

      steps = Array(option["steps"]).map { _1.to_h.deep_stringify_keys }
      preview = option["preview"].presence ||
                Assistant::Actions::Preview.new(steps:, user: action.on_behalf_of || Assistant.user).call.to_h
      action.update!(plan: action.plan.merge("steps" => steps, "chosen" => key.to_s), preview:)
      option
    end

    def decline_siblings(ids)
      Assistant::Action.proposed.where(id: Array(ids).map(&:to_i) - [action.id]).filter_map do |sibling|
        next unless sibling.decidable_by?(user)

        sibling.update!(status: "rejected", decided_by: user)
        sibling
      end
    end

    def signals
      Assistant::Signal.where(action_id: action.id)
                       .or(Assistant::Signal.where("payload -> 'options' @> ?", [{ action_id: action.id }].to_json))
                       .where(recipient: user, outcome: nil)
    end

    def settle(outcome)
      return if outcome.nil?

      signals.find_each { _1.settle!(outcome) }
    end

    def settle_undone
      Assistant::Signal.offering(action).where(recipient: user, outcome: "adopted")
                       .update_all(outcome: "undone", outcome_at: Time.current)
    end
  end
end
