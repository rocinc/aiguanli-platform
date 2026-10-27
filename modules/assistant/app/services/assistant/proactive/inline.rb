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
  module Proactive
    # The side note while someone is changing a date (03 §3.5 channel 2):
    # "this moves #73 and #75 by 5 days, v2.0 slides to 10/9". Previewed as
    # that person, nothing is saved. Returns nil when nothing else moves.
    class Inline
      def initialize(work_package, user:, attributes:)
        @work_package = work_package
        @user = user
        @attributes = attributes.to_h.stringify_keys.slice("start_date", "due_date", "duration", "assigned_to_id", "version_id")
      end

      def call
        return nil if @attributes.empty?

        steps = [{ "op" => "update_work_package", "type" => "WorkPackage", "id" => @work_package.id,
                   "attributes" => @attributes }]
        preview = Assistant::Actions::Preview.new(steps:, user: @user).call
        return { "error" => preview.errors.join("; ") } unless preview.success

        moved = preview.changes.reject { it["id"] == @work_package.id || it["type"] != "WorkPackage" }
        late = preview.version_slips.select { it["late"] && !it["was_late"] }
        return nil if moved.empty? && late.empty?

        { "note" => note(moved, late), "moved" => moved.map do
          { "id" => it["id"], "label" => it["label"], "changes" => it["changes"] }
        end,
          "version_slips" => late, "affected" => User.where(id: preview.affected_user_ids).map(&:name) }
      end

      private

      def note(moved, late)
        parts = []
        if moved.any?
          days = shift_days(moved.first)
          parts << I18n.t("assistant.proactive.inline.moves", list: moved.first(4).map {
            "##{it['id']}"
          }.join("、"), days: days || "?")
        end
        late.each do |slip|
          parts << I18n.t("assistant.proactive.inline.slips", version: slip["name"],
                                                              finish: Assistant::Text.day(Date.iso8601(slip["finish_after"])))
        end
        parts.join(I18n.t("assistant.proactive.inline.separator"))
      end

      def shift_days(change)
        from, to = change.dig("changes", "due_date") || change.dig("changes", "start_date")
        return nil unless from && to

        sign = Date.iso8601(to) >= Date.iso8601(from) ? 1 : -1
        sign * [
          Assistant::Facts.working_days_between([Date.iso8601(from), Date.iso8601(to)].min + 1,
                                                [Date.iso8601(from), Date.iso8601(to)].max), 0
        ].max
      end
    end
  end
end
