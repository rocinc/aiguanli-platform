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

# 04 D3, E1, A4: drafts the assistant wrote are read, changed and put out by a person.
RSpec.describe "Reviewing a draft before it goes out", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant news]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_project manage_news use_assistant])
  end
  shared_let(:lea) { create(:user, member_with_roles: { project => role }) }

  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  before do
    Assistant::Membership.ensure_member!(project)
    login_as(lea)
  end

  def release_notes
    Assistant::Actions::Propose.call(
      kind: "release_notes", title: "Release notes for 2.1", on_behalf_of: lea, project:, subject: project, auto_execute: false,
      steps: [{ "op" => "publish_news",
                "attributes" => { "project_id" => project.id, "title" => "2.1 is out", "summary" => "Page numbers.",
                                  "description" => "## New\n- Page numbers" } }]
    )
  end

  def outside_reminder
    Assistant::Actions::Propose.call(
      kind: "external_notice", title: "Reminder to the outside", on_behalf_of: lea, project:, subject: project, auto_execute: false,
      steps: [{ "op" => "send_mail",
                "attributes" => { "project_id" => project.id, "to" => ["ops@client.example"], "subject" => "2.1 on 11/6",
                                  "body" => "2.1 is planned for 11/6.", "signed_for" => lea.name } }]
    )
  end

  def weekly_status
    Assistant::Actions::Propose.call(
      kind: "weekly_status", title: "Status for this week", on_behalf_of: lea, project:, subject: project, auto_execute: false,
      steps: [{ "op" => "update_project_status", "type" => "Project", "id" => project.id,
                "attributes" => { "status_code" => "at_risk", "status_explanation" => "API is late." } }]
    )
  end

  it "shows the news draft as editable fields with an explicit acknowledgement, since it is public" do
    action = release_notes
    expect(action.tier).to eq("t3")

    get assistant_action_path(action)

    page = Capybara.string(response.body)
    expect(page).to have_test_selector("assistant-draft-form")
    expect(page).to have_field("Title", with: "2.1 is out")
    expect(page).to have_field("News text", with: "## New\n- Page numbers")
    expect(page).to have_css("input[type=checkbox][name=acknowledged][required]")
    expect(page).to have_button("Publish in my name")
  end

  it "does not publish without the acknowledgement" do
    action = release_notes

    post approve_assistant_action_path(action), params: { edits: { "0" => { title: "2.1" } } }, headers: turbo

    expect(response).to have_http_status(:unprocessable_entity)
    expect(News.count).to eq(0)
    expect(action.reload).to be_proposed
  end

  it "publishes the edited words in the name of the person who confirmed" do
    action = release_notes

    post approve_assistant_action_path(action),
         params: { acknowledged: "1", edits: { "0" => { title: "Version 2.1", description: "Page numbers in PDF export." } } },
         headers: turbo

    expect(News.sole).to have_attributes(title: "Version 2.1", description: "Page numbers in PDF export.", author: lea)
    expect(action.reload).to be_executed
  end

  it "saves a draft without going ahead, and keeps who changed it" do
    action = weekly_status

    post revise_assistant_action_path(action),
         params: { edits: { "0" => { status_code: "off_track", status_explanation: "API slipped two weeks." } } },
         headers: turbo

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Draft saved")
    action.reload
    expect(action).to be_proposed
    expect(action.steps.first["attributes"]).to eq("status_code" => "off_track", "status_explanation" => "API slipped two weeks.")
    expect(action.plan["revised_by_id"]).to eq(lea.id)
    expect(project.reload.status_explanation).not_to eq("API slipped two weeks.")
  end

  it "ignores fields a step does not have and status codes the platform does not know" do
    action = weekly_status

    post revise_assistant_action_path(action),
         params: { edits: { "0" => { status_code: "excellent", id: "1", status_explanation: "Fine." } } }, headers: turbo

    expect(action.reload.steps.first).to include("id" => project.id,
                                                 "attributes" => { "status_code" => "at_risk", "status_explanation" => "Fine." })
  end

  it "lets nobody else change the words" do
    action = weekly_status
    reader = create(:project_role, permissions: %i[view_work_packages use_assistant])
    login_as(create(:user, member_with_roles: { project => reader }))

    post revise_assistant_action_path(action), params: { edits: { "0" => { status_explanation: "Hacked." } } }, headers: turbo

    expect(action.reload.steps.first.dig("attributes", "status_explanation")).to eq("API is late.")
  end

  it "shows the outside reminder as a T3 draft signed by the assistant for the one who confirms, with the acknowledgement" do
    action = outside_reminder
    expect(action.tier).to eq("t3")

    get assistant_action_path(action)

    page = Capybara.string(response.body)
    expect(page).to have_field("Mail subject", with: "2.1 on 11/6")
    expect(page).to have_css("input[type=checkbox][name=acknowledged][required]")
  end

  it "sends the outside reminder only after the acknowledgement, with the words as edited" do
    action = outside_reminder
    ActionMailer::Base.deliveries.clear

    post approve_assistant_action_path(action), params: { edits: { "0" => { subject: "2.1 on 11/9" } } }, headers: turbo
    expect(response).to have_http_status(:unprocessable_entity)
    expect(ActionMailer::Base.deliveries).to be_empty

    perform_enqueued_jobs do
      post approve_assistant_action_path(action), params: { acknowledged: "1", edits: { "0" => { subject: "2.1 on 11/9" } } },
                                                  headers: turbo
    end

    mail = ActionMailer::Base.deliveries.sole
    expect(mail).to have_attributes(to: ["ops@client.example"], subject: "2.1 on 11/9")
    expect(mail.text_part.body.to_s).to include("2.1 is planned for 11/6.").and include(lea.name)
  end

  it "keeps what the person changed in the words, so the next draft of its kind can start from there" do
    action = weekly_status
    duty = Assistant::Duty.create!(project:, kind: "weekly_status", delegator: lea)
    action.update!(basis: [Assistant::Basis.for(duty)])

    post approve_assistant_action_path(action), params: { edits: { "0" => { status_explanation: "Fine, nothing late." } } }, headers: turbo

    expect(action.reload.plan["edits"]).to eq([{ "attribute" => "status_explanation", "before" => "API is late.",
                                                  "after" => "Fine, nothing late." }])
    expect(Assistant::Duties::WeeklyStatus.new(duty).send(:earlier_edits))
      .to eq([{ "attribute" => "status_explanation", "before" => "API is late.", "after" => "Fine, nothing late." }])
  end
end
