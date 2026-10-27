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

RSpec.describe "The decisions on record, shown on the objects they bear on", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking wiki assistant meetings]) }
  shared_let(:role) do
    create(:project_role, permissions: %i[view_work_packages edit_work_packages use_assistant view_wiki_pages view_meetings])
  end
  shared_let(:ada) { create(:user, firstname: "Ada", lastname: "A", member_with_roles: { project => role }) }
  shared_let(:sam) { create(:user, member_with_roles: { project => role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "权限模型") }
  shared_let(:version) { create(:version, project:) }

  shared_let(:wiki) { create(:wiki, project:) }

  before do
    Assistant::Membership.ensure_member!(project)
    login_as(sam)
  end

  def said!(work_package, user, notes)
    work_package.add_journal(user:, notes:)
    work_package.save!(validate: false)
    work_package.journals.reload.last
  end

  def decide!(subject, title: "权限模型定为两层", quote: "知识库级 + 文档级两层", on: work_package, **attributes)
    source = said!(on, ada, quote)
    create_intent(project:, subject:, owner: ada, source:, kind: "decision", status: "active", title:, quote:, **attributes)
  end

  def marks = response.parsed_body.at_css("[data-test-selector='assistant-marks']")

  it "says one line on the work package it was decided about, and opens to the words" do
    decide!(work_package)

    get assistant_work_package_line_path(work_package)

    expect(marks.at_css("summary").text).to include(I18n.t("assistant.marks.sentence_here", day: Assistant::Text.day(Date.current),
                                                                                         title: "权限模型定为两层"))
    entry = marks.at_css("[data-test-selector='assistant-mark']")
    expect(entry.at_css("blockquote").text).to eq("知识库级 + 文档级两层")
    original = entry.css(".assistant-marks--origin a").last
    expect(original.text).to eq(I18n.t("assistant.marks.original_here"))
    expect(original["href"]).to include("/work_packages/#{work_package.id}/activity#comment-")
  end

  it "folds a second decision behind the first and counts it" do
    decide!(work_package)
    decide!(work_package, title: "对账口径按 token 折算", quote: "按 token 折算")

    get assistant_work_package_line_path(work_package)

    expect(marks.at_css("summary").text).to include(I18n.t("assistant.marks.summary_many", sentence: "", count: 1))
    entries = marks.css("[data-test-selector='assistant-mark']")
    expect(entries.size).to eq(2)
    expect(entries.first.at_css(".assistant-marks--title")).to be_nil
    expect(entries.last.at_css(".assistant-marks--title").text).to be_present
  end

  it "links to the decision record page once it exists" do
    decide!(work_package)
    page = create(:wiki_page, wiki:, title: Assistant::DecisionRecord.title(project))

    get assistant_work_package_line_path(work_package)

    expect(marks.at_css(".assistant-marks--record a")["href"]).to include(page.slug)
  end

  it "finds a decision on a work package whose words overlap" do
    decide!(create(:work_package, project:, subject: "别的事"), title: "权限模型定为知识库级两层")
    work_package.update_columns(description: "梳理权限模型和知识库级权限")

    get assistant_work_package_line_path(work_package)

    expect(marks.at_css("summary").text).to include("权限模型定为知识库级两层")
  end

  it "takes no room where nothing was decided" do
    get assistant_work_package_line_path(work_package)

    expect(response.body).to eq(%(<turbo-frame id="assistant-wp-line-frame"></turbo-frame>))
  end

  it "leaves out a decision whose original words the reader cannot open" do
    elsewhere = create(:project, public: false, enabled_module_names: %w[work_package_tracking])
    source = said!(create(:work_package, project: elsewhere), ada, "私下定了")
    create_intent(project:, subject: work_package, owner: ada, source:, kind: "decision", status: "active",
                  title: "不该被看到", quote: "私下定了")

    get assistant_work_package_line_path(work_package)

    expect(response.body).not_to include("不该被看到")
  end

  it "shows on a version page above the object line" do
    decide!(version, title: "v2 只做权限", on: work_package)

    get version_path(version)

    expect(marks.at_css("summary").text).to include("v2 只做权限")
  end

  it "does not mark the decision record page itself" do
    decide!(work_package, title: "权限模型定为两层")
    page = create(:wiki_page, wiki:, title: Assistant::DecisionRecord.title(project),
                              text: "权限模型定为两层")

    get project_wiki_path(project, page)

    expect(marks).to be_nil
  end
end
