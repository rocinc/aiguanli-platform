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
    # What taking an action back would do, worked out the way a preview is:
    # the inverse steps run as the assistant and are rolled back. Fields that
    # someone changed since stay as they are, so the preview leaves them out
    # and names them.
    class UndoPreview
      Result = Data.define(:preview, :removed, :kept) do
        def presenter = Assistant::PreviewPresenter.new(preview)

        def empty? = presenter.empty? && removed.empty?
      end

      def initialize(action, user:)
        @action = action
        @user = user
      end

      def call
        kept = Undo.new(action, user:).conflicts
        skipped = kept.group_by { it["gid"] }.transform_values { |list| list.pluck("attribute") }
        steps = action.inverse.map { it.merge("skip" => skipped.fetch("#{it['type']}/#{it['id']}", [])) }
        Result.new(preview: Preview.new(steps: steps.reject { it["created"] }, user: Assistant.user).call.to_h,
                   removed: steps.select { it["created"] }.pluck("label"), kept:)
      end

      private

      attr_reader :action, :user
    end
  end
end
