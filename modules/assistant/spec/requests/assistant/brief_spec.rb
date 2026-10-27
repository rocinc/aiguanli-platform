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

RSpec.describe "Today", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant news]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_package_comments edit_project manage_news
                                          use_assistant])
  end
  shared_let(:sam) { create(:user, firstname: "Sam", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, assigned_to: sam, subject: "Search API") }

  let(:turbo) { { "Accept" => "text/vnd.turbo-stream.html" } }

  before do
    Assistant::Membership.ensure_member!(project)
    login_as(sam)
    Member.where(principal: sam).update_all(created_at: 30.days.ago)
  end

  def decision(headline, score: 50)
    Assistant::Signal.create!(detector: "stalled", fingerprint: headline, recipient: sam, project:, subject: work_package,
                              channel: "brief", score:, deliver_at: 1.hour.ago,
                              payload: { "headline" => headline, "because" => ["4 h left"] })
  end

  def comment_draft(text = "Fiona, can you accept it by Friday?")
    Assistant::Actions::Propose.call(
      kind: "ask_owner", title: "Ask Fiona", on_behalf_of: sam, project:, subject: work_package, auto_execute: false,
      steps: [{ "op" => "comment", "type" => "WorkPackage", "id" => work_package.id, "attributes" => { "notes" => text } }]
    )
  end

  def news_draft
    Assistant::Actions::Propose.call(
      kind: "release_notes", title: "Release notes", on_behalf_of: sam, project:, subject: project, auto_execute: false,
      steps: [{ "op" => "publish_news",
                "attributes" => { "project_id" => project.id, "title" => "2.1 is out", "description" => "Page numbers." } }]
    )
  end

  def offer(action)
    options = [{ "label" => action.title, "action_id" => action.id }]
    Assistant::Signal.create!(detector: "duty_weekly_status", fingerprint: "offer-#{action.id}", recipient: sam, project:,
                              channel: "brief", action:, score: 0, deliver_at: 1.hour.ago,
                              payload: { "headline" => action.title, "options" => options })
  end

  def sel(name) = "[data-test-selector='#{name}']"

  def page
    get assistant_today_widget_path
    Capybara.string(response.body)
  end

  it "says only that there is nothing, when there is nothing" do
    expect(page).to have_css(sel("assistant-brief-empty"), text: "Nothing needs you today.")
    expect(page).to have_no_css(sel("assistant-brief-decisions"))
  end

  it "greets a newcomer instead, in the first week" do
    Member.where(principal: sam).update_all(created_at: 2.days.ago)

    expect(page).to have_css(sel("assistant-brief-empty"), text: "I just joined this project.")
  end

  it "fills the my page widget frame" do
    get assistant_today_widget_path

    expect(response.body).to include(%(<turbo-frame id="grids-widgets-assistant-today">))
  end

  it "keeps the groups in order: decisions, drafts, what was done" do
    decision("Your API task is due tomorrow")
    offer(comment_draft)
    Assistant::Action.create!(kind: "link_pr", title: "Linked PR #412", tier: "t1", status: "executed",
                              executed_at: 1.hour.ago, project:, subject: work_package, on_behalf_of: sam, preview: { "success" => true }, plan: { "steps" => [] },
                              inverse: [{ "op" => "revert", "type" => "WorkPackage", "id" => work_package.id }])

    text = page.text
    expect(text.index("To decide")).to be < text.index("Written, waiting for you to send")
    expect(text.index("Written, waiting for you to send")).to be < text.index("What I did for you")
    expect(text).to include("Your API task is due tomorrow", "Linked PR #412")
    expect(text).not_to include("Quiet", "Nothing needs you today.")
  end

  it "does not name the project when there is only one" do
    decision("Your API task is due tomorrow")

    expect(page).to have_no_css(".assistant-brief--project")
  end

  it "names the project of each line when the person is in several" do
    other = create(:project, name: "Elsewhere", enabled_module_names: %w[work_package_tracking assistant])
    create(:member, principal: sam, project: other, roles: [role])
    decision("Your API task is due tomorrow")

    expect(page).to have_css(".assistant-brief--project", text: project.name)
  end

  it "shows at most three decisions and puts the rest under 'less urgent'" do
    4.times { |i| decision("Task #{i} needs you", score: 50 - i) }

    shown = page
    expect(shown).to have_css("#{sel('assistant-brief-decisions')} #{sel('assistant-notice')}", count: 3)
    expect(shown).to have_css(sel("assistant-brief-deferred"), text: "1 less urgent thing")
    expect(shown.find(sel("assistant-brief-deferred"))).to have_text("Task 3 needs you")
  end

  it "orders the same way on every request" do
    5.times { |i| decision("Task #{i} needs you", score: 40) }
    first = page.text

    expect(page.text).to eq(first)
  end

  describe "drafts" do
    it "shows target, signature, words, what happens and the three buttons" do
      offer(comment_draft)

      draft = page.find(sel("assistant-draft"))
      expect(draft).to have_link("##{work_package.id} Search API")
      expect(draft).to have_css(sel("assistant-draft-signature"), text: "Signed: AI assistant (for you)")
      expect(draft).to have_field("Comment", with: "Fiona, can you accept it by Friday?", visible: :all)
      expect(draft).to have_css(sel("assistant-draft-after"), text: "within 7 days")
      expect(draft).to have_button("Send")
      expect(draft).to have_css("label", text: "Edit first")
      expect(draft).to have_button("Discard")
    end

    it "does not show a draft whose target is gone" do
      action = comment_draft
      action.update!(plan: action.plan.merge("steps" => [action.steps.first.merge("id" => 0)]))
      offer(action)

      expect(page).to have_no_css(sel("assistant-draft"))
    end

    it "shows one that no signal carries, once" do
      comment_draft

      expect(page).to have_css(sel("assistant-draft"), count: 1)
    end

    it "does not show an action that offers a choice as a draft" do
      action = comment_draft
      action.update!(plan: action.plan.merge("options" => [{ "key" => "a", "label" => "A" }, { "key" => "b", "label" => "B" }]))

      expect(page).to have_no_css(sel("assistant-draft"))
    end

    it "sends the edited words when the person presses send" do
      action = comment_draft
      offer(action)

      post approve_assistant_action_path(action), params: { edits: { "0" => { "notes" => "Friday works too." } } }, headers: turbo

      expect(response).to have_http_status(:ok)
      expect(action.reload).to be_executed
      expect(work_package.journals.last.notes).to eq("Friday works too.")
      expect(Assistant::Signal.last.outcome).to eq("adopted")
    end

    it "lets the person drop a draft" do
      action = comment_draft
      offer(action)

      post reject_assistant_action_path(action), headers: turbo

      expect(action.reload.status).to eq("rejected")
      expect(page).to have_no_css(sel("assistant-draft"))
    end

    it "asks for 'I have read it' on a T3 draft, and the server insists" do
      action = news_draft
      expect(action.tier).to eq("t3")

      draft = page.find(sel("assistant-draft"))
      expect(draft).to have_css("input[type=checkbox][name=acknowledged][required]")
      expect(draft).to have_css("label", text: "I have read it")

      post approve_assistant_action_path(action), headers: turbo
      expect(response).to have_http_status(:unprocessable_entity)
      expect(action.reload).to be_proposed

      post approve_assistant_action_path(action), params: { acknowledged: "1" }, headers: turbo
      expect(action.reload).to be_executed
    end
  end

  describe "what the person already dealt with on the page" do
    let(:action) do
      Assistant::Actions::Propose.call(
        kind: "reschedule", title: "Move it to Friday", on_behalf_of: sam, project:, subject: work_package, auto_execute: false,
        steps: [{ "op" => "update_work_package", "type" => "WorkPackage", "id" => work_package.id,
                  "attributes" => { "due_date" => "2026-10-16" } }]
      )
    end
    let!(:signal) do
      Assistant::Signal.create!(detector: "stalled", fingerprint: "move", recipient: sam, project:, subject: work_package,
                                channel: "brief", action:, score: 50, deliver_at: 1.hour.ago,
                                payload: { "headline" => "Your API task slipped", "because" => ["4 h left"] })
    end

    it "keeps the line, struck through and said as done, instead of letting it vanish" do
      expect(page).to have_css(sel("assistant-notice-headline"), text: "Your API task slipped")

      post approve_assistant_action_path(action), params: { variant: "compact" }, headers: turbo

      line = page.find(sel("assistant-notice-handled"))
      expect(line.text).to start_with("Handled:")
      expect(line.text).to include("#{work_package.id}")
      expect(page).to have_no_css(sel("assistant-notice-headline"))
      expect(page).to have_no_css(sel("assistant-brief-empty"))
    end

    it "lets the line go after a day" do
      post approve_assistant_action_path(action), params: { variant: "compact" }, headers: turbo
      signal.reload.update_columns(outcome_at: 25.hours.ago)

      expect(page).to have_no_css(sel("assistant-notice-handled"))
    end

    it "does not keep a line for something that was only left alone" do
      post reject_assistant_action_path(action), headers: turbo

      expect(page).to have_no_css(sel("assistant-notice-handled"))
    end
  end
end
