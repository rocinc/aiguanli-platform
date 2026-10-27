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

RSpec.describe "How the assistant is doing", :skip_csrf, type: :rails_request do
  shared_let(:project) { create(:project, enabled_module_names: %w[work_package_tracking assistant]) }
  shared_let(:manager_role) { create(:project_role, permissions: %i[view_work_packages use_assistant manage_assistant]) }
  shared_let(:member_role) { create(:project_role, permissions: %i[view_work_packages use_assistant]) }
  shared_let(:sam) { create(:user, language: "zh-CN", member_with_roles: { project => manager_role }) }
  shared_let(:ben) { create(:user, language: "zh-CN", member_with_roles: { project => member_role }) }
  shared_let(:work_package) { create(:work_package, project:, subject: "接口联调") }

  let(:page) { response.parsed_body.at_css("[data-test-selector='assistant-insights']") }

  def say!(detector, outcome: nil, headline: "#{detector} 的话", subject: work_package, told_at: 3.days.ago, gate: nil)
    payload = { "headline" => headline, "gate" => gate }.compact
    Assistant::Signal.create!(detector:, fingerprint: "#{detector}-#{Assistant::Signal.count}", recipient: ben, project:,
                              subject:, channel: "brief", state: "delivered", deliver_at: told_at,
                              delivered_at: told_at, outcome:, outcome_at: (told_at + 1.hour if outcome), payload:,
                              created_at: told_at)
  end

  def open_assistant_for_a_while!
    Member.where(project:, principal: Assistant.user).update_all(created_at: 20.days.ago)
  end

  before { login_as(sam) }

  it "says it has just joined, instead of showing numbers, in the first week" do
    Assistant::Membership.ensure_member!(project)
    get project_assistant_desk_path(project, tab: "insights")

    expect(page.text).to include("我刚加入这个项目。先看几天，等有足够的数据再说话。")
    expect(page.css("details")).to be_empty
  end

  context "when it has been here a while" do
    before do
      Assistant::Membership.ensure_member!(project)
      open_assistant_for_a_while!
      Member.update_all(created_at: 1.year.ago)
    end

    it "shows no percentage from too few notices, and says why" do
      say!("stalled", outcome: "adopted")
      say!("stalled", outcome: "wrong", headline: "#{work_package.id} 停了 6 天")

      get project_assistant_desk_path(project, tab: "insights")

      expect(page.at_css("[data-test-selector='assistant-insights-headline']").text)
        .to include("说了 2 次，被采纳 1 次；样本还太少（2 次），不显示比例", "说错 1 次")
      expect(page.text).not_to include("50%")
    end

    it "gives the share once there are enough notices" do
      8.times { say!("stalled", outcome: "adopted") }
      2.times { say!("stalled", outcome: "ignored") }

      get project_assistant_desk_path(project, tab: "insights")

      expect(page.at_css("[data-test-selector='assistant-insights-headline']").text).to include("说了 10 次，被采纳 8 次（80%）")
    end

    it "lists, per rule and without names, what was said, what is muted and what was said wrong" do
      say!("stalled", outcome: "wrong", headline: "接口联调停了 6 天")
      Assistant::Preference.for(project).mute!("critical_slip")
      Assistant::Preference.for(ben).mute!("wiki_stale")

      get project_assistant_desk_path(project, tab: "insights")

      rules = page.at_css("[data-test-selector='assistant-insights-rules']").text
      expect(rules).to include(I18n.t("assistant.insights.detectors.stalled.title", locale: :"zh-CN"), "说了 1 次，被采纳 0 次")
      expect(rules).to include(I18n.t("assistant.insights.detectors.critical_slip.title", locale: :"zh-CN"), "已静音")

      muted = page.at_css("[data-test-selector='assistant-insights-muted']").text
      expect(muted).to include("关键路径", I18n.t("assistant.insights.detectors.wiki_stale.title", locale: :"zh-CN"))
      expect(muted).not_to include(ben.name)

      wrong = page.at_css("[data-test-selector='assistant-insights-wrong']")
      expect(wrong.text).to include("“接口联调停了 6 天”", "收回")
      expect(wrong.at_css("a")["href"]).to eq(work_package_path(work_package))
      expect(page.text).not_to include(ben.name)
    end

    it "counts leaving it alone and taking back apart from being wrong, and counts mutes made for this project only" do
      say!("stalled", outcome: "wrong")
      2.times { say!("stalled", outcome: "rejected") }
      say!("critical_slip", outcome: "undone")
      Assistant::Preference.for(ben).mute_in!("wiki_stale", project)
      Assistant::Preference.for(ben).mute_in!("thread_settled", create(:project))

      get project_assistant_desk_path(project, tab: "insights")

      expect(page.at_css("[data-test-selector='assistant-insights-headline']").text).to include("说错 1 次", "被静音的规则 1 条")
      left_alone = page.at_css("[data-test-selector='assistant-insights-left-alone']").text
      expect(left_alone).to include("先不动或婉拒了 2 次", "撤销了它做的事 1 次")
      expect(page.at_css("[data-test-selector='assistant-insights-muted']").text)
        .to include(I18n.t("assistant.insights.detectors.wiki_stale.title", locale: :"zh-CN"))
      expect(page.at_css("[data-test-selector='assistant-insights-wrong']").text).not_to include("先不动")
    end

    it "does not list wrong things that concern work the reader cannot see" do
      hidden = create(:work_package, project: create(:project, enabled_module_names: %w[work_package_tracking assistant]))
      say!("stalled", outcome: "wrong", headline: "看不到的事", subject: hidden)
      Assistant::Signal.where(subject: hidden).update_all(project_id: project.id)

      get project_assistant_desk_path(project, tab: "insights")

      expect(page.text).not_to include("看不到的事")
      expect(page.text).to include("另有 1 条涉及你看不到的工作，没有列出。")
    end

    it "names what it kept to itself, with the reason, newest first and at most ten" do
      12.times { |i| say!("stalled", subject: create(:work_package, project:, subject: "第#{i}件"), gate: %w[early]) }
      say!("critical_slip", gate: %w[uncertain], told_at: 1.hour.ago)
      say!("wiki_stale", gate: [], told_at: 1.hour.ago)
      say!("commitment_ladder", gate: %w[cold_start], told_at: 30.minutes.ago)

      get project_assistant_desk_path(project, tab: "insights")

      held = page.at_css("[data-test-selector='assistant-insights-held']")
      expect(held.css("li").size).to eq(10)
      expect(held.text).to include("现在说还太早，只放进了简报", "不确定，只放进了简报", "还在熟悉期，先不打扰你")
    end

    def promise!(work_package:, quote: "我来联调", kind: "commitment", stated_at: 20.days.ago, **attributes)
      Assistant::Intent.create!(project:, kind:, status: "open", strength: "firm", title: quote,
                                quote: "原话里有 Ben 的名字", owner: sam, counterparty: ben, source: work_package,
                                subject: work_package, work_package:, stated_at:,
                                extractor_version: "test", **attributes)
    end

    it "names the firm promises that were broken without a word from it, by the work package's own date" do
      broken = create(:work_package, project:, subject: "没做完的事", due_date: 5.days.ago.to_date)
      warned = create(:work_package, project:, subject: "提醒过的事", due_date: 5.days.ago.to_date)
      promise!(work_package: broken, quote: "周三前我做完")
      promise!(work_package: warned, quote: "我也周三前做完")
      say!("stalled", subject: warned, told_at: 9.days.ago)

      get project_assistant_desk_path(project, tab: "insights")

      expect(page.text).to include("有 1 条坚定的承诺食言了，我事先一句话都没说过")
      missed = page.at_css("[data-test-selector='assistant-insights-missed']")
      expect(missed.text).to include("“周三前我做完”", "没做完的事")
      expect(missed.text).not_to include("提醒过的事")
      expect(missed.text).not_to include(sam.name, ben.name, "原话里有")
    end

    it "says there are none when promises were kept or still ahead" do
      promise!(work_package: create(:work_package, project:, due_date: 3.days.from_now.to_date))

      get project_assistant_desk_path(project, tab: "insights")

      expect(page.text).to include("没有我事先一句话都没说过的食言")
    end

    it "shows how much people still put in writing, and says without blame when it fell" do
      before_range = 45.days.ago
      comments = lambda do |count, at|
        ids = create_list(:work_package, count, project:).map(&:id)
        journals = Journal.where(journable_type: "WorkPackage", journable_id: ids)
        journals.update_all(notes: "评论", created_at: at)
      end
      comments.call(20, before_range)
      comments.call(20, 5.days.ago)
      10.times { |i| promise!(work_package: work_package, stated_at: before_range, quote: "上月 #{i}") }
      2.times { |i| promise!(work_package: work_package, stated_at: 5.days.ago, quote: "本月 #{i}") }

      get project_assistant_desk_path(project, tab: "insights")

      candour = page.at_css("[data-test-selector='assistant-insights-candour']").text
      expect(candour).to include("每一百条评论里，有 10 条写下了谁在什么时候之前做什么", "比上个月少了 40。人们开始不愿意把话写下来时，我就看不见了。")
    end

    it "does not show the honesty figure from too few comments" do
      get project_assistant_desk_path(project, tab: "insights")

      expect(page.at_css("[data-test-selector='assistant-insights-candour']").text).to include("样本太少", "不显示")
    end

    it "says plainly that nothing was held back" do
      get project_assistant_desk_path(project, tab: "insights")

      expect(page.at_css("[data-test-selector='assistant-insights-held']").text).to include("没有被挡下的事。")
    end

    it "never offers a form, and reads the same to a member who may not manage" do
      login_as(ben)
      get project_assistant_desk_path(project, tab: "insights")

      expect(response).to have_http_status(:ok)
      expect(page.css("form, button, input, select")).to be_empty
      expect(page.text).not_to match(/[A-Za-z]{3,}/)
    end
  end

  it "has a name for every rule it can talk about" do
    keys = Assistant::Proactive::Detectors.all.map(&:key)
    expect(keys).to all(satisfy { I18n.exists?("assistant.insights.detectors.#{it}.title", :"zh-CN") })
    expect(keys).to all(satisfy { I18n.exists?("assistant.insights.detectors.#{it}.what", :"zh-CN") })
  end
end
