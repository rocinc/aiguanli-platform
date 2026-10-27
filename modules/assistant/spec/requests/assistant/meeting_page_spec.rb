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

RSpec.describe "What a meeting opens with and what it leaves behind", type: :rails_request do
  shared_let(:type) { create(:type) }
  shared_let(:project) do
    create(:project, types: [type], enabled_module_names: %w[work_package_tracking meetings assistant wiki])
  end
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_packages work_package_assigned
                                          view_meetings edit_meetings manage_agendas use_assistant
                                          view_wiki_pages edit_wiki_pages manage_outcomes])
  end
  shared_let(:host) { create(:user, firstname: "Sam", member_with_roles: { project => role }) }
  shared_let(:ada) { create(:user, firstname: "Ada", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", member_with_roles: { project => role }) }

  let(:now) { Time.zone.local(2026, 10, 16, 15, 30) }
  let(:previous) { create(:meeting, project:, author: host, title: "Sprint 6 review", start_time: now - 3.days, state: :closed) }
  let(:upcoming) { create(:meeting, project:, author: host, title: "Sprint 7 planning", start_time: now + 1.day) }
  let(:previous_item) { create(:meeting_agenda_item, meeting: previous, author: host, presenter: ada, title: "Testing earlier") }

  before do
    travel_to(now)
    [host, ada, ben].each do |user|
      create(:meeting_participant, meeting: upcoming, user:, invited: true)
      create(:meeting_participant, meeting: previous, user:, invited: true, attended: true)
    end
    project.wiki || create(:wiki, project:)
    create(:default_status)
    create(:default_priority)
  end

  after { travel_back }

  def said(**attributes)
    create_intent(project:, subject: previous, owner: nil, source: previous_item, **attributes)
  end

  describe Assistant::MeetingRecap do
    subject(:recap) { described_class.new(upcoming, host) }

    it "lists what last time left open as things, with their state, and no one by name" do
      said(title: "Testing joins earlier", status: "open")
      said(title: "Write the export note", owner: ben)
      lines = recap.sections[:last_time].map(&:line)

      expect(lines).to eq([I18n.t("assistant.meeting_recap.said", title: "Testing joins earlier",
                                                                  state: I18n.t("assistant.meeting_recap.unclaimed")),
                           I18n.t("assistant.meeting_recap.said", title: "Write the export note",
                                                                  state: I18n.t("assistant.meeting_recap.open"))])
      expect(lines.join).not_to include("Ben")
    end

    it "skips what is carried out, and says so when that is everything" do
      done = create(:work_package, project:, status: create(:closed_status))
      said(title: "Fix it", work_package: done)

      expect(recap.entries).to be_empty
      expect(recap.landed).to eq(1)
    end

    it "keeps to five lines and leaves out what the agenda already covers" do
      %w[Alpha Bravo Charlie Delta Echo Foxtrot Golf].each { said(title: "#{it} release notes to settle") }
      create(:meeting_agenda_item, meeting: upcoming, author: host, title: "Alpha release notes to settle")

      expect(recap.entries.size).to eq(3)
      expect(recap.entries.map(&:title)).not_to include("Alpha release notes to settle")
    end

    it "addresses the reader only when the matter is theirs" do
      said(title: "Send the draft", owner: host)

      expect(described_class.new(upcoming, host).entries.sole.line).to include(I18n.t("assistant.meeting_recap.yours"))
      expect(described_class.new(upcoming, host, shared: true).entries.sole.line).not_to include(I18n.t("assistant.meeting_recap.yours"))
    end
  end

  describe "the meeting page" do
    it "keeps what the host was notified about waiting at the top, and not in the brief as well" do
      signal = Assistant::Signal.create!(detector: "meeting_prep", fingerprint: "prep", recipient: host, project:, subject: upcoming,
                                         channel: "notification", state: "delivered", delivered_at: Time.current,
                                         deliver_at: Time.current, payload: { "headline" => "Sprint 7 planning 缺一份议程" })
      login_as(host)

      get project_meeting_path(project, upcoming)

      line = response.parsed_body.at_css("[data-test-selector='assistant-object-line']")
      expect(line.at_css(".assistant-notice--headline").text).to eq(signal.headline)
      expect(Assistant::Brief.new(user: host).decisions).to be_empty
    end

    it "opens with the recap, once, for anyone who may see the meeting" do
      said(title: "Testing joins earlier")
      login_as(ada)
      get project_meeting_path(project, upcoming)

      recap = Nokogiri::HTML(response.body).css("[data-test-selector='assistant-meeting-recap']")
      expect(recap.size).to eq(1)
      expect(recap.text).to include("Testing joins earlier")
    end

    it "shows no recap on a meeting that is over" do
      said(title: "Testing joins earlier")
      upcoming.update_columns(state: Meeting.states[:closed])
      login_as(ada)
      get project_meeting_path(project, upcoming)

      expect(response.body).not_to include("assistant-meeting-recap")
    end

    it "shows the host the minutes drafted for them, and no one else" do
      draft = Assistant::Duties::MeetingFollowup.minutes_step(previous, "## Minutes", user: host)
      create(:meeting_agenda_item, meeting: previous, author: host)
      Assistant::Actions::Propose.call(kind: "meeting_minutes", subject: previous, project:, on_behalf_of: host, auto_execute: false,
                                       title: "Minutes", steps: [draft], basis: [Assistant::Basis.for(previous)])

      login_as(host)
      get project_meeting_path(project, previous)
      expect(response.body).to include("assistant-meeting-minutes")

      login_as(ada)
      get project_meeting_path(project, previous)
      expect(response.body).not_to include("assistant-meeting-minutes")
    end
  end

  describe Assistant::Understanding::UnownedItems do
    let(:item) { said(title: "Testing joins earlier", quote: "testing joins earlier") }

    it "tells the host under the item, leaving the choices to the verbs of the promise" do
      described_class.offer(previous_item, [item])

      signal = Assistant::Signal.find_by!(detector: "meeting_unowned", channel: "inline")
      expect(signal).to have_attributes(recipient: host, action_id: nil)
      expect(signal.payload["options"]).to be_empty
      expect(signal.payload["intent_id"]).to eq(item.id)
    end

    it "offers the brief two people for a promise nobody took, and records the owner once taken" do
      described_class.offer(previous_item, [item])

      signal = Assistant::Signal.find_by!(detector: "meeting_unowned", channel: "brief")
      expect(signal).to have_attributes(recipient: host)
      expect(signal.payload["options"].size).to eq(2)
      expect(signal.payload["options"].first["label"]).to eq(I18n.t("assistant.meeting_recap.unowned.option", name: ada.name))

      action = Assistant::Action.find(signal.payload["options"].first["action_id"])
      Assistant::Actions::Execute.call(action, decided_by: host)

      expect(item.reload).to have_attributes(owner: ada)
      expect(item.work_package).to be_present
    end

    it "does not offer someone who is on leave for the whole stretch ahead" do
      UserNonWorkingTime.create!(user: ada, start_date: Date.current - 1, end_date: Date.current + 40)
      described_class.offer(previous_item, [item])

      signal = Assistant::Signal.find_by!(detector: "meeting_unowned", channel: "brief")
      labels = signal.payload["options"].map { it["label"] }
      expect(labels).not_to include(I18n.t("assistant.meeting_recap.unowned.option", name: ada.name))
      expect(labels.size).to eq(2)
    end

    it "retires what was offered once the promise is handed to someone by its verbs" do
      described_class.offer(previous_item, [item])
      offered = Assistant::Action.proposed.where(kind: "meeting_action_item").to_a

      item.update!(owner: ada)
      Assistant::IntentVerbs::Effects.apply(item, Assistant::Action.create!(
        kind: "intent_assign", title: "x", status: "executed", project:, on_behalf_of: host, tier: "t1",
        plan: { "intent" => { "id" => item.id, "verb" => "assign", "effects" => { "owner_id" => ada.id } } }
      ))

      expect(Assistant::Signal.live.where(detector: "meeting_unowned")).to be_none
      expect(offered.map { it.reload.status }.uniq).to eq(["superseded"])
    end

    it "says nothing about a promise that has an owner" do
      described_class.offer(previous_item, [said(title: "Owned", owner: ben)])

      expect(Assistant::Signal.where(detector: "meeting_unowned")).to be_none
    end
  end

  describe Assistant::Understanding::ChecklistItems do
    it "offers to turn a list of causes on the agenda into work packages, none assigned" do
      notes = "Why it could fail:\n\n- [ ] Scans parse empty\n- [ ] Permission edges\n- [ ] Billing basis"
      put = Assistant::Actions::Propose.call(
        kind: "pre_mortem", title: "Pre-mortem", subject: upcoming, project:, on_behalf_of: host, auto_execute: false,
        steps: [{ "op" => "create_meeting_agenda_item",
                  "attributes" => { "meeting_id" => upcoming.id, "title" => "Pre-mortem", "notes" => notes } }]
      )
      raise "propose: #{put.status} #{put.error}" unless put.status == "proposed"

      Assistant::Actions::Execute.call(put, decided_by: host)
      raise "exec: #{put.reload.status} #{put.error} #{put.inverse}" unless put.executed?

      signal = Assistant::Signal.find_by!(detector: "meeting_checklist")
      action = Assistant::Action.find(signal.payload["options"].sole["action_id"])
      expect(action.steps.map { it.dig("attributes", "subject") }).to eq(["Scans parse empty", "Permission edges", "Billing basis"])
      expect(action.steps.filter_map { it.dig("attributes", "assigned_to_id") }).to be_empty
    end
  end

  describe Assistant::Understanding::ChecklistItems, "on the assistant's own fact lines" do
    def execute_notes(notes)
      put = Assistant::Actions::Propose.call(
        kind: "pre_mortem", title: "Pre-mortem", subject: upcoming, project:, on_behalf_of: host, auto_execute: false,
        steps: [{ "op" => "create_meeting_agenda_item",
                  "attributes" => { "meeting_id" => upcoming.id, "title" => "Pre-mortem", "notes" => notes } }]
      )
      Assistant::Actions::Execute.call(put, decided_by: host)
      put
    end

    it "does not offer to turn plain fact lines, or checkbox lines that restate a work package, into work packages" do
      execute_notes("Intro\n\n- Already past their date: #73, #100\n- [ ] Nobody on: #101, #105\n- Billing basis is thin")

      expect(Assistant::Signal.where(detector: "meeting_checklist")).to be_none
    end

    it "still offers the checkbox lines that name no work package" do
      execute_notes("- Already past their date: #73\n- [ ] Decide who owns billing")

      signal = Assistant::Signal.find_by!(detector: "meeting_checklist")
      action = Assistant::Action.find(signal.payload["options"].sole["action_id"])
      expect(action.steps.map { it.dig("attributes", "subject") }).to eq(["Decide who owns billing"])
    end
  end

  describe "while the meeting runs" do
    let(:running) { create(:meeting, project:, author: host, title: "Standup", start_time: now - 10.minutes, state: :in_progress) }
    let(:running_item) { create(:meeting_agenda_item, meeting: running, author: host, presenter: ada, title: "Export", notes: "Ben will look into it.") }

    before do
      [host, ada, ben].each { create(:meeting_participant, meeting: running, user: it, invited: true, attended: true) }
      allow(Assistant::Llm).to receive(:configured?).and_return(true)
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
    end

    it "reads an item once for a burst of saves, and only where something was written" do
      expect { 3.times { Assistant::Understanding::MeetingCapture.agenda_item_saved(running_item) } }
        .to have_enqueued_job(Assistant::Understanding::ExtractJob).exactly(:once)

      blank = create(:meeting_agenda_item, meeting: running, author: host, title: "Empty", notes: "")
      expect { Assistant::Understanding::MeetingCapture.agenda_item_saved(blank) }
        .not_to have_enqueued_job(Assistant::Understanding::ExtractJob)
    end

    it "does not read while the meeting is not running, or when the budget is spent" do
      running.update_columns(state: Meeting.states[:open])
      expect { Assistant::Understanding::MeetingCapture.agenda_item_saved(running_item) }
        .not_to have_enqueued_job(Assistant::Understanding::ExtractJob)

      running.update_columns(state: Meeting.states[:in_progress])
      allow(Assistant::Usage).to receive(:near_budget?).and_return(true)
      expect { Assistant::Understanding::MeetingCapture.agenda_item_saved(running_item) }
        .not_to have_enqueued_job(Assistant::Understanding::ExtractJob)
    end

    it "offers an owner under the item once, and takes the line back when the promise has one" do
      promise = create_intent(project:, subject: running, owner: nil, source: running_item, title: "Look into the export")
      2.times { Assistant::Understanding::UnownedItems.offer(running_item, [promise]) }

      expect(Assistant::Signal.where(detector: "meeting_unowned", channel: "inline").count).to eq(1)
      expect(Assistant::Action.where(kind: "meeting_action_item").count).to eq(2)

      promise.update!(owner: ben)
      Assistant::Understanding::UnownedItems.offer(running_item, [promise])

      expect(Assistant::Signal.live.where(detector: "meeting_unowned")).to be_none
      expect(Assistant::Action.proposed.where(kind: "meeting_action_item")).to be_none
    end

    it "asks the host whether an item is a decision already made, and notes it under the item when told so" do
      earlier = create(:meeting, project:, author: host, title: "Planning", start_time: now - 5.days, state: :closed)
      source = create(:meeting_agenda_item, meeting: earlier, author: host, title: "Billing basis")
      create_intent(project:, subject: earlier, owner: host, source:, kind: "decision", status: "active",
                    title: "Billing reconciliation counts tokens rounded to the cent", quote: "Billing reconciliation counts tokens rounded to the cent")
      item = create(:meeting_agenda_item, meeting: running, author: host, title: "Billing reconciliation counts tokens rounded",
                                          notes: "Do we still count tokens rounded to the cent?")

      Assistant::Understanding::RelatedDecision.offer(item)

      signal = Assistant::Signal.find_by!(detector: "meeting_related_decision")
      expect(signal.recipient).to eq(host)
      action = Assistant::Action.find(signal.payload["options"].sole["action_id"])
      Assistant::Actions::Execute.call(action, decided_by: host)
      expect(item.outcomes.sole).to have_attributes(kind: "information")

      login_as(ada)
      get assistant_agenda_item_proposals_path(item)
      expect(response.body).not_to include("meeting_related_decision")
    end

    it "shows the host the line in the frame the page reloads" do
      promise = create_intent(project:, subject: running, owner: nil, source: running_item, title: "Look into the export")
      Assistant::Understanding::UnownedItems.offer(running_item, [promise])

      login_as(host)
      get assistant_agenda_item_proposals_path(running_item)

      expect(response.parsed_body.css("[data-test-selector='assistant-notice']").size).to eq(1)
      expect(response.body).to include(I18n.t("assistant.meeting_recap.unowned.headline", title: "Look into the export"))
    end
  end

  describe "the older due items" do
    it "shows two lines and folds the rest" do
      4.times { |n| create(:work_package, project:, assigned_to: ben, due_date: now.to_date - 20 - n, subject: "Old task #{n}") }
      recap = Assistant::MeetingRecap.new(upcoming, host)

      expect(recap.sections[:due].size).to eq(2)
      expect(recap.older_due.size).to eq(2)
      expect(recap.older_late?).to be(true)
    end
  end
end
