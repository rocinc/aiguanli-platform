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

require "spec_helper"
require_relative "../../../support/intent_helpers"

RSpec.describe "Signals that belong at the top of the object page", type: :component do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant wiki meetings]) }
  shared_let(:other_project) { create(:project, name: "Scribe", enabled_module_names: %w[work_package_tracking]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant
                                          add_work_package_comments manage_work_package_relations view_wiki_pages
                                          edit_wiki_pages view_meetings])
  end
  shared_let(:lead) do
    create(:user, firstname: "Lea", lastname: "L", member_with_roles: { project => role, other_project => role })
  end
  shared_let(:ben) do
    create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => role, other_project => role })
  end
  shared_let(:viewer) { create(:project_role, permissions: %i[view_work_packages]) }
  shared_let(:quinn) do
    create(:user, firstname: "Quinn", lastname: "Q", member_with_roles: { project => role, other_project => viewer })
  end
  shared_let(:mia) { create(:user, firstname: "Mia", lastname: "M", member_with_roles: { other_project => role }) }
  shared_let(:wiki) { project.wiki || create(:wiki, project:) }

  let(:now) { Time.zone.local(2026, 10, 14, 15) }

  around { |example| travel_to(now) { example.run } }

  before do
    allow(Assistant::Facts).to receive(:working_day?) { |date| !date.saturday? && !date.sunday? }
    allow(Assistant::Proactive::Routing).to receive(:leads).and_return([lead])
    Assistant::Facts.reset!
    Assistant::Membership.ensure_member!(project)
  end

  def sweep(detector)
    engine = Assistant::Proactive::Engine.new(project, now:, today: now.to_date, writer: Assistant::Proactive::Immediate::Plain)
    engine.run(detector, 1.day.ago)
  end

  def line_for(object, user)
    render_inline(Assistant::ObjectLineComponent.new(object:, user:))
    page
  end

  def expect_on_top_of(signal, object, user)
    expect(signal).to have_attributes(channel: "inline", subject: object, recipient: user)
    expect(Assistant::ObjectLineComponent.signals_for(object, user)).to eq([signal])
    expect(line_for(object, user)).to have_test_selector("assistant-object-line")
    expect(page).to have_test_selector("assistant-notice-headline", text: signal.payload["headline"])
  end

  it "puts a colleague elsewhere who did what was asked on top of the page the question was asked on" do
    wp = create(:work_package, project:, subject: "Import", assigned_to: quinn)
    create(:work_package, project: other_project, subject: "扫描件 OCR 识别", assigned_to: mia, status: create(:closed_status))
    create_intent(project:, subject: wp, owner: quinn, kind: "question", status: "open",
                  title: "扫描件 OCR 识别怎么做", quote: "扫描件 OCR 识别怎么做？", stated_at: 5.days.ago)

    signal = sweep(Assistant::Proactive::Detectors::Matchmaker).sole

    expect_on_top_of(signal, wp, quinn)
  end

  it "tells each of two people doing the same thing on their own work package" do
    one = create(:work_package, project:, subject: "导出 PDF 页码", assigned_to: ben)
    other = create(:work_package, project:, subject: "PDF 导出页码", assigned_to: quinn)

    signals = sweep(Assistant::Proactive::Detectors::Overlap)

    expect(signals.size).to eq(2)
    expect_on_top_of(signals.find { it.recipient == ben }, one, ben)
    expect_on_top_of(signals.find { it.recipient == quinn }, other, quinn)
  end

  it "tells the editor of a wiki page that it repeats a replaced decision, on that page" do
    work_package = create(:work_package, project:, assigned_to: lead, subject: "PDF export")
    old = create_intent(project:, subject: work_package, owner: ben, kind: "decision", status: "superseded",
                        title: "Only PDF", quote: "导出只支持 PDF 格式", stated_at: 30.days.ago)
    create_intent(project:, subject: work_package, owner: lead, kind: "decision", status: "active",
                  title: "PDF and CSV", quote: "导出同时支持 PDF 和 CSV", stated_at: 3.days.ago, supersedes: old)
    page_record = create(:wiki_page, wiki:, title: "导出规范", author: ben, text: "## 格式\n导出只支持 PDF 格式。")

    signal = sweep(Assistant::Proactive::Detectors::WikiContradictsDecision).sole

    expect_on_top_of(signal, page_record, ben)
  end

  it "reminds whoever made a thinly based decision on the work package it was made about" do
    wp = create(:work_package, project:, subject: "Search scope", assigned_to: ben)
    create_intent(project:, subject: wp, owner: ben, kind: "decision", status: "active",
                  title: "不做全文检索", quote: "就这么定了，不做全文检索", stated_at: 2.days.ago)

    signal = sweep(Assistant::Proactive::Detectors::WeakDecision).sole

    expect_on_top_of(signal, wp, ben)
  end

  it "puts the missing minutes on top of the meeting page, for its host" do
    meeting = create(:meeting, project:, author: lead, title: "Planning", start_time: now - 5.hours, duration: 1)
    create(:meeting_agenda_item, meeting:, title: "Search scope", notes: "Keep full-text search out of 2.0")

    signal = sweep(Assistant::Proactive::Detectors::MeetingWithoutMinutes).sole

    expect_on_top_of(signal, meeting, lead)
  end

  it "falls back to the meeting for an agenda item and to the project for objects without a page-top line" do
    stray = create(:wiki_page, wiki:, title: "笔记", author: ben, text: "x")
    item = create(:meeting, project:, author: lead, title: "Sync", start_time: now + 1.day)
    agenda_item = create(:meeting_agenda_item, meeting: item, title: "Topic")

    detector = Assistant::Proactive::Detectors::WeakDecision.new(project, today: now.to_date)

    expect(detector.send(:page_top, stray)).to eq(stray)
    expect(detector.send(:page_top, agenda_item)).to eq(item)
    expect(detector.send(:page_top, create(:news, project:))).to eq(project)
  end
end
