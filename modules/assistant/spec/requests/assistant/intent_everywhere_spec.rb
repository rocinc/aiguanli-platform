# frozen_string_literal: true

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
require_relative "../../support/intent_helpers"

RSpec.describe "What was said, with its verbs wherever it is shown", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking meetings assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_packages work_package_assigned
                                          add_work_package_comments view_meetings manage_agendas use_assistant])
  end
  shared_let(:no_meetings) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_package_comments use_assistant])
  end
  shared_let(:sam) { create(:user, firstname: "Sam", language: "zh-CN", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", language: "zh-CN", member_with_roles: { project => role }) }
  shared_let(:zoe) { create(:user, firstname: "Zoe", language: "zh-CN", member_with_roles: { project => no_meetings }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Wire up permissions", assigned_to: ben, due_date: Date.new(2026, 10, 16)) }

  let(:now) { Time.zone.local(2026, 10, 12, 10, 30) }
  let(:private_meeting) { create(:meeting, project:, author: sam, title: "Leads only", start_time: now - 3.days, state: :closed) }
  let(:private_item) { create(:meeting_agenda_item, meeting: private_meeting, author: sam, presenter: sam, title: "Plan", notes: "x") }

  before { travel_to(now) }

  after { travel_back }

  def page = Capybara.string(response.body)

  def bar_of(text)
    page.all("li", visible: :all).find { it.text.include?(text) }&.find("[data-test-selector='assistant-intent-verbs']", visible: :all)
  end

  def verbs_in(row) = row.all("[data-verb]", visible: :all).map { it["data-verb"] }

  describe "on the desk, under what we agreed" do
    let!(:owed) { create_intent(project:, subject: work_package, owner: ben, counterparty: sam, work_package:, title: "Regression cases") }
    let!(:mine) do
      create_intent(project:, subject: work_package, owner: sam, counterparty: ben, work_package:, title: "Refund note")
    end
    let!(:asked) do
      create_intent(project:, subject: work_package, owner: sam, counterparty: ben, kind: "question", strength: "requested",
                    title: "Which level wins?", quote: "Which level wins?")
    end

    before do
      login_as(sam)
      get project_assistant_desk_path(project)
    end

    it "gives a promise made to you the reminder first and no handing over, and names who made it" do
      row = bar_of("Regression cases")

      expect(verbs_in(row)).to start_with("remind")
      expect(row).to have_no_css("[data-verb='assign']")
      expect(row).to have_css("[data-test-selector='assistant-say']")
      expect(page).to have_link(ben.name, href: user_path(ben))
    end

    it "gives your own promise the handing over first and no reminder" do
      row = bar_of("Refund note")

      expect(verbs_in(row)).to start_with("assign")
      expect(row).to have_no_css("[data-verb='remind']")
    end

    it "shows the day it was said and the day it was promised for, and counts lateness from the promise" do
      owed.update!(said_due_on: Date.new(2026, 10, 9))
      get project_assistant_desk_path(project)

      text = bar_of("Regression cases").ancestor("li").text
      expect(text).to include(I18n.t("assistant.desk.agreements.spoken", day: Assistant::Text.day(owed.stated_at.to_date), locale: :"zh-CN"))
      expect(text).to include(I18n.t("assistant.desk.agreements.overdue", days: 3, locale: :"zh-CN"))
    end

    it "does not call a promise late for the work package's date alone" do
      work_package.update_columns(due_date: Date.new(2026, 10, 5))
      get project_assistant_desk_path(project)

      text = bar_of("Refund note").ancestor("li").text
      expect(text).to include(I18n.t("assistant.desk.agreements.package_due", day: Assistant::Text.day(Date.new(2026, 10, 5)), locale: :"zh-CN"))
      expect(text).not_to include(I18n.t("assistant.desk.agreements.overdue", days: 7, locale: :"zh-CN"))
    end

    it "lists the questions waiting for your answer for the person asked, with answering first" do
      login_as(ben)
      get project_assistant_desk_path(project)

      expect(page).to have_text(I18n.t("assistant.desk.agreements.questions_for_me", locale: :"zh-CN"))
      row = bar_of("Which level wins?")
      expect(verbs_in(row).first).to eq("answer")
      expect(row).to have_no_css("[data-verb='remind']")
    end
  end

  describe "where the words cannot be opened by the reader" do
    let!(:private_promise) do
      create_intent(project:, subject: work_package, owner: sam, counterparty: zoe, work_package:, source: private_item,
                    title: "Private note", quote: "Only for leads")
    end

    before do
      login_as(zoe)
      get project_assistant_desk_path(project)
    end

    it "shows the line without a name and without a way to talk about it" do
      row = bar_of("Private note")

      expect(page).to have_no_link(sam.name)
      expect(page).to have_text(I18n.t("assistant.desk.agreements.owed_alone", locale: :"zh-CN"))
      expect(row).to have_no_css("[data-test-selector='assistant-say']") if row
    end

    it "does not let the reader talk about it either" do
      expect(Assistant::Conversations::Context.for(private_promise).visible_to?(zoe)).to be(false)
      expect(Assistant::Conversations::Context.for(private_promise).visible_to?(sam)).to be(true)
    end
  end

  describe "on the work package" do
    let!(:decision) do
      create_intent(project:, subject: work_package, owner: ben, work_package:, kind: "decision", status: "active",
                    title: "Two levels of permission", quote: "Two levels, repository and document")
    end
    let!(:promise) { create_intent(project:, subject: work_package, owner: ben, counterparty: sam, work_package:, title: "Regression cases") }

    before do
      create(:meeting, project:, author: sam, title: "Planning", start_time: now + 1.day, state: :open)
      login_as(sam)
    end

    it "gives every decision on the line one verb and the rest behind the menu, with saying something among them" do
      get assistant_work_package_line_path(work_package)

      row = page.find("[data-test-selector='assistant-marks'] .assistant-verbs--compact", visible: :all)
      expect(row.all(".assistant-verbs--bar > [data-verb]", visible: :all).size).to eq(1)
      expect(row).to have_css(".assistant-verbs--menu [data-test-selector='assistant-say']", visible: :all)
      expect(page).to have_link(ben.name, href: user_path(ben), visible: :all)
    end

    it "gives the promise under the date its verbs, compactly, with the reminder first for the one waiting" do
      get assistant_work_package_field_aside_path(work_package, field: "date")

      row = page.find("[data-test-selector='assistant-promise'] .assistant-verbs--compact", visible: :all)
      expect(verbs_in(row).first).to eq("remind")
      expect(page).to have_link(ben.name, href: user_path(ben), visible: :all)
    end

    it "keeps the compact shape when a verb answers in place" do
      post assistant_intent_verb_path(promise, "shelve"), params: { density: "compact" },
                                                         headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body).to include("assistant-verbs--compact")
    end
  end

  describe Assistant::Conversations::IntentContext do
    let!(:promise) do
      create_intent(project:, subject: work_package, owner: ben, counterparty: sam, work_package:, title: "Regression cases",
                    quote: "I will add them by Friday", said_due_expression: "Friday", moves: 2)
    end

    it "tells the assistant the words, the people and the work package as it is now" do
      work_package.update_columns(due_date: Date.new(2026, 10, 23))

      material = described_class.new(promise).material(sam)

      expect(material).to include("I will add them by Friday", "Ben", "Sam", "due 2026-10-23", "moved 2 times", "Friday")
    end

    it "is for those who may open the words and nobody else" do
      expect(described_class.new(promise).visible_to?(sam)).to be(true)
      expect(described_class.new(promise).visible_to?(create(:user))).to be(false)
    end

    it "opens as a conversation about just this one, with its own questions" do
      login_as(sam)

      get assistant_panel_path(context: promise.to_gid.to_s)

      expect(response).to have_http_status(:ok)
      expect(page).to have_text(I18n.t("assistant.thread.chips.intent", locale: :"zh-CN").first)
    end
  end

  describe Assistant::PersonLoadHintComponent, type: :component do
    it "says how much of the week is left, and when someone is away" do
      render_inline(described_class.new(person: ben, today: Date.new(2026, 10, 12)))
      expect(page).to have_css("[data-test-selector='assistant-person-load']")

      create(:user_non_working_time, user: ben, start_date: Date.new(2026, 10, 12), end_date: Date.new(2026, 10, 20))
      render_inline(described_class.new(person: ben, today: Date.new(2026, 10, 12)))
      expect(page).to have_text("10/20")
    end

    it "keeps quiet in a line of text unless it would change what you do" do
      render_inline(described_class.new(person: ben, today: Date.new(2026, 10, 12), always: false,
                                        reading: Assistant::PersonLoad::Reading.new(free_hours: 12, away_until: nil)))
      expect(page).to have_no_css("[data-test-selector='assistant-person-load']")
    end
  end

  describe "what the assistant wrote itself" do
    let(:meeting) { create(:meeting, project:, author: sam, title: "Planning", start_time: now + 1.day, state: :open) }
    let!(:promise) do
      create_intent(project:, subject: work_package, owner: ben, counterparty: sam, work_package:, title: "Regression cases",
                    quote: "I will add them by Friday")
    end

    def schedule!
      verbs = Assistant::IntentVerbs.new(promise, sam, meeting:)
      Assistant::IntentVerbs::Act.new(verbs, "schedule", { meeting_id: meeting.id }, confirm: true).call
      meeting.agenda_items.reload.last
    end

    it "is not read back as something somebody promised" do
      item = schedule!

      expect(item.notes).to include("I will add them by Friday")
      expect(Assistant::Understanding::Extractor.agenda_text(item)).to be_blank
    end

    it "still reads what people add to it" do
      item = schedule!
      item.update!(notes: "#{item.notes}\n\nBen will check the numbers on Monday.")

      text = Assistant::Understanding::Extractor.agenda_text(item)

      expect(text).to include("Ben will check the numbers on Monday.")
      expect(text).not_to include("I will add them by Friday")
    end

    def comment_caused_by(action, notes)
      work_package.add_journal(user: sam, notes:)
      work_package.save!(validate: false)
      work_package.journals.reload.last.tap do
        it.update_columns(cause: { "type" => "assistant_action", "action_id" => action.id })
      end
    end

    it "does not read back a reminder it drafted from a promise, but still reads a comment it carried for someone" do
      from_verb = Assistant::Action.create!(kind: "intent_remind", title: "r", status: "executed", project:, on_behalf_of: sam, tier: "t1",
                                            plan: { "intent" => { "id" => promise.id, "verb" => "remind" } })
      other = Assistant::Action.create!(kind: "comment", title: "c", status: "executed", project:, on_behalf_of: sam, tier: "t1")
      reminder = comment_caused_by(from_verb, "Ben, how is it going?")
      carried = comment_caused_by(other, "I will send the numbers")

      expect(Assistant::Understanding::OwnWords.journal?(reminder)).to be(true)
      expect(Assistant::Understanding::OwnWords.journal?(carried)).to be(false)
    end
  end
end
