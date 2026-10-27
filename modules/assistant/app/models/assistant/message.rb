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
  class Message < ApplicationRecord
    belongs_to :conversation, class_name: "Assistant::Conversation", touch: true

    validates :role, inclusion: { in: %w[system user assistant tool] }

    def to_llm
      base = { "role" => role, "content" => content.to_s }
      base["tool_calls"] = tool_calls if role == "assistant" && tool_calls.present?
      base["tool_call_id"] = tool_call_id if role == "tool"
      base
    end

    def streaming? = status == "streaming"

    def settled? = !streaming?

    def actions = Assistant::Action.where(id: Array(cards).filter_map { it["action_id"] })
  end
end
