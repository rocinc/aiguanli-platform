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

RSpec.describe "What can be done with a remembered promise, decision or question", :skip_csrf, type: :rails_request do
  shared_let(:project) do
    create(:project, enabled_module_names: %w[work_package_tracking meetings assistant])
  end
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_packages work_package_assigned
                                          add_work_package_comments view_meetings manage_agendas manage_outcomes use_assistant])
  end
  shared_let(:host) { create(:user, firstname: "Sam", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", member_with_roles: { project => role }) }
  shared_let(:ada) { create(:user, firstname: "Ada", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Wire up permissions", assigned_to: ben) }

  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }
  let(:now) { Time.zone.local(2026, 10, 12, 10, 30) }
  let(:current) { create(:meeting, project:, author: host, title: "Mid-sprint planning", start_time: now, duration: 1) }
  let!(:promise) do
    create_intent(project:, subject: work_package, owner: ben, counterparty: host, work_package:,
                  title: "Wire up the permission API", quote: "I will wire it up by Wednesday")
  end
  let!(:handed) do
    create_intent(project:, subject: work_package, owner: ben, work_package:, title: "Wire up the permission API",
                  quote: "I will wire it up by Wednesday, said in passing")
  end
  let!(:question) do
    create_intent(project:, subject: work_package, owner: host, counterparty: ben, work_package:, kind: "question",
                  title: "Which level wins on conflict?", quote: "Which level wins?")
  end

  before do
    travel_to(now)
    login_as(host)
  end

  after { travel_back }

  def params(**) = { context_meeting_id: current.id, **}

  def frame_html = Nokogiri::HTML(response.body.then { Nokogiri::HTML(it).at_css("template")&.inner_html || it })

  it "opens the panel of a verb with the meetings to choose from" do
    get assistant_intent_verb_path(promise, "schedule"), params: params

    expect(response).to have_http_status(:ok)
    page = Capybara.string(response.body)
    expect(page).to have_css("turbo-frame#assistant-verb-panel-#{promise.id}")
    expect(page).to have_css("input[type=radio][name=meeting_id][checked]", count: 1)
    expect(page).to have_text(current.title)
  end

  it "puts the item on this meeting's agenda, linked to the work package, with the words and where they were said" do
    expect do
      post assistant_intent_verb_path(promise, "schedule"), params: params(meeting_id: current.id), headers: turbo
    end.to change { current.agenda_items.count }.by(1)

    item = current.agenda_items.order(:id).last
    expect(item.work_package).to eq(work_package)
    expect(item.notes).to include("I will wire it up by Wednesday").and include("/work_packages/#{work_package.id}")
    expect(response.body).to include("assistant-receipt").and include("assistant-intent-scheduled")
  end

  it "waits for a confirmation before adding to a meeting somebody else organises" do
    theirs = create(:meeting, project:, author: ada, title: "Ada's review", start_time: now + 1.day)

    expect do
      post assistant_intent_verb_path(promise, "schedule"), params: params(meeting_id: theirs.id)
    end.not_to(change { theirs.agenda_items.count })
    expect(response.body).to include("assistant-verb-consequence").or include("confirm")

    post assistant_intent_verb_path(promise, "schedule"), params: params(meeting_id: theirs.id, confirm: "1"), headers: turbo
    expect(theirs.agenda_items.count).to eq(1)
  end

  it "shows what handing a work package over would change before doing it, and does it once confirmed" do
    expect do
      post assistant_preview_intent_verb_path(handed, "assign"), params: params(person_id: ada.id)
    end.not_to(change { Assistant::Action.count })
    expect(response.body).to include(ada.name)
    expect(work_package.reload.assigned_to).to eq(ben)

    post assistant_intent_verb_path(handed, "assign"), params: params(person_id: ada.id, confirm: "1"), headers: turbo

    expect(work_package.reload.assigned_to).to eq(ada)
    expect(handed.reload.owner).to eq(ada)
  end

  it "says so when the person already has it" do
    post assistant_preview_intent_verb_path(handed, "assign"), params: params(person_id: ben.id)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("assistant-verb-message")
  end

  it "drafts a comment in the speaker's name to remind someone, and sends nothing" do
    journals = work_package.journals.count
    post assistant_intent_verb_path(promise, "remind"), params: params(target_id: ben.id), headers: turbo

    draft = Assistant::Action.where(kind: "intent_remind").sole
    expect(draft).to be_proposed
    expect(draft.steps.first).to include("op" => "comment", "as" => "person", "id" => work_package.id)
    expect(draft.steps.first.dig("attributes", "notes")).to include("Wire up the permission API")
    expect(response.body).to include("assistant-draft")
    expect(work_package.journals.count).to eq(journals)
  end

  it "points a question at someone with a draft, not by doing anything behind their back" do
    post assistant_intent_verb_path(question, "assign"), params: params(person_id: ada.id), headers: turbo

    draft = Assistant::Action.where(kind: "intent_assign").sole
    expect(draft).to be_proposed
    expect(draft.steps.first).to include("op" => "comment", "as" => "person")
  end

  it "answers a question as a draft and settles it only once the draft is sent" do
    post assistant_intent_verb_path(question, "answer"), params: params(text: "The narrower level."), headers: turbo
    draft = Assistant::Action.where(kind: "intent_answer").sole
    expect(question.reload.status).to eq("open")

    Assistant::Decisions.new(draft, user: host).approve
    Assistant::IntentVerbs::Effects.reconcile(question)

    expect(question.reload.status).to eq("answered")
  end

  it "explains why a result cannot be recorded yet, instead of failing" do
    decision = create_intent(project:, subject: work_package, owner: ben, work_package:, kind: "decision", status: "active",
                             title: "Two levels")

    get assistant_intent_verb_path(decision, "record"), params: params
    expect(response).to have_http_status(:ok)
    expect(Capybara.string(response.body)).to have_text(I18n.t("assistant.verbs.refused.outcome_not_started"))

    post assistant_intent_verb_path(decision, "record"), params: params(text: "Keep it"), headers: turbo
    expect(response).to have_http_status(:ok)
    expect(Capybara.string(response.body)).to have_text(I18n.t("assistant.verbs.refused.outcome_not_started"))
  end

  it "records the result under an agenda item while the meeting runs" do
    current.update_columns(state: Meeting.states[:in_progress])
    item = create(:meeting_agenda_item, meeting: current, author: host, title: "Permissions")
    decision = create_intent(project:, subject: work_package, owner: ben, work_package:, kind: "decision", status: "active",
                             title: "Two levels")

    post assistant_intent_verb_path(decision, "record"), params: params(text: "Keep it", agenda_item_id: item.id), headers: turbo

    expect(item.outcomes.sole.notes).to include("Keep it")
    expect(decision.reload.answered_by).to eq(item.outcomes.sole)
  end

  it "sets an item aside and takes it back" do
    post assistant_intent_verb_path(question, "shelve"), params: params, headers: turbo
    expect(question.reload.status).to eq("dismissed")
    expect(response.body).to include("assistant-intent-shelved")

    post assistant_shelved_intent_path(question), params: params, headers: turbo
    expect(question.reload.status).to eq("open")
  end

  it "does not let anyone act on what they cannot see" do
    outsider = create(:user)
    login_as(outsider)

    post assistant_intent_verb_path(promise, "shelve"), params: params, headers: turbo

    expect(response).to have_http_status(:not_found)
    expect(promise.reload.status).to eq("open")
  end

  describe "on the meeting page" do
    let(:previous) { create(:meeting, project:, author: host, title: "Last week", start_time: now - 5.days, state: :closed) }

    before do
      [host, ben].each { create(:meeting_participant, meeting: current, user: it, invited: true) }
      promise.update_columns(subject_type: "Meeting", subject_id: previous.id, work_package_id: nil)
    end

    it "gives every line of what was said last time its verbs, and names who said it" do
      get project_meeting_path(project, current)

      recap = Capybara.string(response.body)
      expect(recap).to have_css("[data-test-selector='assistant-meeting-recap-item']", minimum: 1)
      expect(recap).to have_css("[data-test-selector='assistant-intent-verbs-bar']")
      expect(recap).to have_css("[data-test-selector='assistant-meeting-recap-who']")
      expect(recap).to have_css("[data-verb='schedule']")
    end
  end
end
