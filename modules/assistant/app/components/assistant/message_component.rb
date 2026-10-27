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
  # One line of a conversation. While the answer is being written it shows
  # what the assistant is doing and the text so far; once done, the text and
  # the cards it prepared (actions to decide, facts it computed, ways to go).
  # The ids are the targets `Assistant::Reasoning::Stream` writes to.
  class MessageComponent < ApplicationComponent
    include OpPrimer::ComponentHelpers

    def initialize(message:, user: nil)
      super()
      @message = message
      @user = user || message.conversation.user
    end

    attr_reader :message, :user

    def id = "assistant_message_#{message.id}"

    def content_id = "#{id}_content"

    def status_id = "#{id}_status"

    def mine? = message.role == "user"

    def streaming? = message.status == "streaming"

    def failed? = message.status == "failed"

    def stopped? = message.status == "stopped"

    def progress
      return unless streaming?

      message.progress.presence || t("assistant.panel.thinking")
    end

    def body
      return helpers.simple_format(h(message.content)) if mine?
      return h(message.content) if streaming?

      formatted
    end

    def formatted = Assistant::Linkify.call(message.content, user:, project: message.conversation.project)

    def cards = Array(message.cards).select { it.is_a?(Hash) }

    def actions_by_id
      @actions_by_id ||= Assistant::Action.where(id: cards.flat_map { card_action_ids(it) }).index_by(&:id)
    end

    def card_action_ids(card)
      case card["type"]
      when "action" then [card["action_id"]]
      when "options" then Array(card["items"]).filter_map { it["action_id"] }
      else []
      end.compact.map(&:to_i)
    end

    def action(id) = actions_by_id[id.to_i]

    def sibling_ids(card) = card_action_ids(card)

    def speaker = mine? ? user.name : AssistantUser.instance.name

    def message_url = url_helpers.assistant_conversation_message_path(message.conversation_id, message.id)

    def progress_url = url_helpers.assistant_conversation_message_path(message.conversation_id, message.id, format: :json)

    def stream_data
      return {} unless streaming?

      { controller: "assistant--message-stream",
        assistant__message_stream_url_value: message_url,
        assistant__message_stream_progress_url_value: progress_url,
        assistant__message_stream_signed_stream_value: Turbo::StreamsChannel.signed_stream_name(message.conversation),
        assistant__message_stream_length_value: message.content.to_s.length }
    end
  end
end
