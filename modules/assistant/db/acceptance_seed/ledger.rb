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
  class Ledger
    VERSION = "seed"

    def initialize(ctx)
      @ctx = ctx
    end

    def call
      intents
      extractions
      presence
      project_settings
      duties
    end

    def last_logins
      PEOPLE.each_key do |key|
        next if key == :quinn

        day = key == :ben && @ctx.today == @ctx.monday ? @ctx.d(-10) : @ctx.backward(@ctx.today - 1)
        user(key).update_columns(last_login_on: day)
      end
    end

    private

    def project = @ctx.project

    def user(key) = @ctx.user(key)

    def intents
      commitments
      decisions
      questions
    end

    def commitments
      say(:commitment, 88, :ben, :sam, "周四前我能给出接口文档", "给出接口文档", due: 3, expression: "周四前")
      say(:commitment, 69, :ben, :fiona, "周三前我把权限接口联调好", "联调好权限接口", due: 2, expression: "周三前")
      say(:commitment, 110, :sam, :fiona, "周三前能帮我确认一下吗", "确认评论通知的文案和交互", due: 2, expression: "周三前",
                                                                         strength: "requested")
      say(:commitment, 79, :bob, :sam, "今天修", "修复试用到期后配额检查不生效的问题", due: -7, expression: "今天", status: "done")
    end

    def decisions
      say(:decision, 69, :ben, nil, "权限分两层：知识库级和文档级", "权限分知识库级与文档级两层")
      say(:decision, 55, :bob, :ada, "路由先按成本、再按延迟排序", "模型路由先按成本、再按延迟排序")
      say(:decision, 99, :ada, nil, "扫描件先加界面提示，OCR 放到 v2.0 再做", "扫描件先加界面提示，OCR 放到 v2.0")
      say(:decision, 68, :fiona, nil, "用段落指纹来定位", "同名章节改用段落指纹定位")
      say(:decision, 102, :bob, :sam, "金额按 token 折算后四舍五入到分", "账单金额按 token 折算，四舍五入到分")
      say(:decision, 75, :ben, nil, "对账口径我先按 token 折算来做", "对账口径按 token 折算")
    end

    def questions
      say(:question, 69, :fiona, :ben, "文档级权限和知识库级权限冲突时，以哪一级为准？", "两级权限冲突时以哪一级为准")
      say(:question, 75, :sam, :ben, "退款发生时，对账流水要不要冲回？", "退款要不要冲回对账流水")
      say(:question, 68, :ada, :fiona, "跨文档的跳转要不要在新标签页打开？", "跨文档跳转是否新开标签页")
      say(:question, 79, :sam, :bob, "补丁要不要回灌到已经过期的老账号？", "补丁是否回灌过期老账号", status: "answered")
    end

    def say(kind, work_package_id, owner, counterparty, excerpt, title, due: nil, expression: nil, strength: "firm", status: nil)
      work_package = WorkPackage.find(work_package_id)
      journal = Journal.where(journable: work_package).where("notes LIKE ?", "%#{excerpt}%").order(:version).first!
      status ||= { "commitment" => "open", "decision" => "active", "question" => "open" }.fetch(kind.to_s)
      strength = "requested" if kind == :question
      Assistant::Intent.create!(
        project:, kind: kind.to_s, status:, strength:, title:, quote: quote_of(journal.notes, excerpt), owner: user(owner),
        counterparty: (user(counterparty) if counterparty), source: journal, subject: work_package, work_package:,
        said_due_expression: expression, said_due_on: (@ctx.backward(@ctx.d(due)) if due), stated_at: journal.created_at,
        resolved_at: (journal.created_at if status.in?(%w[done answered])), extractor_version: VERSION
      )
    end

    def quote_of(notes, excerpt)
      notes.split(/(?<=[。！？])/).find { it.include?(excerpt) }&.strip || excerpt
    end

    def extractions
      read = Journal.where(journable_type: "WorkPackage",
                           journable_id: WorkPackage.where(project:).select(:id)).where.not(notes: [
                                                                                              nil, ""
                                                                                            ])
      read.find_each do |journal|
        count = Assistant::Intent.where(source: journal).count
        Assistant::Extraction.create!(project:, source: journal, extractor_version: Assistant::Understanding::Prompt::VERSION,
                                      source_digest: Digest::SHA256.hexdigest(journal.notes), status: "succeeded", items_count: count,
                                      created_at: journal.created_at, updated_at: journal.created_at)
      end
    end

    def presence
      returned = @ctx.today == @ctx.monday
      before = @ctx.backward(@ctx.today - 1)
      PEOPLE.each_key do |key|
        next if key == :quinn

        last = key == :ben && returned ? @ctx.d(-10) : before
        Assistant::Preference.for(user(key)).update!(presence: { "today" => last.iso8601 })
      end
      Assistant::Preference.where(owner: user(:quinn)).update_all(presence: {})
    end

    def project_settings
      Assistant::Proactive::ProjectSettings.write!(project, lead_ids: [user(:sam).id])
    end

    def duties
      sam = user(:sam)
      Assistant::Duties::Defaults.ensure!(project, sam)
      Assistant::Duty.find_or_create_by!(project:, kind: "weekly_status") { it.delegator = sam }
      Assistant::Duty.where(project:).update_all(last_run_at: nil, last_result: {}, unseen_runs: 0)
    end
  end
end
