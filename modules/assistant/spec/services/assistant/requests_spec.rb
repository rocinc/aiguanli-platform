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

# 06 S3: a request from the forum to a shipped release.
RSpec.describe Assistant::Requests do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant forums]) }
  shared_let(:lead_role) do
    create(:project_role, permissions: %i[view_work_packages add_work_packages edit_work_packages manage_versions assign_versions
                                          use_assistant view_messages add_messages])
  end
  shared_let(:user_role) { create(:project_role, permissions: %i[view_messages add_messages]) }
  shared_let(:sam) { create(:user, firstname: "Sam", member_with_roles: { project => lead_role }) }
  shared_let(:fiona) { create(:user, firstname: "Fiona", member_with_roles: { project => user_role }) }
  shared_let(:forum) { create(:forum, project:) }
  shared_let(:release) { create(:version, project:, name: "2.1", effective_date: 2.months.from_now.to_date) }
  shared_let(:default_status) { create(:default_status) }
  shared_let(:priority) { create(:default_priority) }
  shared_let(:feature) { create(:type, name: "Feature").tap { create(:project_type, project:, type: it) } }

  let(:llm) { instance_double(Assistant::Llm) }
  let(:topic) { create(:message, forum:, author: fiona, subject: "PDF 页码", content: "导出 PDF 没有页码，打印很麻烦。") }

  before do
    Assistant::Membership.ensure_member!(project)
    allow(Assistant::Llm).to receive(:configured?).and_return(true)
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([sam])
    allow(llm).to receive(:json).and_return(
      "request" => true, "kind" => "feature", "subject" => "导出 PDF 时显示页码",
      "description" => "打印导出的 PDF 时没有页码。", "acceptance" => ["每页底部显示页码", "目录页码与正文一致"]
    )
  end

  def requests = described_class.new(topic, llm:)

  def replies = topic.reload.children.where(author: Assistant.user).pluck(:content)

  it "points to the work already planned, in the topic, and remembers to come back" do
    wp = create(:work_package, project:, subject: "导出 PDF 显示页码", type: feature)
    WorkPackageVersion.create!(work_package: wp, version: release, kind: "target")

    requests.call

    expect(replies).to eq(["这已经是 ##{wp.id}，计划在 2.1。"]).or eq(["This is already ##{wp.id}, planned for 2.1."])
    expect(Assistant::FollowUp.find_by(place: topic)).to have_attributes(work_package: wp, asker: fiona)
  end

  it "drafts a work package for the lead's brief and says in the topic that it waits" do
    action = requests.call

    expect(action).to have_attributes(kind: "request_draft", status: "proposed", on_behalf_of: sam)
    expect(action.steps.first["attributes"]).to include("subject" => "导出 PDF 时显示页码", "type_id" => feature.id,
                                                        "version_id" => release.id)
    expect(action.steps.first["attributes"]["description"]).to include("- [ ] 每页底部显示页码")
    signal = Assistant::Signal.find_by(detector: "forum_request", recipient: sam)
    expect(signal.payload["options"].sole).to include("action_id" => action.id)
    expect(replies.sole).to include("等产品负责人确认").or include("waiting for the product lead")
  end

  it "tells the topic once the lead creates it, when it is done, and when it ships" do
    action = requests.call
    Assistant::Actions::Execute.call(action, decided_by: sam)
    wp = WorkPackage.find_by!(subject: "导出 PDF 时显示页码")

    expect(replies.last).to include("##{wp.id}")
    follow_up = Assistant::FollowUp.find_by!(place: topic, work_package: wp)

    wp.update!(status: create(:closed_status))
    Assistant::Facts.reset!
    Assistant::Requests.follow_up!(wp)
    expect(follow_up.reload.told).to include("done")

    release.update!(status: "closed")
    Assistant::FollowUpJob.perform_now
    expect(follow_up.reload).to have_attributes(state: "released")
    expect(replies.last).to include("2.1")
    expect(replies.size).to eq(4)
  end

  it "does not go back to the topic when the asker muted the follow-up" do
    action = requests.call
    Assistant::Actions::Execute.call(action, decided_by: sam)
    wp = WorkPackage.find_by!(subject: "导出 PDF 时显示页码")
    follow_up = Assistant::FollowUp.find_by!(place: topic, work_package: wp)
    Assistant::Preference.for(fiona).mute!("forum_followup")
    told = replies.size

    wp.update!(status: create(:closed_status))
    Assistant::Facts.reset!
    Assistant::Requests.follow_up!(wp)

    expect(replies.size).to eq(told)
    expect(follow_up.reload.told).not_to include("done")
  end

  it "keeps the lead's brief free of the request once the lead muted it" do
    Assistant::Preference.for(sam).mute!("forum_request")

    requests.call

    expect(Assistant::Signal.where(detector: "forum_request")).to be_empty
  end

  it "says nothing about a topic that asks for nothing" do
    allow(llm).to receive(:json).and_return("request" => false)

    expect(requests.call).to be_nil
    expect(replies).to be_empty
  end
end
