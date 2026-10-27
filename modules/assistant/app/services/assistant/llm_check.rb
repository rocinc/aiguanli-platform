# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "net/http"
require "json"

module Assistant
  # One tiny real request with the saved configuration, to tell an administrator
  # whether the model can be reached. It is not recorded as usage.
  class LlmCheck
    TIMEOUT = 15

    Result = Data.define(:ok, :model, :seconds, :reason)

    def self.call = new.call

    def call
      models.map { check(it) }
    end

    private

    def config = Assistant::Llm.base_config

    def models = [config[:model], Assistant::Llm.config[:model]].compact_blank.uniq.presence || [nil]

    def check(model)
      reason = missing(model)
      return failure(model, reason) if reason

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = Timeout.timeout(TIMEOUT) { post(model) }
      seconds = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      status = response.code.to_i
      return Result.new(ok: true, model:, seconds:, reason: nil) if status.between?(200, 299)

      failure(model, rejected(status, response.body.to_s, model))
    rescue Timeout::Error, Net::OpenTimeout, Net::ReadTimeout
      failure(model, I18n.t("assistant.admin.test.timeout", seconds: TIMEOUT))
    rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, EOFError => e
      failure(model, I18n.t("assistant.admin.test.unreachable", host: endpoint&.host, detail: e.message.truncate(80)))
    rescue OpenSSL::SSL::SSLError => e
      failure(model, I18n.t("assistant.admin.test.ssl", detail: e.message.truncate(80)))
    rescue URI::InvalidURIError
      failure(model, I18n.t("assistant.admin.test.bad_address"))
    end

    def missing(model)
      return I18n.t("assistant.admin.test.no_address") if config[:base_url].blank?
      return I18n.t("assistant.admin.test.no_key") if config[:api_key].blank?

      I18n.t("assistant.admin.test.no_model") if model.blank?
    end

    def endpoint = @endpoint ||= URI.parse("#{config[:base_url].to_s.chomp('/')}/chat/completions")

    def post(model)
      http = Net::HTTP.new(endpoint.host, endpoint.port)
      http.use_ssl = endpoint.scheme == "https"
      http.open_timeout = TIMEOUT
      http.read_timeout = TIMEOUT
      request = Net::HTTP::Post.new(endpoint)
      request["Authorization"] = "Bearer #{config[:api_key]}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(model:, max_tokens: 8, messages: [{ role: "user", content: "1+1=?" }])
      http.request(request)
    end

    def rejected(status, body, model)
      key = if [401, 403].include?(status) then "denied"
            elsif status == 429 then "limited"
            elsif status >= 500 then "server"
            elsif body.match?(/model/i) && [400, 404].include?(status) then "no_such_model"
            elsif status == 404 then "not_found"
            else "other"
            end
      I18n.t("assistant.admin.test.#{key}", status:, model:, detail: body.truncate(120))
    end

    def failure(model, reason) = Result.new(ok: false, model:, seconds: nil, reason:)
  end
end
