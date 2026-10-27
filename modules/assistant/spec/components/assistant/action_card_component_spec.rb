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

RSpec.describe Assistant::ActionCardComponent, type: :component do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages work_package_assigned use_assistant])
  end
  shared_let(:sam) { create(:user, firstname: "Sam", lastname: "Lee", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "Ng", member_with_roles: { project => role }) }
  shared_let(:viewer) { create(:user, member_with_roles: { project => create(:project_role, permissions: %i[view_work_packages use_assistant]) }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "Search API", assigned_to: ben) }

  let(:preview) do
    {
      "success" => true,
      "changes" => [
        { "gid" => work_package.to_gid.to_s, "type" => "WorkPackage", "id" => work_package.id,
          "label" => "##{work_package.id} Search API", "created" => false,
          "changes" => { "due_date" => ["2026-10-02", "2026-10-07"] } },
        { "gid" => "gid://openproject/WorkPackage/999", "type" => "WorkPackage", "id" => 999,
          "label" => "#999 Release notes", "created" => false,
          "changes" => { "start_date" => ["2026-10-05", "2026-10-08"] } }
      ],
      "cascaded" => ["gid://openproject/WorkPackage/999"],
      "affected_user_ids" => [ben.id],
      "version_slips" => [{ "name" => "v2.0", "target" => "2026-10-09", "finish_before" => "2026-10-08",
                            "finish_after" => "2026-10-12", "late" => true, "was_late" => false }]
    }
  end

  let(:action) do
    Assistant::Action.create!(kind: "reschedule", title: "Move Search API to Wednesday", tier: "t2", status: "proposed",
                              project:, subject: work_package, on_behalf_of: sam, preview:,
                              plan: { "steps" => [{ "op" => "update_work_package", "type" => "WorkPackage",
                                                    "id" => work_package.id, "attributes" => { "due_date" => "2026-10-07" } }] },
                              basis: [{ "kind" => "quote", "label" => "Sprint 6 planning", "quote" => "push it to Wednesday" }])
  end

  def card(user, **) = render_inline(described_class.new(action:, user:, **))

  it "says what would move, what moves along, which version slips and whom it touches" do
    card(sam)

    expect(page).to have_css("h3", text: "Move Search API to Wednesday")
    expect(page).to have_test_selector("assistant-action-change", text: "Search API")
    expect(page).to have_test_selector("assistant-action-cascade", text: "#999 Release notes")
    expect(page).to have_css(".assistant-card--slip-late", text: "v2.0")
    expect(page).to have_test_selector("assistant-action-people", text: "Ben Ng")
    expect(page).to have_css("details summary", text: "Basis")
    expect(page).to have_css("blockquote", text: "push it to Wednesday", visible: :all)
  end

  it "says each touched record as one sentence a person can read, without model names" do
    reply = Assistant::Action.create!(
      kind: "reply", title: "Answer on Search API", tier: "t2", status: "proposed", project:, subject: work_package,
      on_behalf_of: sam, plan: { "steps" => [] },
      preview: {
        "success" => true, "cascaded" => [], "affected_user_ids" => [], "version_slips" => [],
        "changes" => [
          { "gid" => "gid://openproject/Journal/12", "type" => "Journal", "id" => 12, "kind" => "comment",
            "label" => "##{work_package.id} Search API", "detail" => { "text" => "Friday is fine", "internal" => false },
            "anchor" => { "type" => "WorkPackage", "id" => work_package.id }, "created" => true, "changes" => {} },
          { "gid" => "gid://openproject/WorkPackage/999", "type" => "WorkPackage", "id" => 999, "kind" => "work_package",
            "label" => "Release notes", "detail" => { "type" => "Task" }, "anchor" => nil, "created" => true,
            "changes" => {} },
          { "gid" => work_package.to_gid.to_s, "type" => "WorkPackage", "id" => work_package.id, "kind" => "work_package",
            "label" => "##{work_package.id} Search API", "detail" => {}, "created" => false,
            "anchor" => { "type" => "WorkPackage", "id" => work_package.id },
            "changes" => { "due_date" => ["2026-09-23", "2026-09-30"] } }
        ]
      }
    )

    render_inline(described_class.new(action: reply, user: sam))

    lines = page.all("[data-test-selector='assistant-action-change']").map { it.text.squish }
    expect(lines).to eq(["Comment on ##{work_package.id} Search API: “Friday is fine”",
                         "Create Task “Release notes”",
                         "##{work_package.id} Search API: Finish date 9/23 (Wed) → 9/30 (Wed)"])
    expect(page.all("[data-test-selector='assistant-action-change'] a").map { it[:href] })
      .to eq(["/work_packages/#{work_package.id}"] * 2)
    expect(page.text).not_to match(/Journal|Relation/)
  end

  it "writes when it was proposed the way the rest of the assistant does, not in the browser's English" do
    card(sam)

    time = page.find("header time")
    expect(time[:datetime]).to eq(action.updated_at.iso8601)
    expect(time.text).to eq(Assistant::Text.stamp(action.updated_at))
  end

  it "lets the person it is for decide" do
    card(sam)

    expect(page).to have_test_selector("assistant-action-approve")
    expect(page).to have_test_selector("assistant-action-reject")
  end

  it "only tells others who is to decide" do
    card(viewer)

    expect(page).not_to have_test_selector("assistant-action-approve")
    expect(page).to have_text("Sam Lee")
  end

  it "offers the ways to choose from when there are several" do
    action.update!(plan: action.plan.merge("options" => [
                                             { "key" => "parallel", "label" => "Let Quinn take #75", "consequence" => "v2.0 holds" },
                                             { "key" => "push", "label" => "Push v2.0 to 10/9", "steps" => [] }
                                           ]))
    card(sam)

    expect(page).to have_test_selector("assistant-action-option", count: 2)
    expect(page).to have_field("option", with: "parallel", checked: true)
    expect(page).to have_text("v2.0 holds")
  end

  it "offers undo once done, and lists conflicts before overwriting" do
    action.update!(status: "executed", executed_at: Time.current, decided_by: sam,
                   inverse: [{ "op" => "revert", "type" => "WorkPackage", "id" => work_package.id }])

    card(sam)
    expect(page).to have_test_selector("assistant-action-undo")

    card(sam, conflicts: [{ "label" => "#1 Search API", "attribute" => "due_date" }])
    expect(page).to have_test_selector("assistant-action-conflicts", text: "#1 Search API")
    expect(page).to have_test_selector("assistant-action-undo-keep")
  end

  it "explains a failure without offering buttons" do
    action.update!(status: "failed", error: "Due date must be after start date")
    card(sam)

    expect(page).to have_text("Due date must be after start date")
    expect(page).not_to have_test_selector("assistant-action-approve")
  end

  it "shows word for word what it would say in public, and an icon for where each basis comes from" do
    journal = work_package.journals.last
    action.update!(plan: { "steps" => [{ "op" => "comment", "type" => "WorkPackage", "id" => work_package.id,
                                         "attributes" => { "notes" => "<p>Moving this to Wednesday.</p>" } }] },
                   basis: [{ "kind" => "journal", "gid" => journal.to_gid.to_s, "label" => "Comment" }])
    card(sam)

    expect(page).to have_test_selector("assistant-action-spoken", text: "Moving this to Wednesday.")
    expect(page).to have_css("section[aria-label] blockquote")
    expect(page).to have_css(".assistant-card--basis-entry svg.octicon-issue-opened[aria-hidden='true']", visible: :all)
  end

  it "reads a drafted work package's description with its acceptance boxes" do
    action.update!(kind: "request_draft",
                   plan: { "steps" => [{ "op" => "create_work_package",
                                         "attributes" => { "subject" => "CSV export",
                                                           "description" => "Export.\n\n- [ ] Has headers\n- [ ] UTF-8" } }] })
    card(sam)

    expect(page).to have_test_selector("assistant-action-spoken", text: "The new work package will say:")
    expect(page).to have_test_selector("assistant-action-spoken", text: "☐ Has headers")
  end

  it "shows only what is added to someone else's wiki page, and that it waits for a go-ahead" do
    wiki = project.wiki || create(:wiki, project:)
    create(:wiki_page, wiki:, title: "Architecture", text: "We use Postgres.", author: ben)
    action.update!(tier: "t2",
                   plan: { "steps" => [{ "op" => "create_wiki_page",
                                         "attributes" => { "project_id" => project.id, "title" => "Architecture",
                                                           "text" => "We use Postgres.\n\n> Replaced: we use SQLite." } }] })
    card(sam)

    spoken = page.find("[data-test-selector='assistant-action-spoken']")
    expect(spoken).to have_text("Added at the end of the wiki page “Architecture”")
    expect(spoken).to have_text("Replaced: we use SQLite.")
    expect(spoken).to have_no_text("We use Postgres.")
    expect(page).to have_test_selector("assistant-action-tier", text: "Needs your go-ahead")
  end
end
