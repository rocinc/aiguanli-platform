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

require "spec_helper"

RSpec.describe "Testing the language model connection", :skip_csrf, :webmock, type: :rails_request do
  let(:config) { { base_url: "https://llm.example.com", api_key: "secret", model: "deepseek-chat" } }
  let(:result) { Capybara.string(response.body).find("[data-test-selector='assistant-llm-test-result']").text }

  before do
    login_as(create(:admin))
    allow(Assistant::Llm).to receive_messages(base_config: config, config:)
  end

  it "says it is connected, with the model and how long it took" do
    stub_request(:post, "https://llm.example.com/chat/completions")
      .to_return(status: 200, body: { choices: [{ message: { content: "2" }, finish_reason: "stop" }] }.to_json)

    expect { post test_connection_admin_settings_assistant_path }.not_to change(Assistant::Usage, :count)

    expect(response).to have_http_status(:ok)
    expect(result).to match(/Connected\. Model: deepseek-chat, took \d+\.\d s\./)
  end

  it "names why it could not connect" do
    stub_request(:post, "https://llm.example.com/chat/completions")
      .to_return(status: 400, body: { error: { message: "Model Not Exist" } }.to_json)

    post test_connection_admin_settings_assistant_path

    expect(result).to include("Not connected: the model “deepseek-chat” does not exist")
  end

  it "says the key is missing without calling out" do
    config[:api_key] = nil

    post test_connection_admin_settings_assistant_path

    expect(result).to include("no API key is set")
    expect(WebMock).not_to have_requested(:post, "https://llm.example.com/chat/completions")
  end

  it "says it timed out" do
    stub_request(:post, "https://llm.example.com/chat/completions").to_timeout

    post test_connection_admin_settings_assistant_path

    expect(result).to include("no answer within 15 seconds")
  end

  it "is for administrators only" do
    login_as(create(:user))
    post test_connection_admin_settings_assistant_path

    expect(response).to have_http_status(:forbidden)
  end
end
