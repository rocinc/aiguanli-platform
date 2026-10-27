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

module AssistantSeed
  class Community
    def initialize(ctx)
      @ctx = ctx
    end

    def call
      ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL DEFERRED")
      Meetings.new(@ctx).call
      wiki
      forum
      news
      pull_requests
    end

    private

    def project = @ctx.project

    def wiki
      User.current = @ctx.user(:ada)
      pages = project.wiki.pages
      pages.where(title: ["提炼讨论要点 (document)", "侦察阻塞关系 (document)"]).destroy_all
      record = pages.find_by!(title: "决定记录")
      record.update!(text: decision_record)
      pages.find_each.with_index do |page, index|
        stamp = page == record ? @ctx.at(-5, "16:30") : @ctx.at(-30 - (index * 3 % 40), "15:00")
        @ctx.retime(page, stamp)
        page.update_columns(created_at: @ctx.at(-80, "10:00"), updated_at: stamp)
      end
    end

    def decision_record
      rows = [
        [-5, "权限只做知识库级和文档级两层，#69 的截止日顺延到本迭代末", "Sprint 6 周中同步会第 3 项、#69"],
        [-5, "模型路由先按成本、再按延迟排序", "#55"],
        [-10, "扫描件先在界面上提示，OCR 放到 v2.0 再做", "#62、#99"],
        [-10, "测试提前介入：开发完成当天就提测", "Sprint 5 回顾会"],
        [-17, "账单金额按 token 折算后四舍五入到分", "#102"]
      ]
      lines = rows.map { |day, what, basis| "| #{@ctx.day_label(@ctx.backward(@ctx.d(day)))} | #{what} | #{basis} |" }
      <<~TEXT
        # 决定记录

        团队做过的决定都记在这里：决定了什么、什么时候定的、依据在哪里。新成员可以先从这页读起。

        | 日期 | 决定 | 依据 |
        |---|---|---|
        #{lines.join("\n")}
      TEXT
    end

    def forum
      forum = project.forums.first
      added = Message.where(forum:, subject: ["导出 PDF 时中文字体缺失怎么处理？", "Sprint 6 约定：测试提前介入"])
      Message.where(parent_id: added.select(:id)).destroy_all
      added.destroy_all
      old = Message.where(forum:).order(:id).to_a
      stamps = [[-40, "10:00"], [-40, "14:30"], [-39, "09:15"], [-26, "11:00"], [-26, "16:00"], [-19, "10:30"], [-18, "09:00"]]
      old.zip(stamps).each do |message, (day, hm)|
        stamp = @ctx.at(day, hm)
        message.update_columns(created_at: stamp, updated_at: stamp)
        @ctx.retime(message, stamp)
      end
      Message.where(forum:).where(parent_id: nil).find_each do |topic|
        last = Message.where(parent_id: topic.id).maximum(:created_at)
        topic.update_columns(updated_at: last || topic.created_at)
      end
      add_topic(forum, :fiona, [-5, "16:20"], "导出 PDF 时中文字体缺失怎么处理？",
                "在没有安装中文字体的服务器上导出 PDF，中文会变成方框。是打包字体，还是让用户选择？有做过的同学吗？")
      topic = add_topic(forum, :sam, [-7, "10:00"], "Sprint 6 约定：测试提前介入",
                        "按上次回顾会的结论：开发完成当天就提测，缺陷不要攒到迭代末。状态用“测试中”，不要直接关闭。")
      add_reply(topic, :ada, [-7, "11:00"], "同意。评审会上我会按这个口径看完成情况。")
    end

    def add_topic(forum, key, (day, hm), subject, content)
      stamp = @ctx.at(day, hm)
      User.current = @ctx.user(key)
      Message.create!(forum:, author: @ctx.user(key), subject:, content:, created_at: stamp, updated_at: stamp)
    end

    def add_reply(topic, key, (day, hm), content)
      stamp = @ctx.at(day, hm)
      User.current = @ctx.user(key)
      reply = Message.create!(forum: topic.forum, parent: topic, author: @ctx.user(key), subject: "回复：#{topic.subject}", content:,
                              created_at: stamp, updated_at: stamp)
      topic.update_columns(updated_at: stamp)
      reply
    end

    def news
      items = News.where(project:)
      items.where(title: "Frank、Mia 借调到数据平台组").destroy_all
      sprint_news = ["Sprint 5 进入后半程", "Sprint 5 评审通过，商业化主链路进入内测"]
      {
        "v1.0 正式发布" => [-45, "10:00"],
        "团队扩充" => [-70, "10:00"],
        sprint_news => [-10, "18:00"]
      }.each do |title, (day, hm)|
        item = items.find_by!(title:)
        stamp = @ctx.at(day, hm)
        item.update_columns(created_at: stamp, updated_at: stamp)
        @ctx.retime(item, stamp)
      end
      items.find_by!(title: sprint_news).update_columns(
        title: "Sprint 5 评审通过，商业化主链路进入内测", summary: "计费主链路已打通，引用溯源与幻觉拦截通过评审。",
        description: "Sprint 5 评审会已通过：引用溯源、幻觉拦截和计费主链路全部完成，商业化版本进入内测。\n\n下一步是 Sprint 6：收尾用量统计与升级流程，v1.1 计划两周后发布。"
      )
      stamp = @ctx.at(-10, "18:30")
      User.current = @ctx.user(:sam)
      News.create!(project:, author: @ctx.user(:sam), title: "Frank、Mia 借调到数据平台组",
                   summary: "两位同事将借调到数据平台组，预计年底前回来。",
                   description: "Frank 和 Mia 从下周起借调到数据平台组，已承接的工作都已完成或交接。借调期间需要他们配合的事，请先找 Sam。",
                   created_at: stamp, updated_at: stamp)
    end

    def pull_requests
      return unless defined?(GithubPullRequest)

      merged(409, 62, "修复扫描版 PDF 解析为空的提示", @ctx.at(-19, "17:00"))
      merged(412, 94, "修复 DOCX 合并单元格解析丢失", @ctx.at(-4, "17:15"))
    end

    def merged(number, work_package_id, title, merged_at)
      pull = GithubPullRequest.create!(
        github_id: 9_000_000 + number, number:, github_html_url: "https://github.com/quill-team/quill-server/pull/#{number}",
        state: "closed", repository: "quill-team/quill-server", repository_html_url: "https://github.com/quill-team/quill-server",
        title:, body: "关联 OP##{work_package_id}", draft: false, merged: true, merged_at:, github_updated_at: merged_at,
        comments_count: 2, review_comments_count: 3, additions_count: 86, deletions_count: 21, changed_files_count: 4, labels: [],
        created_at: merged_at - 1.day, updated_at: merged_at
      )
      pull.work_packages << WorkPackage.find(work_package_id)
    end
  end

  class Meetings
    def initialize(ctx)
      @ctx = ctx
    end

    def call
      everyone = %i[sam ada fiona bob ben quinn]
      past = %i[sam ada fiona bob ben frank mia]
      build("Sprint 5 评审会", :sam, -10, "14:00", 60, :closed, past - %i[quinn], attended: past, items: [
              ["Sprint 5 完成情况", "完成 14 项，没有结转。", nil, 10],
              ["演示：引用溯源", nil, 64, 15],
              ["演示：幻觉拦截", nil, 65, 15]
            ], outcomes: { 1 => [:information, "引用溯源与幻觉拦截通过评审，进入内测。"] })
      build("Sprint 5 回顾会", :sam, -10, "15:30", 60, :closed, past, attended: past, items: [
              ["做得好", "引用溯源提前一天完成；评测集让回归更有底气。", nil, 15],
              ["待改进", "缺陷发现偏晚，测试应该更早介入。", nil, 15],
              ["行动项", "开发完成当天就提测，缺陷不要攒到迭代末。", nil, 15]
            ], outcomes: { 3 => [:decision, "测试提前介入：开发完成当天提测。"] })
      build("Sprint 6 计划会", :sam, -7, "09:30", 90, :closed, past - %i[quinn frank mia], attended: past - %i[quinn frank mia], items: [
              ["迭代目标", "商业化主链路收尾，v1.1 两周后发布。", nil, 10],
              ["容量与请假", "Ben 本周起休假一周；Frank、Mia 借调到数据平台组。", nil, 10],
              ["用量统计的排期与风险", nil, 73, 20],
              ["知识库权限的范围", nil, 69, 20]
            ], outcomes: {})
      build("Sprint 6 周中同步会", :sam, -5, "14:00", 30, :closed, everyone - %i[quinn], attended: everyone - %i[quinn ben], items: [
              ["进度与阻塞", "对账口径还在等财务确认。", nil, 10],
              ["用量统计的排期", nil, 73, 10],
              ["知识库权限范围收窄", nil, 69, 10]
            ], outcomes: { 3 => [:decision, "权限只做知识库级和文档级两层；#69 的截止日顺延到本迭代末。"] })
      build("Sprint 6 中期计划会", :sam, 0, "10:00", 60, :open, everyone, items: [
              ["用量统计第二次改期对 v1.1 的影响", nil, 73, 10],
              ["评论通知的文案与交互", nil, 110, 10],
              ["Quinn 入项与 5 个工作包交接", "Ben、Bob、Fiona、Frank 把背景讲给 Quinn。", nil, 15],
              ["多人同时编辑逾期的原因与补救", nil, 81, 10],
              ["Ben 回归后的安排", "#69、#88、#94 各自的下一步。", nil, 10]
            ], outcomes: {})
      build("待办梳理（Backlog Refinement）", :ada, 2, "15:00", 60, :open, everyone, items: [
              ["导出格式与优先级", nil, 83, 20],
              ["多知识库隔离的范围", nil, 71, 20],
              ["新进缺陷", "#91 章节衔接断裂、#93 PDF 表格错乱，需要确认负责人。", nil, 10]
            ], outcomes: {})
      build("Sprint 6 评审会", :sam, 4, "14:00", 60, :open, everyone, items: [
              ["演示：套餐升级与配额告警", nil, 74, 20],
              ["演示：会话管理", nil, 54, 15],
              ["v1.1 发布准备", nil, 116, 15]
            ], outcomes: {})
      build("Sprint 7 计划会", :sam, 7, "10:00", 90, :open, everyone, items: [
              ["迭代目标草案", "把商业化主链路收尾并发布 v1.1。", nil, 10]
            ], outcomes: {})
    end

    private

    def build(title, author_key, day, hm, minutes, state, invited, items:, outcomes:, attended: [])
      author = @ctx.user(author_key)
      User.current = author
      start = @ctx.at(day, hm)
      meeting = Meeting.new(project: @ctx.project, author:, title:, start_time: start, duration: minutes / 60.0, location: "线上会议")
      invited.each { |key| meeting.participants.build(user: @ctx.user(key), invited: true, attended: attended.include?(key)) }
      meeting.save!
      section = MeetingSection.create!(meeting:, title: "议程", position: 1)
      created = items.each_with_index.map do |(item_title, notes, work_package_id, length), index|
        MeetingAgendaItem.create!(meeting:, meeting_section: section, author:, title: (item_title unless work_package_id), notes:,
                                  position: index + 1, duration_in_minutes: length, work_package_id:,
                                  item_type: work_package_id ? :work_package : :simple)
      end
      outcomes.each do |position, (kind, text)|
        MeetingOutcome.create!(meeting_agenda_item: created.fetch(position - 1), kind:, notes: text, author:)
      end
      stamp = [start - 3.days, @ctx.at(-3, "10:00")].min
      meeting.update_columns(created_at: stamp, updated_at: stamp, state: Meeting.states.fetch(state.to_s))
      @ctx.retime(meeting, stamp, 1.minute)
    end
  end
end
