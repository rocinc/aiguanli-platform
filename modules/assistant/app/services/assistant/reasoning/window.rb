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
    # Keeps what goes to the model within bounds. A tool result is cut to a
    # size the model can still read whole; once the conversation as a whole
    # grows past the budget, the oldest tool results are replaced by a stub
    # (the model can call the tool again), and only then old turns are dropped.
    module Window
      module_function

      RESULT_CHARS = 6000
      BUDGET_CHARS = 60_000
      KEEP_RECENT_RESULTS = 4
      CLEARED = "[earlier tool result cleared to save space; call the tool again if you need it]"

      def compress(result)
        payload = result.is_a?(Hash) ? result.except("cards") : result
        text = payload.is_a?(String) ? payload : JSON.generate(payload)
        return text if text.length <= RESULT_CHARS

        shrunk = shrink(payload)
        text = JSON.generate(shrunk)
        text.length <= RESULT_CHARS ? text : "#{text[0, RESULT_CHARS]}… [truncated]"
      end

      def fit(messages)
        return messages if size(messages) <= BUDGET_CHARS

        fitted = clear_old_results(messages)
        drop_old_turns(fitted)
      end

      def size(messages) = messages.sum { it["content"].to_s.length + it["tool_calls"].to_s.length }

      def shrink(value, depth = 0)
        case value
        when Array
          kept = value.first(depth.zero? ? 25 : 10).map { shrink(it, depth + 1) }
          kept << "… #{value.size - kept.size} more" if value.size > kept.size
          kept
        when Hash then value.transform_values { shrink(it, depth + 1) }
        when String then value.truncate(depth.zero? ? 2000 : 400)
        else value
        end
      end

      def clear_old_results(messages)
        tool_indexes = messages.each_index.select { messages[it]["role"] == "tool" }
        stale = tool_indexes[0...-KEEP_RECENT_RESULTS] || []
        messages.each_with_index.map do |message, index|
          stale.include?(index) ? message.merge("content" => CLEARED) : message
        end
      end

      # The system prompt and the latest user turn always stay; what goes is
      # whole exchanges from the front, so that no tool result is left without
      # the call that asked for it.
      def drop_old_turns(messages)
        system, rest = messages.partition { it["role"] == "system" }
        while size(system + rest) > BUDGET_CHARS && rest.count { it["role"] == "user" } > 1
          rest = rest.drop(1)
          rest = rest.drop(1) until rest.empty? || rest.first["role"] == "user"
        end
        system + rest
      end
    end
  end
end
