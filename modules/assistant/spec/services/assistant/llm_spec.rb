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

RSpec.describe Assistant::Llm, :webmock, with_settings: { assistant_llm_consent: true } do
  let(:config) { { base_url: "https://llm.example.com", api_key: "key", model: "m" } }
  let(:sent) { [] }
  let(:allowance) { described_class::REASONING_ALLOWANCE }

  before do
    allow(Assistant::Llm).to receive_messages(base_config: config, config:)
  end

  def answer(*replies)
    stub_request(:post, "https://llm.example.com/chat/completions").to_return do |request|
      sent << JSON.parse(request.body)["max_tokens"]
      content, finish = replies.shift
      { status: 200, body: { choices: [{ message: { content: }, finish_reason: finish }], usage: {} }.to_json }
    end
  end

  it "leaves room to think on top of the answer" do
    answer(['{"ok": true}', "stop"])

    expect(described_class.new(purpose: "spec").json(system: "s", user: "u", max_tokens: 800)).to eq("ok" => true)
    expect(sent).to eq([800 + allowance])
  end

  it "asks once more with twice the room when thinking used it all up" do
    answer(["", "length"], ['{"ok": true}', "stop"])

    expect(described_class.new(purpose: "spec").json(system: "s", user: "u", max_tokens: 800)).to eq("ok" => true)
    expect(sent).to eq([800 + allowance, (800 + allowance) * 2])
  end

  it "streams the words with the spaces and line breaks between them" do
    pieces = ["Ruby", " on", " Rails", " ", "is", " fast", ".", "\n", "\n", "Yes"]
    events = pieces.map { |piece| "data: #{{ choices: [{ delta: { content: piece } }] }.to_json}\n\n" }
    events << "data: #{{ choices: [{ delta: {}, finish_reason: "stop" }], usage: { prompt_tokens: 3 } }.to_json}\n\ndata: [DONE]\n\n"
    stub_request(:post, "https://llm.example.com/chat/completions").to_return(status: 200, body: events.join)
    streamed = []

    reply = described_class.new(purpose: "spec").chat(messages: [{ role: "user", content: "?" }]) do |kind, text|
      streamed << text if kind == :content
    end

    expect(reply.content).to eq("Ruby on Rails is fast.\n\nYes")
    expect(streamed.join).to eq(reply.content)
  end

  it "keeps a cut-off answer that has text in it" do
    answer(["It can, if", "length"])

    reply = described_class.new(purpose: "spec").chat(messages: [{ role: "user", content: "?" }], max_tokens: 50)

    expect(reply.content).to eq("It can, if")
    expect(sent.size).to eq(1)
  end
end
