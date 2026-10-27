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
  module Reasoning
    # What a turn shows besides its text: the actions it prepared, the facts
    # it computed and the options it laid out. Tools put them under "cards";
    # a message stores them so the panel can render buttons for each action.
    #
    #   { "type" => "action", "action_id" => 12 }
    #   { "type" => "fact", "title" => "...", "rows" => [[label, value, because], ...] }
    #   { "type" => "options", "title" => "...", "items" => [{ "label", "consequence", "action_id" }] }
    module Cards
      module_function

      def from(result)
        return [] unless result.is_a?(Hash)

        Array(result["cards"]).map(&:deep_stringify_keys)
      end

      def action(action) = { "type" => "action", "action_id" => action.id }

      def fact(title, rows) = { "type" => "fact", "title" => title, "rows" => rows }

      def options(title, items) = { "type" => "options", "title" => title, "items" => items }

      # An action that also appears inside an options card is shown once, as
      # part of the options.
      def merge(cards)
        in_options = cards.select { it["type"] == "options" }.flat_map { Array(it["items"]).filter_map { |i| i["action_id"] } }
        cards.reject { it["type"] == "action" && in_options.include?(it["action_id"]) }
             .uniq { [it["type"], it["action_id"], it["title"]] }
      end
    end
  end
end
