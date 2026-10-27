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
  module Actions
    # Takes an action back. Fields someone changed after the action are not
    # overwritten; they are returned as conflicts for a person to decide.
    class Undo
      Result = Data.define(:success, :conflicts, :errors)

      def self.call(...) = new(...).call

      def initialize(action, user:, keep: [])
        @action = action
        @user = user
        @keep = Array(keep)
      end

      def conflicts
        action.inverse.flat_map do |step|
          Steps::Revert.new(step).conflicts.map do |attribute|
            { "gid" => "#{step['type']}/#{step['id']}", "label" => step["label"], "attribute" => attribute }
          end
        end
      end

      def call
        unless action.undoable?
          return Result.new(success: false, conflicts: [],
                            errors: [I18n.t("assistant.actions.errors.not_undoable")])
        end

        found = conflicts
        return Result.new(success: false, conflicts: found, errors: []) if found.any? && keep.empty?

        skip_by_target = found.group_by { it["gid"] }.transform_values { |list| list.pluck("attribute") }
        errors = []
        cause = Journal::CausedByAssistant.new(action)
        ActiveRecord::Base.transaction do
          action.inverse.each do |step|
            step = step.merge("skip" => skip_by_target.fetch("#{step['type']}/#{step['id']}", []))
            outcome = User.execute_as(Assistant.user) { Steps::Revert.new(step).call(user: Assistant.user, cause:) }
            next if outcome.success

            errors.concat(outcome.errors)
            raise ActiveRecord::Rollback
          end
          action.update!(status: "undone", undone_at: Time.current, undone_by: user)
        end

        Result.new(success: errors.empty?, conflicts: found, errors:)
      end

      private

      attr_reader :action, :user, :keep
    end
  end
end
