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

require "net/http"
require "json"

module Assistant
  # OpenAI-compatible chat client with tool calls and streaming, for reading
  # what people write and for reasoning alike. It records every call as usage
  # so that cost is visible.
  class Llm
    class Error < StandardError; end
    class NotConfigured < Error; end
    class OverBudget < Error; end
    class RetryableError < Error; end

    ToolCall = Data.define(:id, :name, :arguments) do
      def to_message
        { "id" => id, "type" => "function", "function" => { "name" => name, "arguments" => JSON.generate(arguments) } }
      end
    end
    Reply = Data.define(:content, :tool_calls, :finish_reason, :usage)

    OPEN_TIMEOUT = 15
    READ_TIMEOUT = 180
    ATTEMPTS = 3

    def self.configured? = Setting.assistant_llm_consent? && base_config.values.all?(&:present?)

    def self.base_config
      {
        base_url: Setting.assistant_llm_base_url.presence ||
          ENV.fetch("ASSISTANT_LLM_BASE_URL", ENV.fetch("DEEPSEEK_BASE_URL", nil)),
        api_key: ENV.fetch("ASSISTANT_LLM_API_KEY", ENV.fetch("DEEPSEEK_API_KEY", nil)),
        model: Setting.assistant_llm_name.presence || ENV.fetch("ASSISTANT_LLM_MODEL", ENV.fetch("DEEPSEEK_MODEL", nil))
      }
    end

    def self.config = base_config.merge(model: Setting.assistant_reasoning_model.presence || base_config[:model])

    def self.key_present? = base_config[:api_key].present?

    def initialize(purpose:, user: nil, project: nil, config: self.class.config)
      raise NotConfigured, "language model is not configured or not consented" unless self.class.configured?
      raise OverBudget, "monthly assistant budget used up" if Assistant::Usage.over_budget?(project:)

      @purpose = purpose
      @user = user
      @project = project
      @endpoint = URI.parse("#{config[:base_url].to_s.chomp('/')}/chat/completions")
      @api_key = config[:api_key]
      @model = config[:model]
    end

    # Yields [:content, text] while streaming when a block is given.
    # Reasoning models think before they answer and the thinking counts
    # against max_tokens, so callers give the length of the answer and the
    # thinking room is added on top.
    REASONING_ALLOWANCE = ENV.fetch("ASSISTANT_LLM_REASONING_TOKENS", "6000").to_i

    def self.budget(answer_tokens) = answer_tokens + REASONING_ALLOWANCE

    def chat(messages:, tools: nil, temperature: 0.2, max_tokens: 4000, json: false, &on_delta)
      reply = chat_once(messages:, tools:, temperature:, max_tokens: self.class.budget(max_tokens), json:, &on_delta)
      return reply unless thought_out?(reply)

      # The thinking used everything up: once more with twice the room.
      Rails.logger.warn("[assistant] #{@purpose} answer cut off while thinking; retrying with more room")
      chat_once(messages:, tools:, temperature:, max_tokens: self.class.budget(max_tokens) * 2, json:, &on_delta)
    end

    def json(system:, user:, max_tokens: 4000)
      reply = chat(messages: [{ role: "system", content: system }, { role: "user", content: user }],
                   temperature: 0, max_tokens:, json: true)
      JSON.parse(reply.content.to_s[/\{.*\}/m] || "{}")
    rescue JSON::ParserError
      {}
    end

    private

    def thought_out?(reply)
      reply.finish_reason == "length" && reply.content.blank? && reply.tool_calls.blank?
    end

    def chat_once(messages:, tools:, temperature:, max_tokens:, json:, &on_delta)
      body = { model: @model, messages:, temperature:, max_tokens: }
      body[:tools] = tools if tools.present?
      body[:response_format] = { type: "json_object" } if json
      body.merge!(stream: true, stream_options: { include_usage: true }) if on_delta

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      reply = with_retries { on_delta ? stream(body, &on_delta) : request(body) }
      track!(reply, started, succeeded: true)
      reply
    rescue Error => e
      track!(nil, started, succeeded: false) if started
      raise e
    end

    def http
      Net::HTTP.new(@endpoint.host, @endpoint.port).tap do |h|
        h.use_ssl = @endpoint.scheme == "https"
        h.open_timeout = OPEN_TIMEOUT
        h.read_timeout = READ_TIMEOUT
      end
    end

    def post_request(body)
      Net::HTTP::Post.new(@endpoint).tap do |r|
        r["Authorization"] = "Bearer #{@api_key}"
        r["Content-Type"] = "application/json"
        r.body = JSON.generate(body)
      end
    end

    def request(body)
      response = http.request(post_request(body))
      check!(response)
      payload = JSON.parse(response.body)
      message = payload.dig("choices", 0, "message") || {}
      Reply.new(content: message["content"], tool_calls: parse_calls(message["tool_calls"]),
                finish_reason: payload.dig("choices", 0, "finish_reason"), usage: payload["usage"] || {})
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError, EOFError => e
      raise RetryableError, e.message
    end

    def stream(body, &)
      content = +""
      calls = {}
      usage = {}
      finish = nil
      buffer = +""
      http.start do |connection|
        connection.request(post_request(body)) do |response|
          check!(response)
          response.read_body do |chunk|
            buffer << chunk
            while (newline = buffer.index("\n"))
              line = buffer.slice!(0, newline + 1).strip
              next unless line.start_with?("data:")

              data = line.delete_prefix("data:").strip
              next if data.empty? || data == "[DONE]"

              event = JSON.parse(data)
              usage = event["usage"] if event["usage"].present?
              choice = event.dig("choices", 0) or next
              finish = choice["finish_reason"] if choice["finish_reason"]
              delta = choice["delta"] || {}
              if (text = delta["content"]).is_a?(String) && !text.empty?
                content << text
                yield(:content, text)
              end
              Array(delta["tool_calls"]).each do |d|
                entry = calls[d["index"] || 0] ||= { "id" => nil, "function" => { "name" => +"", "arguments" => +"" } }
                entry["id"] ||= d["id"]
                entry["function"]["name"] << d.dig("function", "name").to_s
                entry["function"]["arguments"] << d.dig("function", "arguments").to_s
              end
            end
          end
        end
      end
      Reply.new(content:, tool_calls: parse_calls(calls.sort.map(&:last)), finish_reason: finish, usage:)
    rescue Timeout::Error, Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError, OpenSSL::SSL::SSLError, EOFError => e
      raise RetryableError, e.message
    end

    def check!(response)
      status = response.code.to_i
      raise RetryableError, "HTTP #{status}" if status == 429 || status >= 500
      raise Error, "HTTP #{status}: #{response.body.to_s.truncate(300)}" unless status.between?(200, 299)
    end

    def parse_calls(raw)
      Array(raw).each_with_index.map do |call, i|
        args = begin
          JSON.parse(call.dig("function", "arguments").presence || "{}")
        rescue JSON::ParserError
          {}
        end
        ToolCall.new(id: call["id"] || "call_#{i}", name: call.dig("function", "name"), arguments: args)
      end
    end

    def with_retries
      attempt = 0
      begin
        attempt += 1
        yield
      rescue RetryableError
        raise Error, "language model unavailable" if attempt >= ATTEMPTS

        sleep(1.5**attempt)
        retry
      end
    end

    def track!(reply, started, succeeded:)
      usage = reply&.usage || {}
      Assistant::Usage.create!(
        project: @project, user: @user, purpose: @purpose, model: @model, succeeded:,
        prompt_tokens: usage["prompt_tokens"].to_i, completion_tokens: usage["completion_tokens"].to_i,
        tool_calls: reply&.tool_calls&.size.to_i,
        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round,
        created_at: Time.current
      )
    rescue StandardError => e
      Rails.logger.error("[assistant] usage not recorded: #{e.message}")
    end
  end
end
