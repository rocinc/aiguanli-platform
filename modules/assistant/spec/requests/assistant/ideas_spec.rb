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

RSpec.describe "The ideas tab of the desk", :skip_csrf, type: :rails_request do
  shared_let(:type) { create(:type_task) }
  shared_let(:project) { create(:project, types: [type], enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages add_work_packages edit_work_packages add_work_package_notes
                                          view_internal_comments use_assistant])
  end
  shared_let(:reader_role) { create(:project_role, permissions: %i[view_work_packages use_assistant]) }
  shared_let(:quinn) { create(:user, firstname: "Quinn", lastname: "Q", member_with_roles: { project => role }) }
  shared_let(:mia) { create(:user, firstname: "Mia", lastname: "M", member_with_roles: { project => role }) }
  shared_let(:ben) { create(:user, firstname: "Ben", lastname: "B", member_with_roles: { project => reader_role }) }
  shared_let(:status) { create(:default_status) }
  shared_let(:priority) { create(:default_priority) }
  shared_let(:source) { create(:work_package, project:, subject: "Search tuning", type:, status:) }
  shared_let(:secret_project) { create(:project, public: false, types: [type]) }
  shared_let(:secret_source) { create(:work_package, project: secret_project, type:, status:) }

  def say(idea, user, quote, at: Time.current, internal: false, on: source)
    on.reload.add_journal(user:, notes: quote, internal:)
    on.save_journals
    idea.mentions.create!(speaker: user, source: on.journals.reload.last, quote:, said_at: at)
  end

  def ideas_page
    get project_assistant_desk_path(project, tab: "ideas")
    response.parsed_body
  end

  def idea_titles(page) = page.css("[data-test-selector='assistant-desk-ideas'] > ul h3").map { it.text.strip }

  def act(name, idea, **params)
    post public_send(:"#{name}_project_assistant_idea_path", project, idea, format: :turbo_stream), params:
  end

  let!(:repeated) do
    Assistant::Idea.create!(project:, title: "Better recall for short text").tap do |idea|
      say(idea, quinn, "It would be nice if short text recall were better", at: 3.days.ago)
      say(idea, mia, "We could consider better recall for short text", at: 1.day.ago)
    end
  end
  let!(:single) { Assistant::Idea.create!(project:, title: "Dark mode for exports").tap { say(it, mia, "Dark mode for exports would be nice") } }

  it "puts ideas said by more people first and says who raised each, with the words, the day and a link to where" do
    login_as(quinn)
    page = ideas_page

    expect(idea_titles(page)).to eq(["Better recall for short text", "Dark mode for exports"])
    first = page.css("[data-test-selector='assistant-idea']").first
    expect(first.at_css(".assistant-idea--who").text).to eq("Raised by Quinn Q、Mia M")
    expect(first.css("blockquote").size).to eq(2)
    expect(first.at_css("blockquote").text).to eq("“We could consider better recall for short text”")
    expect(first.at_css("a")["href"]).to include("/work_packages/#{source.id}/activity")
    expect(page.at_css("[data-test-selector='assistant-ideas-lead']").text).to eq("Ideas · 2 still growing")
  end

  it "shows no votes, owners or due dates" do
    login_as(quinn)
    text = ideas_page.at_css("[data-test-selector='assistant-desk-ideas']").text

    expect(text).not_to match(/vote|owner|assignee|due/i)
  end

  it "names two people and counts the rest once more than three raised it" do
    crowd = Assistant::Idea.create!(project:, title: "Charts in comments")
    [quinn, mia, ben, create(:user, firstname: "Zoe", lastname: "Z", member_with_roles: { project => role })]
      .each_with_index { |user, i| say(crowd, user, "Charts in comments would be nice #{i}", at: i.days.ago) }
    login_as(quinn)

    page = ideas_page
    expect(page.css("[data-test-selector='assistant-idea']").first.at_css(".assistant-idea--who").text)
      .to eq("Raised by Zoe Z、Ben B and 4 people in all")
  end

  it "folds what was not mentioned for ninety days into the earlier ones and never drops it" do
    old = Assistant::Idea.create!(project:, title: "Old thought")
    say(old, mia, "We could consider an old thing", at: 120.days.ago)
    login_as(quinn)

    page = ideas_page
    expect(idea_titles(page)).not_to include("Old thought")
    expect(page.at_css("[data-test-selector='assistant-ideas-earlier'] h3").text).to eq("Old thought")
    expect(page.at_css("[data-test-selector='assistant-ideas-lead']").text).to eq("Ideas · 2 still growing")
  end

  it "shows a source the reader cannot open only as a place they cannot see, and never lends its title" do
    private_only = Assistant::Idea.create!(project:, title: "Buy the competitor")
    say(private_only, quinn, "Buy the competitor would be nice", on: secret_source)
    internal_only = Assistant::Idea.create!(project:, title: "Customer list import")
    say(internal_only, quinn, "Customer list import would be nice", internal: true)
    mixed = Assistant::Idea.create!(project:, title: "Hidden origin title")
    say(mixed, quinn, "Hidden origin would be nice", internal: true, at: 5.days.ago)
    say(mixed, mia, "We could consider a visible form of it", at: 2.days.ago)
    login_as(ben)

    page = ideas_page
    expect(response.body).not_to include("Buy the competitor", "Customer list import", "Hidden origin")
    entries = page.css("[data-test-selector='assistant-idea']")
    mixed_entry = entries.find { |entry| entry.at_css("blockquote").text.include?("visible form") }
    expect(mixed_entry.at_css("h3").text).to eq("We could consider a visible form of it")
    expect(mixed_entry.at_css(".assistant-idea--who").text).to eq("Raised by Mia M")
    expect(mixed_entry.at_css("[data-test-selector='assistant-idea-hidden']").text).to eq("Somewhere you cannot see")
    act(:release, private_only)
    expect(response).to have_http_status(:not_found)
    expect(private_only.reload.state).to eq("open")
  end

  it "says what the tab is for when nothing was ever mentioned" do
    Assistant::Idea.delete_all
    Member.update_all(created_at: 1.year.ago)
    login_as(quinn)

    expect(ideas_page.at_css("[data-test-selector='assistant-ideas-empty']").text).to include("Nobody has mentioned an idea")
  end

  it "turns an idea into a work package that carries who said it and where, and shows its current status" do
    login_as(quinn)
    expect { act(:convert, repeated) }.to change(WorkPackage, :count).by(1)

    wp = WorkPackage.order(:id).last
    expect(repeated.reload).to have_attributes(state: "adopted", work_package_id: wp.id)
    expect(wp.description).to include("Quinn Q、Mia M", "short text recall", "/work_packages/#{source.id}/activity")
    expect(response.body).to include(%(method="morph"), "liveRegion")
    adopted = Nokogiri::HTML(response.body).at_css("[data-test-selector='assistant-idea-adopted']")
    expect(adopted.at_css("a")["href"]).to end_with("/work_packages/#{wp.id}")
    expect(adopted.text).to include(wp.status.name)
    expect(ideas_page.at_css("[data-test-selector='assistant-ideas-lead']").text).to eq("Ideas · 1 still growing, 1 became work")
  end

  it "merges an idea into another that says the same, keeping every mention" do
    login_as(quinn)
    act(:merge, single, into_id: repeated.id)

    expect(single.reload).to have_attributes(state: "merged", merged_into_id: repeated.id)
    expect(repeated.mentions.count).to eq(3)
    expect(idea_titles(ideas_page)).to eq(["Better recall for short text"])
  end

  it "does not merge an idea into itself or into one that is no longer open" do
    login_as(quinn)
    act(:merge, single, into_id: single.id)
    expect(single.reload.state).to eq("open")

    repeated.set_aside!
    act(:merge, single, into_id: repeated.id)
    expect(single.reload.state).to eq("open")
  end

  it "sets an idea aside with a reason and brings it back" do
    login_as(ben)
    act(:release, single, reason: "Not now")
    expect(single.reload).to have_attributes(state: "set_aside", set_aside_reason: "Not now")
    expect(ideas_page.at_css("[data-test-selector='assistant-idea-reason']").text).to include("Not now")

    act(:restore, single)
    expect(single.reload).to have_attributes(state: "open", set_aside_reason: nil)
  end

  it "does not let someone without add_work_packages convert" do
    login_as(ben)
    act(:convert, repeated)

    expect(response).to have_http_status(:forbidden)
    expect(repeated.reload.state).to eq("open")
    expect(ideas_page.css("[data-test-selector='assistant-idea-convert']")).to be_empty
  end
end
