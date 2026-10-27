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
require_relative "../../support/intent_helpers"

RSpec.describe Assistant::Onboarding do
  shared_let(:project) do
    create(:project, name: "Billing", description: "Invoices and payments for the shop.",
                     enabled_module_names: %w[work_package_tracking assistant wiki])
  end
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant
                                          view_wiki_pages])
  end
  shared_let(:sam) { create(:user, firstname: "Sam", lastname: "S", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:quinn) { create(:user, firstname: "Quinn", lastname: "Q", member_with_roles: { project => role }) }

  let!(:taken_over) do
    wp = create(:work_package, project:, subject: "Invoice export", assigned_to: ben, due_date: Date.current + 5)
    User.execute_as(sam) { WorkPackages::UpdateService.new(user: sam, model: wp).call(assigned_to_id: quinn.id) }
    wp.reload
  end
  let!(:blocker) { create(:work_package, project:, subject: "Payment API", assigned_to: sam) }
  let!(:relation) { create(:relation, from: blocker, to: taken_over, relation_type: "blocks") }
  let!(:decision) do
    create_intent(project:, subject: taken_over, owner: sam, kind: "decision", status: "active",
                  title: "Export as CSV only", quote: "We export CSV only, PDF later.")
  end
  let!(:page) do
    wiki = project.wiki || create(:wiki, project:)
    create(:wiki_page, wiki:, title: "Invoice export format", text: "How the invoice export is laid out.")
  end

  def onboarding(llm: nil) = described_class.new(user: quinn, project:, llm:)

  def all_items(data) = described_class::LIMITS.keys.flat_map { data[it.to_s] }

  before { allow(Assistant::Llm).to receive(:configured?).and_return(false) }

  it "lists the facts with a link on every line when there is no model" do
    data = onboarding.written

    expect(data["written"]).to be(false)
    expect(data["project"]["facts"]).to include(a_string_including("Invoices and payments"))
    expect(data["work_packages"].map { it["label"] }).to eq(["##{taken_over.id} Invoice export"])
    expect(data["work_packages"].first["facts"]).to include(
      a_string_including("Export as CSV only"), a_string_including("Ben B"), a_string_including("##{blocker.id}")
    )
    expect(data["decisions"].first).to include("label" => "Export as CSV only")
    expect(data["decisions"].first["facts"].first).to include("CSV only, PDF later")
    expect(data["people"].map { it["label"] }).to include("Ben B", "Sam S")
    expect(data["people"].find { it["label"] == "Ben B" }["facts"]).to include(a_string_including("##{taken_over.id}"))
    expect(data["wiki"].map { it["label"] }).to include("Invoice export format")
    expect(all_items(data)).to all(include("url" => a_string_starting_with("/")))
  end

  it "lets one model call word the facts, keeping each link and dropping notes for unknown refs" do
    llm = instance_double(Assistant::Llm)
    allow(Assistant::Llm).to receive(:configured?).and_return(true)
    allow(llm).to receive(:json).and_return(
      "summary" => "Billing builds invoices. The export is next.",
      "notes" => { "wp-#{taken_over.id}" => "Ben started it; it waits on the payment API.", "wp-999999" => "made up" }
    )

    data = onboarding(llm:).written

    expect(llm).to have_received(:json).once
    expect(data["written"]).to be(true)
    expect(data["project"]["summary"]).to eq("Billing builds invoices. The export is next.")
    expect(data["work_packages"].first).to include("note" => "Ben started it; it waits on the payment API.",
                                                   "url" => "/work_packages/#{taken_over.id}")
    expect(all_items(data).map { it["note"] }.compact).not_to include("made up")
  end

  it "falls back to facts when the model fails" do
    llm = instance_double(Assistant::Llm)
    allow(Assistant::Llm).to receive(:configured?).and_return(true)
    allow(llm).to receive(:json).and_raise(Assistant::Llm::Error, "timeout")

    expect(onboarding(llm:).written).to include("written" => false)
  end

  it "writes the page with a link on every list line and a title naming the person" do
    text = onboarding.markdown(onboarding.written)

    expect(onboarding.page_title).to eq("Onboarding: Quinn Q")
    expect(text).to include("[##{taken_over.id} Invoice export](/work_packages/#{taken_over.id})")
    expect(text.lines.grep(/^- /)).to all(include("](/"))
  end
end
