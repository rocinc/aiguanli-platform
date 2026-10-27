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
    # One answer in a conversation: the history and the page the person is on
    # go to the agent; tool calls and results are stored as messages; the
    # answer streams to the panel as it is written and ends with its cards.
    class Turn
      HISTORY = 30

      class Stopped < StandardError; end

      def self.start(conversation, user_message, inline: false)
        placeholder = conversation.messages.create!(role: "assistant", content: "", status: "streaming")
        if inline
          new(conversation:, user_message:, placeholder:).call
        else
          Assistant::TurnJob.perform_later(conversation, user_message)
        end
        placeholder
      end

      def initialize(conversation:, user_message:, placeholder: nil, llm: nil, stream: Stream.new(conversation))
        @conversation = conversation
        @user_message = user_message
        @placeholder = placeholder
        @llm = llm
        @stream = stream
      end

      def call
        message = placeholder || conversation.messages.where(role: "assistant", status: "streaming").last ||
                  conversation.messages.create!(role: "assistant", content: "", status: "streaming")
        stream.started(message)
        title_conversation!

        listener = Listener.new(self, message)
        result = User.execute_as(conversation.user) { agent(listener).run(prompt) }
        listener.flush
        message.update!(content: result.content, cards: result.cards, status: "done", progress: nil, created_at: Time.current)
        stream.finished(message)
        message
      rescue Stopped
        message
      rescue Assistant::Llm::OverBudget
        fail!(message, I18n.t("assistant.reasoning.errors.over_budget"))
      rescue Assistant::Llm::NotConfigured
        fail!(message, I18n.t("assistant.reasoning.errors.not_configured"))
      rescue Assistant::Llm::Error => e
        Rails.logger.error("[assistant] turn #{conversation.id}: #{e.message}")
        fail!(message, I18n.t("assistant.reasoning.errors.unavailable"))
      end

      attr_reader :conversation, :stream

      def stopped?(message) = Assistant::Message.where(id: message.id, status: "stopped").exists?

      # The tool exchanges are stored before the final answer, in order, so a
      # later turn replays them exactly.
      def store_round(_message, assistant)
        conversation.messages.create!(role: "assistant", content: assistant["content"], tool_calls: assistant["tool_calls"],
                                      status: "tool_round")
      end

      def store_tool(call, content)
        conversation.messages.create!(role: "tool", tool_call_id: call.id, content:, status: "done")
      end

      private

      attr_reader :user_message, :placeholder

      def agent(listener)
        Agent.new(user: conversation.user, project: conversation.project, subject: conversation.page_subject,
                  conversation:, llm: @llm, listener:)
      end

      def prompt
        [{ "role" => "system", "content" => system_prompt }] + history
      end

      def history
        rows = conversation.messages.where.not(status: "streaming").where.not(status: "failed")
                           .where.not(role: "system").reorder(:created_at, :id).last(HISTORY)
        rows = rows.drop_while { it.role == "tool" }
        rows.map(&:to_llm).reject { it["role"] == "assistant" && it["content"].blank? && it["tool_calls"].blank? }
      end

      def system_prompt
        [Constitution::TEXT, Situation.new(user: conversation.user, project: conversation.project,
                                           subject: conversation.context).to_s].join("\n\n")
      end

      def title_conversation!
        return if conversation.title.present?

        conversation.update_columns(title: Assistant::Text.plain(user_message.content).truncate(60))
      end

      def fail!(message, text)
        message.update!(content: text, status: "failed", progress: nil)
        stream.finished(message)
        message
      end

      # Every flush is written to the message before it is broadcast, so a
      # browser that missed the socket (or never had one) reads the same text
      # from `messages/:id` and continues from its offset.
      class Listener < Agent::Listener
        FLUSH_EVERY = 0.15

        def initialize(turn, message)
          @turn = turn
          @message = message
          @written = message.content.to_s.dup
          @buffer = +""
          @flushed_at = Time.current
        end

        def delta(text)
          @buffer << text
          return unless Time.current - @flushed_at > FLUSH_EVERY

          raise Stopped if @turn.stopped?(@message)

          flush
        end

        def flush
          return if @buffer.empty?

          from = @written.length
          @written << @buffer
          @message.update_columns(content: @written, updated_at: Time.current)
          @turn.stream.delta(@message, @buffer, from:)
          @buffer = +""
          @flushed_at = Time.current
        end

        def round_finished(assistant)
          flush
          @turn.store_round(@message, assistant)
        end

        def tool_started(call)
          text = I18n.t("assistant.reasoning.progress.#{call.name}", default: I18n.t("assistant.reasoning.progress.default"))
          @message.update_columns(progress: text)
          @turn.stream.status(@message, text)
        end

        def tool_finished(call, content, _cards)
          @turn.store_tool(call, content)
        end
      end
    end
  end
end
