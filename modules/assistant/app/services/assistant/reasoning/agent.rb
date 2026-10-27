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
    # The tool loop. The model reads, calls fact, preview and action tools,
    # and answers. Rounds and tokens are bounded; long tool results are cut
    # down before they go back to the model, and old ones are cleared once the
    # conversation grows.
    class Agent
      MAX_ROUNDS = 8
      LAST_ROUND = "No more tool calls are possible. Answer now in plain text with what you have found."
      LEAKED_CALLS = /<｜｜DSML｜｜.*\z/m
      MAX_TOKENS = 3000
      BUTTON_PROMISE = /按钮|点(?:击|一下)?\s*(?:下面的)?确认|等你(?:点|确认)|\bbuttons?\b|click (?:to )?confirm/i
      NO_BUTTON = /(?:没有|没|无|不会有|不)\s*(?:任何)?(?:可点的)?按钮|\bno buttons?\b/i

      Result = Data.define(:content, :cards, :rounds, :tool_calls)

      # Receives progress; every method is optional.
      class Listener
        def delta(_text); end

        def round_finished(_assistant_message); end

        def tool_started(_call); end

        def tool_finished(_call, _content, _cards); end
      end

      def initialize(user:, project:, subject: nil, conversation: nil, purpose: "conversation",
                     tools: Tools.all, llm: nil, listener: Listener.new)
        @context = Tools::Context.new(user:, project:, subject:, conversation:)
        @purpose = purpose
        @tools = tools.index_by(&:tool_name)
        @llm = llm
        @listener = listener
      end

      attr_reader :context

      def run(messages)
        messages = messages.map(&:deep_stringify_keys)
        cards = []
        text = +""
        calls = 0
        previewed = nil

        1.upto(MAX_ROUNDS) do |round|
          last = round == MAX_ROUNDS
          sent = last ? Window.fit(messages) + [{ "role" => "system", "content" => LAST_ROUND }] : Window.fit(messages)
          reply = llm.chat(messages: sent, tools: last ? nil : schemas, max_tokens: MAX_TOKENS) do |_kind, delta|
            listener.delta(delta)
          end
          text << reply.content.to_s.sub(LEAKED_CALLS, "")

          if reply.tool_calls.empty? || last
            text, cards = keep_promises(text, cards, previewed)
            return Result.new(content: text.strip, cards: Cards.merge(cards), rounds: round, tool_calls: calls)
          end

          assistant = { "role" => "assistant", "content" => reply.content.to_s,
                        "tool_calls" => reply.tool_calls.map(&:to_message) }
          messages << assistant
          listener.round_finished(assistant)

          reply.tool_calls.each do |call|
            calls += 1
            listener.tool_started(call)
            result = dispatch(call)
            found = Cards.from(result)
            previewed = call.arguments.to_h.stringify_keys["steps"] if previewed_ok?(call, result)
            cards.concat(found)
            content = Window.compress(result)
            messages << { "role" => "tool", "tool_call_id" => call.id, "content" => content }
            listener.tool_finished(call, content, found)
          end
          text << "\n\n" if text.present? && !text.end_with?("\n")
        end
      end

      private

      attr_reader :purpose, :tools, :listener

      def llm = @llm ||= Assistant::Llm.new(purpose:, user: context.user, project: context.project)

      def previewed_ok?(call, result)
        call.name == "preview" && result.is_a?(Hash) && result["success"] && !result["error"]
      end

      # preview only rehearses; the person gets something to press only from
      # propose. When the answer says there is a button and the turn produced
      # none, prepare the last good preview as a held proposal, or say so.
      def keep_promises(text, cards, previewed)
        return [text, cards] unless promises_button?(text) && cards.none? { %w[action options].include?(it["type"]) }

        found = previewed.present? && tools.key?("propose") ? hold(previewed) : []
        return [text, cards + found] if found.any?

        ["#{text.strip}\n\n#{I18n.t('assistant.reasoning.no_buttons')}", cards]
      end

      def promises_button?(text) = text.to_s.gsub(NO_BUTTON, "").match?(BUTTON_PROMISE)

      def hold(steps)
        result = dispatch(Struct.new(:name, :arguments).new(
                            "propose", { "title" => I18n.t("assistant.reasoning.prepared_title"), "kind" => "change",
                                         "steps" => steps, "hold" => true }
                          ))
        result["error"] ? [] : Cards.from(result)
      end

      def schemas = tools.values.map(&:schema)

      def dispatch(call)
        tool = tools[call.name]
        return { "error" => "unknown tool #{call.name}" } unless tool

        User.execute_as(context.user) { tool.new(context).call(call.arguments.to_h.stringify_keys) }
      rescue Tools::Refused => e
        { "error" => e.message }
      rescue ActiveRecord::RecordNotFound
        { "error" => I18n.t("assistant.reasoning.errors.not_found") }
      rescue StandardError => e
        Rails.logger.error("[assistant] tool #{call.name} failed: #{e.class} #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
        { "error" => "#{call.name} failed: #{e.message.truncate(200)}" }
      end
    end
  end
end
