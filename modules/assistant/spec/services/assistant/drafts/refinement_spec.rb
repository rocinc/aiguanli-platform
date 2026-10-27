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
require "rails_helper"

RSpec.describe Assistant::Drafts::Refinement do
  let(:project) { build_stubbed(:project) }
  let(:action) { instance_double(Assistant::Action, project_id: project.id) }
  let(:signer) { build_stubbed(:user, firstname: "Sam", lastname: "Lee") }
  let(:refinement) do
    described_class.new(action:, url: "/assistant/writings", lead: "Comment on #1 Search", signer:, basis: ["Meeting notes"])
  end

  it "knows which attributes are words" do
    words = %w[notes content comments description text summary status_explanation body]
    others = %w[hours status_code title subject]

    expect(words.map { |attribute| described_class.words?(attribute) }).to all(be(true))
    expect(others.map { |attribute| described_class.words?(attribute) }).to all(be(false))
  end

  it "hands the controller the writings path, the project and the sentences it shows" do
    data = refinement.form_data

    expect(data[:controller]).to eq("assistant--draft-refine")
    expect(data[:"assistant--draft-refine-url-value"]).to eq("/assistant/writings")
    expect(JSON.parse(data[:"assistant--draft-refine-scope-value"])).to eq("project_id" => project.id)
    expect(JSON.parse(data[:"assistant--draft-refine-texts-value"]).keys).to match_array(described_class::TEXTS)
  end

  it "tells the rewrite what the draft is for, who signs it and what it rests on" do
    expect(refinement.task("Comment")).to include("Comment on #1 Search").and include("Sam Lee").and include("Comment")
    expect(refinement.material("Hello")).to include("Hello").and include("- Meeting notes")
  end
end
