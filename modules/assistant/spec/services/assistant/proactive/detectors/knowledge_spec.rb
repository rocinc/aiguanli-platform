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

# 03 §6.6 and 04 D4: what the team already knows is written down once.
RSpec.describe "Knowledge detectors" do # rubocop:disable RSpec/DescribeClass
  shared_let(:project) do
    create(:project, enabled_module_names: %w[work_package_tracking assistant wiki])
  end
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant
                                          view_wiki_pages edit_wiki_pages])
  end
  shared_let(:lea) { create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role }) }
  shared_let(:mia) { create(:user, firstname: "Mia", lastname: "M", member_with_roles: { project => role }) }
  shared_let(:wiki) { project.wiki || create(:wiki, project:) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: lea, subject: "PDF export") }

  let(:today) { Date.current }

  before do
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lea])
    Assistant::Membership.ensure_member!(project)
  end

  def candidates(detector) = detector.new(project, today:).candidates

  def ask(owner, title, quote, days_ago:)
    create_intent(project:, subject: work_package, owner:, kind: "question", status: "answered",
                  title:, quote:, stated_at: days_ago.days.ago)
  end

  def answer(question, by:, text:)
    work_package.add_journal(user: by, notes: text)
    work_package.save!(validate: false)
    question.update!(answered_by: work_package.journals.reload.last)
  end

  describe Assistant::Proactive::Detectors::RepeatedQuestion do
    before do
      q1 = ask(ben, "扫描件为什么解析为空", "扫描件为什么解析为空？", days_ago: 40)
      ask(lea, "扫描件解析为空怎么办", "扫描件解析为空怎么办？", days_ago: 20)
      ask(ben, "为什么扫描件解析结果为空", "为什么扫描件解析结果为空", days_ago: 2)
      answer(q1, by: mia, text: "扫描件没有文本层，要先走 OCR。")
    end

    it "offers whoever answered a FAQ entry quoting the answers, on the third time" do
      found = candidates(described_class).sole

      expect(found).to have_attributes(recipient: mia, nature: :opportunity, channel: "brief")
      step = found.options_for(mia).sole[:steps].sole
      expect(step["op"]).to eq("create_wiki_page")
      expect(step["attributes"]["text"]).to include("扫描件没有文本层，要先走 OCR。", "Mia M")
    end

    it "stays quiet once the FAQ answers it" do
      create(:wiki_page, wiki:, title: I18n.t("assistant.proactive.repeated_question.page_title"),
                         text: "## 扫描件为什么解析为空\n先走 OCR。")

      expect(candidates(described_class)).to be_empty
    end
  end

  describe Assistant::Proactive::Detectors::ThreadSettled do
    before do
      stub_const("#{described_class}::MIN_COMMENTS", 3)
      [ben, mia, lea].each do |user|
        work_package.add_journal(user:, notes: "comment by #{user.firstname}")
        work_package.save!(validate: false)
      end
      create_intent(project:, subject: work_package, owner: lea, kind: "decision", status: "active",
                    title: "Export as CSV only", quote: "CSV only, PDF later", stated_at: 10.days.ago)
      work_package.journals.update_all(created_at: 10.days.ago)
    end

    it "drafts the conclusion into the description, from the recorded decisions" do
      found = candidates(described_class).sole

      expect(found).to have_attributes(recipient: lea, subject: work_package)
      description = found.options_for(lea).sole[:steps].sole.dig("attributes", "description")
      expect(description).to include("Export as CSV only", "CSV only, PDF later")
    end
  end

  describe Assistant::Proactive::Detectors::WikiContradictsDecision do
    let!(:old) do
      create_intent(project:, subject: work_package, owner: ben, kind: "decision", status: "superseded",
                    title: "Only PDF", quote: "导出只支持 PDF 格式", stated_at: 30.days.ago)
    end

    before do
      create_intent(project:, subject: work_package, owner: lea, kind: "decision", status: "active",
                    title: "PDF and CSV", quote: "导出同时支持 PDF 和 CSV", stated_at: 3.days.ago, supersedes: old)
      create(:wiki_page, wiki:, title: "导出规范", author: ben, text: "## 格式\n导出只支持 PDF 格式。")
    end

    it "asks the page's editor to mark the replaced passage, deleting nothing" do
      found = candidates(described_class).sole

      expect(found).to have_attributes(recipient: ben, subject: WikiPage.find_by(title: "导出规范"), channel: "inline")
      text = found.options_for(ben).sole[:steps].sole.dig("attributes", "text")
      expect(text).to start_with("## 格式\n导出只支持 PDF 格式。")
      expect(text).to include("导出同时支持 PDF 和 CSV")
    end
  end

  describe Assistant::Proactive::Detectors::WikiStale do
    it "tells the page's editor which work the page names has closed or moved since it was written" do
      closed = create(:closed_status)
      done = create(:work_package, project:, subject: "Old export")
      page = create(:wiki_page, wiki: wiki, title: "Export spec", text: "We do ##{done.id} first.", author: lea)
      WikiPage.where(id: page.id).update_all(updated_at: 40.days.ago)
      done.update_columns(status_id: closed.id, updated_at: 1.day.ago)

      found = described_class.new(project).candidates.sole

      expect(found).to have_attributes(recipient: lea, subject: page)
      expect(found.because.first).to include("##{done.id}", "Old export")
    end
  end
end
