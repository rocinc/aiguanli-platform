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
    # Progress of an answer over the conversation's own signed stream
    # (`turbo_stream_from conversation`), as one custom Turbo Stream action,
    # `assistant_message`, aimed at `assistant_message_<id>`:
    #   kind="delta"   from/to are codepoint offsets into the answer; the
    #                  template holds exactly that slice
    #   kind="status"  the template holds what it is doing right now
    #   kind="settled" the answer is final; fetch it over HTTP
    # Offsets let the browser drop what it already has after a reconnect and
    # notice a gap it must fill from `GET .../messages/:id.json?offset=`.
    # Whole messages are never broadcast: PostgreSQL NOTIFY carries < 8000 bytes.
    class Stream
      ACTION = "assistant_message"

      def initialize(conversation)
        @conversation = conversation
      end

      def started(message) = signal(message, "status", progress_text(message))

      def delta(message, text, from:)
        signal(message, "delta", text, from:, to: from + text.length)
      end

      def status(message, text) = signal(message, "status", text)

      def finished(message) = signal(message, "settled", "")

      private

      def signal(message, kind, text, **offsets)
        Turbo::StreamsChannel.broadcast_action_to(
          @conversation,
          action: ACTION,
          target: "assistant_message_#{message.id}",
          html: ERB::Util.html_escape(text),
          attributes: { kind:, "message-id": message.id, **offsets }
        )
      rescue StandardError => e
        Rails.logger.warn("[assistant] stream #{kind} #{message.id}: #{e.class} #{e.message}")
      end

      def progress_text(message) = message.progress.presence || I18n.t("assistant.panel.thinking")
    end
  end
end
