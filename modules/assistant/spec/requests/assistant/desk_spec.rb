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

RSpec.describe "The assistant's desk", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:manager_role) { create(:project_role, permissions: %i[view_work_packages use_assistant manage_assistant]) }
  shared_let(:member_role) { create(:project_role, permissions: %i[view_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, language: "zh-CN", member_with_roles: { project => manager_role }) }
  shared_let(:ben) { create(:user, language: "zh-CN", member_with_roles: { project => member_role }) }

  def tab_names = response.parsed_body.css("[data-test-selector^='assistant-desk-tab-']").pluck("data-test-selector")

  before { login_as(sam) }

  it "says once that it is new while it is new and the whole desk is empty" do
    Member.where(principal: Assistant.user).update_all(created_at: 2.days.ago)

    get project_assistant_desk_path(project)

    expect(response.body.scan("我刚加入这个项目。先看几天，等有足够的数据再说话。").size).to eq(1)
    expect(response.body).to include("最近 7 天我没有替你改动任何东西。")
  end

  it "keeps the specific empty sentences while it is new once something is on the desk" do
    Member.where(principal: Assistant.user).update_all(created_at: 2.days.ago)
    create(:work_package, project:, assigned_to: sam)

    get project_assistant_desk_path(project)

    expect(response.body).not_to include("我刚加入这个项目。先看几天，等有足够的数据再说话。")
    expect(response.body).to include("最近 7 天我没有替你改动任何东西。")
  end

  it "opens on what it watches for the person, and says so when there is nothing" do
    Member.update_all(created_at: 1.year.ago)
    get project_assistant_desk_path(project)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("在这个项目里：0 项职责 · 主动程度：标准")
    expect(response.body).to include("这个项目里我还没替你盯什么。", "最近 7 天我没有替你改动任何东西。")
    expect(tab_names).to eq(%w[watching duties ideas insights].map { "assistant-desk-tab-#{it}" })
  end

  it "shows the page that used to stand alone under each other tab" do
    get project_assistant_desk_path(project, tab: "duties")
    expect(response.body).to include("assistant-duties")

    get project_assistant_desk_path(project, tab: "ideas")
    expect(response.body).to include("assistant-desk-ideas")

    get project_assistant_desk_path(project, tab: "insights")
    expect(response.body).to include("assistant-insights")
  end

  it "falls back to the first tab for a tab it does not know" do
    get project_assistant_desk_path(project, tab: "nothing")

    expect(response.body).to include("assistant-desk-watching")
  end

  it "shows every tab to a member who may not manage, who reads them without being able to change anything" do
    login_as(ben)

    get project_assistant_desk_path(project)
    expect(tab_names).to eq(%w[watching duties ideas insights].map { "assistant-desk-tab-#{it}" })

    Assistant::Duty.create!(project:, kind: "weekly_status", delegator: sam)
    get project_assistant_desk_path(project, tab: "duties")
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("每周项目状态")
    expect(response.body).not_to include("assistant-duty-toggle")

    get project_assistant_desk_path(project, tab: "insights")
    expect(response).to have_http_status(:ok)
  end

  it "lists what was promised through the work package it is about, with the work package's date" do
    work_package = create(:work_package, project:, due_date: Date.new(2026, 9, 17))
    Assistant::Intent.create!(project:, kind: "commitment", status: "open", strength: "firm", title: "UI 联调", quote: "我来联调",
                              owner: sam, counterparty: ben, source: work_package, subject: work_package, work_package:,
                              said_due_on: Date.new(2026, 9, 1), stated_at: Time.current, extractor_version: "test")

    get project_assistant_desk_path(project)

    page = Capybara.string(response.body)
    expect(page).to have_text("你答应 #{ben.name}：")
    expect(page).to have_link(ben.name, href: user_path(ben))
    expect(page).to have_text("UI 联调")
    expect(page).to have_text("9/17（周四）")
    expect(response.body).not_to include("当时说的")
  end

  describe "being quiet for a while" do
    it "holds back interruptions until the end of the chosen day, and can be taken back" do
      post project_assistant_pause_path(project), params: { length: "tomorrow" }

      expect(response).to redirect_to(project_assistant_desk_path(project))
      preference = Assistant::Preference.effective(sam, project)
      expect(preference).to be_quiet
      expect(preference.cap).to eq(0)

      get project_assistant_desk_path(project)
      expect(response.body).to include("安静到")

      delete project_assistant_pause_path(project)
      expect(Assistant::Preference.effective(sam, project)).not_to be_quiet
    end

    it "refuses a length it does not offer" do
      post project_assistant_pause_path(project), params: { length: "forever" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Assistant::Preference.find_by(owner: sam)&.paused_until).to be_nil
    end
  end
end
