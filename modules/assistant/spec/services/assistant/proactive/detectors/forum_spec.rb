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
require_relative "../../../../support/intent_helpers"

RSpec.describe Assistant::Proactive::Detectors::UnansweredForumQuestion do
  shared_let(:project) do
    create(:project, enabled_module_names: %w[work_package_tracking assistant forums wiki])
  end
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant
                                          view_messages add_messages view_wiki_pages])
  end
  shared_let(:lea) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:mia) { create(:user, firstname: "Mia", lastname: "M", member_with_roles: { project => role }) }
  shared_let(:fiona) { create(:user, firstname: "Fiona", lastname: "F", member_with_roles: { project => role }) }
  shared_let(:forum) { create(:forum, project:) }

  let(:now) { Time.zone.local(2026, 10, 15, 10) }
  let!(:topic) do
    create(:message, forum:, author: fiona, subject: "OCR 扫描件怎么处理？", content: "扫描件 OCR 识别为空怎么办？")
      .tap { it.update_columns(created_at: now - 4.days) }
  end

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lea])
    Assistant::Membership.ensure_member!(project)
  end

  around { |example| travel_to(now) { example.run } }

  def found = described_class.new(project, today: now.to_date).candidates

  it "asks whoever did the matching work to answer, in the topic" do
    create(:work_package, project:, subject: "扫描件 OCR 识别", assigned_to: mia)

    candidate = found.sole

    expect(candidate.recipient).to eq(mia)
    reply = candidate.options_for(mia).sole[:steps].sole
    expect(reply).to include("op" => "create_forum_reply")
    expect(reply.dig("attributes", "content")).to include("Fiona F", "data-id=\"#{mia.id}\"")
  end

  it "offers to answer with the decision when the team already made one" do
    wp = create(:work_package, project:, subject: "扫描件")
    create_intent(project:, subject: wp, owner: lea, kind: "decision", status: "active",
                  title: "扫描件先走 OCR 识别再解析", quote: "扫描件 OCR 识别为空时先提示，再走 OCR 识别流程", stated_at: 10.days.ago)

    candidate = found.sole

    expect(candidate.nature).to eq(:opportunity)
    expect(candidate.options_for(candidate.recipient).sole[:steps].sole.dig("attributes", "content"))
      .to include("扫描件先走 OCR 识别再解析")
  end

  it "waits until two working days have passed, and once anyone replied" do
    topic.update_columns(created_at: now - 1.day)
    expect(found).to be_empty

    topic.update_columns(created_at: now - 4.days, replies_count: 1)
    expect(found).to be_empty
  end
end
