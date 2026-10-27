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

RSpec.describe Assistant::Linkify do
  shared_let(:project) do
    create(:project, name: "Quill Platform", enabled_module_names: %w[work_package_tracking wiki meetings])
  end
  shared_let(:secret_project) do
    create(:project, name: "Hidden Research", public: false, enabled_module_names: %w[work_package_tracking])
  end
  shared_let(:role) do
    create(:project_role, permissions: %i[view_project view_work_packages view_wiki_pages view_meetings])
  end
  shared_let(:reader) { create(:user, firstname: "Rita", lastname: "Reader", member_with_roles: { project => role }) }
  shared_let(:colleague) { create(:user, firstname: "Colin", lastname: "Mate", member_with_roles: { project => role }) }
  shared_let(:outsider) do
    create(:user, firstname: "Olga", lastname: "Outside", member_with_roles: { secret_project => role })
  end
  shared_let(:work_package) { create(:work_package, project:, subject: "Knowledge base permissions") }
  shared_let(:secret_package) { create(:work_package, project: secret_project, subject: "Competitor matrix") }
  shared_let(:version) { create(:version, project:, name: "v2.0 Team Edition") }
  shared_let(:secret_version) { create(:version, project: secret_project, name: "Vault 9.9", sharing: "none") }
  shared_let(:wiki_page) { create(:wiki_page, wiki: project.wiki || create(:wiki, project:), title: "Sprint process") }
  shared_let(:meeting) { create(:meeting, project:, title: "Sprint 6 planning", start_time: 1.day.from_now) }

  def render_for(text, user: reader)
    Nokogiri::HTML.fragment(described_class.call(text, user:, project:))
  end

  def link_to(fragment, href) = fragment.at_css("a[href='#{href}']")

  it "turns #id into a link with the platform's hover card and takes the title that follows into the link" do
    fragment = render_for("See ##{work_package.id} Knowledge base permissions now")

    link = link_to(fragment, "/work_packages/#{work_package.id}")
    expect(link.text).to eq("##{work_package.id} Knowledge base permissions")
    expect(link["data-hover-card-url"]).to eq("/work_packages/#{work_package.id}/hover_card")
    expect(link["data-turbo-frame"]).to eq("_top")
    expect(fragment.text).to eq("See ##{work_package.id} Knowledge base permissions now")
  end

  it "links versions, wiki pages, meetings, projects and people the reader can see" do
    text = "#{version.name}, #{wiki_page.title}, #{meeting.title}, #{project.name}, #{colleague.name}"
    fragment = render_for(text)

    expect(link_to(fragment, "/versions/#{version.id}").text).to eq(version.name)
    expect(link_to(fragment, "/meetings/#{meeting.id}").text).to eq(meeting.title)
    expect(link_to(fragment, "/projects/#{project.identifier}").text).to eq(project.name)
    expect(link_to(fragment, "/users/#{colleague.id}")["data-hover-card-url"]).to eq("/users/#{colleague.id}/hover_card")
    expect(fragment.css("a").map(&:text)).to include(wiki_page.title)
  end

  it "links a version by its first word when only one version starts that way" do
    fragment = render_for("Slips into v2.0 next week")

    expect(link_to(fragment, "/versions/#{version.id}").text).to eq("v2.0")
  end

  it "leaves what the reader cannot see as plain words" do
    text = "##{secret_package.id} #{secret_package.subject}; #{secret_version.name}; #{secret_project.name}; #{outsider.name}"
    fragment = render_for(text)

    expect(fragment.css("a")).to be_empty
    expect(fragment.text).to eq(text)
  end

  it "does not touch names inside code or inside existing links" do
    fragment = render_for("`#{version.name}` and [#{colleague.name}](https://example.com)")

    expect(fragment.at_css("code").css("a")).to be_empty
    expect(fragment.css("a").pluck("href")).to eq(["https://example.com"])
  end

  it "renders markdown and drops scripts" do
    fragment = render_for("**Done**\n\n- one\n- two\n\n<script>alert(1)</script>")

    expect(fragment.css("strong").text).to eq("Done")
    expect(fragment.css("ul li").size).to eq(2)
    expect(fragment.css("script")).to be_empty
    expect(fragment.text).not_to include("alert(1)")
  end

  it "links an #id the platform skips because a full-width mark or a Chinese character comes before it" do
    fragment = render_for("下游：##{work_package.id} Knowledge base permissions，见##{secret_package.id}。")

    link = link_to(fragment, "/work_packages/#{work_package.id}")
    expect(link.text).to eq("##{work_package.id} Knowledge base permissions")
    expect(link["data-hover-card-url"]).to eq("/work_packages/#{work_package.id}/hover_card")
    expect(fragment.css("a").size).to eq(1)
    expect(fragment.text).to include("见##{secret_package.id}。")
  end

  it "links a first name alone when it is the only one among the people the reader can see" do
    fragment = render_for("Colin will reply, Rita should wait")

    expect(link_to(fragment, "/users/#{colleague.id}").text).to eq("Colin")
    expect(link_to(fragment, "/users/#{reader.id}").text).to eq("Rita")
  end
end
