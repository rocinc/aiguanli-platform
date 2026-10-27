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
require "rails_helper"

RSpec.describe Assistant::DraftComponent, type: :component do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages add_work_package_comments use_assistant])
  end
  shared_let(:sam) { create(:user, firstname: "Sam", lastname: "Lee", member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Search API") }

  let(:action) do
    Assistant::Actions::Propose.call(
      kind: "ask_owner", title: "Ask Fiona", on_behalf_of: sam, project:, subject: work_package, auto_execute: false,
      steps: [{ "op" => "comment", "type" => "WorkPackage", "id" => work_package.id, "attributes" => { "notes" => "Friday?" } }]
    )
  end

  def render_draft(**) = render_inline(described_class.new(action:, user: sam, **))

  it "is a card with a target link, the words and the three ways out" do
    render_draft

    expect(page).to have_link("##{work_package.id} Search API")
    expect(page).to have_field("Comment", with: "Friday?", visible: :all)
    expect(page).to have_button("Send")
    expect(page).to have_css("label", text: "Edit first")
    expect(page).to have_button("Discard")
    expect(page).to have_no_field("acknowledged")
  end

  it "lets the person say something about the draft" do
    render_draft

    expect(page).to have_css("[data-test-selector='assistant-say'][data-assistant-context='#{action.to_gid}']",
                             text: "Say something")
  end

  it "shows a mention in the edit box as plain text" do
    bob = create(:user, firstname: "Bob", lastname: "Fischer", member_with_roles: { project => role })
    action.update!(plan: action.plan.merge("steps" => [{ "op" => "comment", "type" => "WorkPackage", "id" => work_package.id,
                                                         "attributes" => { "notes" => "Hi #{Assistant::Reasoning::StepBuilder.mention(bob)}!" } }]))

    render_draft

    expect(page).to have_field("Comment", with: "Hi @Bob Fischer!", visible: :all)
    expect(page).to have_css("[data-test-selector='assistant-draft-text']", text: "Hi @Bob Fischer!")
  end

  context "with a language model configured" do
    before { allow(Assistant::Llm).to receive(:configured?).and_return(true) }

    it "makes the words something to keep working on, with the context the rewrite needs" do
      render_draft

      form = page.find("form[data-controller='assistant--draft-refine']", visible: :all)
      expect(form["data-assistant--draft-refine-url-value"]).to eq("/assistant/writings")
      expect(JSON.parse(form["data-assistant--draft-refine-scope-value"])).to eq("project_id" => project.id)
      expect(page).to have_css("[data-role='revise-input'][placeholder='What else should change?']", visible: :all)
      expect(page).to have_css("[data-role='bar'] [data-role='chip']", count: 4, visible: :all)
      bench = page.find("[data-assistant--draft-refine-target='field']", visible: :all)
      expect(bench["data-task"]).to include("Sam Lee").and include("Comment")
      expect(bench["data-material"]).to include("Friday?")
      expect(page).to have_css("[data-test-selector='assistant-draft-keep']", visible: :all)
    end

    it "leaves fields that are not words alone" do
      step = { "op" => "create_time_entry", "type" => "TimeEntry",
               "attributes" => { "work_package_id" => work_package.id, "user_id" => sam.id, "hours" => 2, "comments" => "Login" } }
      action.update!(plan: { "steps" => [step] })
      render_draft

      expect(page).to have_css("[data-assistant--draft-refine-target='field']", count: 1, visible: :all)
      expect(page).to have_field("edits[0][hours]", visible: :all)
      expect(page).to have_no_css(".assistant-bench input[name='edits[0][hours]']", visible: :all)
    end

    it "asks to tick the confirmation again when the words of a public draft change" do
      step = { "op" => "publish_news", "attributes" => { "project_id" => project.id, "title" => "T", "description" => "Body" } }
      action.update!(plan: { "steps" => [step] }, tier: "t3")
      render_draft

      expect(page).to have_css("[data-assistant--draft-refine-target='reread']", text: /Tick "I have read it" again/,
                                                                                 visible: :all)
    end
  end

  it "is a plain text box without a language model" do
    allow(Assistant::Llm).to receive(:configured?).and_return(false)
    render_draft

    expect(page).to have_field("Comment", with: "Friday?", visible: :all)
    expect(page).to have_no_css("[data-role='revise-input']", visible: :all)
    expect(page).to have_no_css("form[data-controller]", visible: :all)
  end

  it "is one line with a way to look at it" do
    render_draft(density: :line)

    expect(page).to have_link("Take a look", href: "/assistant/actions/#{action.id}")
    expect(page).to have_no_button("Send")
  end

  it "turns into a receipt once sent" do
    Assistant::Decisions.new(action, user: sam).approve
    render_draft

    expect(page).to have_css("[data-assistant-density='line'][data-assistant-action-id='#{action.id}']")
    expect(page).to have_no_button("Send")
  end

  it "becomes a quiet line when dropped" do
    Assistant::Decisions.new(action, user: sam).reject
    render_draft

    expect(page).to have_text("Not sending")
    expect(page).to have_no_button("Send")
  end

  it "signs as the person when the step speaks in the confirmer's name" do
    step = { "op" => "publish_news", "attributes" => { "project_id" => project.id, "title" => "T" } }
    action.update!(plan: { "steps" => [step] })
    render_draft

    expect(page).to have_text("Signed: you")
  end
end
