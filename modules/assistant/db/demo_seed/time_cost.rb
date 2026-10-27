# frozen_string_literal: true

require "yaml"

module DemoSeed
  # Time entries for S1-S6 (on top of the 122 from AssistantSeed::TimeLog), hourly rates, cost types,
  # the v1.1 / v2.0 budgets and a few cost entries.
  #
  # Rules
  # - catalog items: leaf tasks/bugs log exactly their catalog `actual`; a story logs only what exceeds the
  #   sum of its children (acceptance / glue work). A reviewer and Ada's acceptance are carved out of the
  #   item's own hours, so the item total never drifts from `actual`.
  # - Sprint 6 final week is a hand-written schedule (WEEK_PLAN) that matches the sentences in talk_now.rb.
  #   Bob / Ben / Fiona / Quinn leave the last Friday empty; the 3h Bob mentions on #73 (Tuesday) is not booked.
  # - Frank and Mia are on leave from M-9, Ben from M-7 to M-3; nobody logs on those days.
  class TimeCost
    include Support

    CATALOG = YAML.safe_load_file(File.expand_path("catalog.yml", __dir__), symbolize_names: true).freeze
    PEOPLE = AssistantSeed::PEOPLE
    ACT = { dev: AssistantSeed::ACTIVITIES[:development], test: AssistantSeed::ACTIVITIES[:testing],
            manage: AssistantSeed::ACTIVITIES[:manage], req: AssistantSeed::ACTIVITIES[:requirements] }.freeze

    SOFT_CAP = 7.5
    HARD_CAP = 9.5
    ADA_CAP = 3.5

    REVIEWER = { bob: :frank, frank: :bob, ben: :frank, fiona: :ben, mia: :frank, sam: :bob }.freeze
    DEV_NOTES = %w[编码实现 接口联调 自测与修正 补充单元测试 整理与重构 对接与联调].freeze
    TEST_NOTES = %w[自测与回归 补充测试用例 联调验证].freeze
    EPICS = [42, 57, 72, 80].freeze
    EPIC_NOTES = %w[需求梳理与优先级 验收与反馈 干系人沟通 待办梳理准备].freeze

    RATES = { ada: 300, sam: 260, frank: 360, bob: 260, ben: 280, fiona: 260, mia: 320, quinn: 160 }.freeze
    RAISES = { ben: 300, fiona: 280, mia: 340 }.freeze

    COST_TYPES = {
      outsource: { name: "外包测试（人天）", unit: "人天", rate: 2200 },
      cloud: { name: "云服务费用", unit: "元", rate: 1, default: true },
      gpu: { name: "GPU 卡时", unit: "卡时", rate: 14 },
      tokens: { name: "模型调用（百万 token）", unit: "百万 token", rate: 60 }
    }.freeze

    # day => [[work package, hours, activity, comment], ...]; day 0 is the Monday of the seeded week.
    WEEK_PLAN = {
      bob: {
        0 => [[73, 2.0, :dev, "扣减接口收尾，对账口径对齐"], [100, 2.0, :dev, "行级锁实现与自测"],
              [55, 1.5, :dev, "路由主逻辑收尾"], [104, 1.5, :dev, "幂等测试用例补充"]],
        1 => [[100, 2.0, :dev, "合并与并发 200 压测"], [100, 1.0, :test, "压测结果复核"],
              [104, 1.0, :test, "重复回调补测（30 秒、5 分钟间隔）"], [55, 1.5, :dev, "降级逻辑"]],
        2 => [[55, 2.0, :dev, "降级逻辑收尾"], [55, 3.0, :dev, "备用模型超时重试排查"],
              [89, 1.0, :test, "网关限流压测复核"], [73, 1.0, :dev, "退款冲回边界"]],
        3 => [[55, 1.5, :test, "提测前自测"], [73, 2.5, :dev, "退款冲回边界，尚未跑通"],
              [116, 1.5, :manage, "回滚方案草稿"], [100, 0.5, :dev, "灰度观察"]]
      },
      ben: {
        0 => [[94, 3.0, :dev, "回归样本：补 3 个合并单元格样本"], [69, 2.5, :dev, "权限接口设计落地"],
              [75, 1.0, :req, "回答退款冲回的问题"]],
        1 => [[94, 3.0, :dev, "合并单元格修复与回归样本"], [88, 1.5, :dev, "接口文档：限流返回码一节"],
              [69, 1.5, :dev, "接口骨架"]],
        2 => [[94, 3.0, :dev, "横向加纵向合并同时存在的样本一并修复"], [88, 1.5, :dev, "接口文档：分页参数"],
              [69, 1.5, :dev, "联调准备"]],
        3 => [[88, 2.0, :dev, "文档草稿，未完成"], [69, 2.0, :dev, "接口实现"], [56, 1.0, :req, "S7 续写任务准备"]]
      },
      fiona: {
        0 => [[86, 2.5, :dev, "归档搜索收尾"], [54, 1.0, :dev, "会话归档接口收尾"], [108, 3.0, :dev, "光标广播改为只发增量"],
              [110, 1.0, :dev, "站内通知接入"]],
        1 => [[108, 1.5, :test, "三人同时编辑复测"], [110, 2.5, :dev, "邮件通知"], [74, 1.5, :dev, "降级文案与说明"],
              [54, 0.5, :dev, "已归档会话的隐藏开关"], [87, 1.5, :dev, "标题自动生成"]],
        2 => [[87, 0.5, :dev, "标题截断规则"], [103, 2.0, :dev, "降级后权益回收"], [81, 2.5, :dev, "离线冲突选择界面"],
              [82, 1.5, :dev, "@ 候选列表"], [74, 1.0, :test, "升级流程走查"]],
        3 => [[82, 3.5, :dev, "@ 候选排序与提测"], [103, 1.5, :test, "回收用例 9 条"], [81, 1.5, :req, "#81 拆分草稿"],
              [90, 0.5, :dev, "降级占位文案"]]
      },
      quinn: {
        0 => [[68, 1.5, :test, "读 Fiona 的说明，开始同名章节回归"], [75, 1.5, :req, "读评论与财务口径，确认理解"],
              [98, 1.5, :dev, "接手评测集，样本分类"], [79, 1.0, :test, "接手，确认三个验证场景"]],
        1 => [[68, 2.0, :test, "同名章节回归与指纹碰撞补充用例"], [79, 2.5, :test, "试用到期与续费场景验证"],
              [98, 1.0, :dev, "32 篇样本分类"], [75, 0.5, :dev, "冲正流水数据模型草稿"], [99, 0.5, :dev, "开始写回归用例"]],
        2 => [[79, 1.0, :test, "降级场景验证"], [99, 3.0, :dev, "8 条回归用例"], [98, 1.0, :dev, "评测集补充"]],
        3 => [[98, 3.5, :dev, "补全问答对（11 篇不足 5 个）"], [75, 1.5, :dev, "按财务三条口径修改"],
              [99, 0.5, :test, "用例复跑"]]
      },
      sam: {
        0 => [[116, 1.0, :manage, "检查清单对账：12 项完成 6 项"], [200, 1.0, :manage, "迭代运转与阻碍清理"]],
        1 => [[116, 0.5, :manage, "清单更新"], [200, 1.0, :manage, "站会记录与风险登记"]],
        2 => [[116, 1.5, :manage, "清单补全至 12 项"], [200, 0.5, :manage, "迭代运转"]],
        3 => [[116, 1.0, :manage, "迁移演练排期"], [200, 1.5, :manage, "#69 移出迭代与决定记录"]],
        4 => [[116, 1.5, :manage, "Sprint 6 评审与回顾材料"], [200, 1.5, :manage, "Sprint 7 计划会准备"]]
      },
      ada: {
        0 => [[54, 0.5, :req, "验收：归档后搜索"], [74, 0.5, :req, "走查升级流程"], [73, 1.0, :req, "确认对账口径与提测日期"]],
        1 => [[104, 0.5, :req, "验收：幂等测试记录"], [68, 0.5, :req, "验收：同名章节回归"],
              [112, 1.0, :req, "页码与封面：需求澄清"]],
        2 => [[108, 0.5, :req, "验收：光标同步"], [74, 0.5, :req, "验收：套餐升级"], [79, 0.5, :req, "验收：试用到期"],
              [110, 0.5, :req, "验收：@ 通知"]],
        3 => [[94, 0.5, :req, "验收：合并单元格样本"], [89, 0.5, :req, "验收：限流返回"],
              [69, 0.5, :req, "确认 #69 范围挪出本迭代"], [81, 0.5, :req, "拆分草稿评估"]],
        4 => [[82, 0.5, :req, "验收：评论与提及"], [55, 0.5, :req, "验收：模型路由与降级"], [98, 0.5, :req, "评测集纪要脱敏"]]
      }
    }.freeze

    def call
      @plan = []
      @seq = 0
      @booked = Hash.new(0.0)
      @cap = ctx.backward(ctx.today - 1)
      clear_costs
      rates
      load_existing
      week_time
      meeting_time
      catalog_time
      legacy_time
      overhead_time
      crowd_bob
      persist
      costing
      say("time entries +#{@plan.size}, total #{TimeEntry.where(project_id: project.id).count}")
    end

    private

    def half(value) = (value * 2).round / 2.0

    def sprint_day(number, index)
      plan = CATALOG[:sprints].find { it[:name] == "Sprint #{number}" }
      ctx.d(plan[:from] + index + (index >= 5 ? 2 : 0))
    end

    def clear_costs
      Budget.where(project:).destroy_all
      CostEntry.where(project_id: project.id).destroy_all
      HourlyRate.where(project_id: project.id).delete_all
      CostType.where(name: COST_TYPES.values.pluck(:name)).destroy_all
    end

    def rates
      RATES.each { |key, rate| HourlyRate.create!(user: user(key), project:, valid_from: ctx.d(-100), rate:) }
      RAISES.each { |key, rate| HourlyRate.create!(user: user(key), project:, valid_from: ctx.d(-35), rate:) }
      Setting.costs_currency = "¥"
      Setting.costs_currency_format = "%u %n"
    end

    def load_existing
      TimeEntry.where(project_id: project.id).group(:user_id, :spent_on).sum(:hours).each do |(user_id, day), hours|
        key = PEOPLE.key(user_id)
        @booked[[key, day]] += hours if key
      end
    end

    def away?(key, date)
      case key
      when :ben then date.between?(ctx.d(-7), ctx.d(-3))
      when :frank, :mia then date >= ctx.d(-9)
      when :bob then date == ctx.d(-3)
      when :quinn then date < quinn_joined
      else false
      end
    end

    def quinn_joined
      @quinn_joined ||= Member.find_by(project:, principal: user(:quinn))&.created_at&.to_date || ctx.monday
    end

    def room(key, date, cap)
      return 0 if date > @cap || !ctx.weekday?(date) || away?(key, date)

      half(cap - @booked[[key, date]])
    end

    def add(key, date, hours, kind, entity, comment, span: nil, fixed: false)
      return if hours <= 0 || date > @cap || !ctx.weekday?(date)

      @booked[[key, date]] += hours
      @plan << { key:, date:, hours:, kind:, entity:, comment:, span:, fixed:, seq: (@seq += 1) }
    end

    def cap_for(key, level = SOFT_CAP) = key == :ada ? ADA_CAP : level

    # Fills days nearest to `days[index]` first: soft cap inside the item, then earlier days of the sprint,
    # then up to 9h inside the item, then 9.5h; whatever is left lands on the least loaded day.
    def place(key, days, index, hours, kind, entity, comment, span, sprint_days = days)
      left = hours
      earlier = sprint_days.select { it < days.first }
      passes = [[days, cap_for(key)], [earlier, cap_for(key)], [days, cap_for(key, 9.0)], [days, cap_for(key, HARD_CAP)]]
      passes.each do |candidates, cap|
        candidates.sort_by { [(it - days[index]).abs, it] }.each do |day|
          take = [room(key, day, cap), left].min
          next if take < 0.5

          add(key, day, take, kind, entity, comment, span:)
          left -= take
          return if left <= 0
        end
      end
      day = days.reject { away?(key, it) }.min_by { @booked[[key, it]] } || days.last
      add(key, day, left, kind, entity, comment, span:)
    end

    def split(hours, count, rng)
      chosen = hours <= 2 ? 1 : [(hours / 1.0).ceil, count].min
      indexes = chosen == 1 ? [count - 1] : (0...chosen).map { (it * (count - 1) / (chosen - 1.0)).round }.uniq
      weights = Array.new(indexes.size) { 0.75 + (rng.rand * 0.5) }
      sizes = weights.map { [half(hours * it / weights.sum), 0.5].max }
      sizes[sizes.index(sizes.max)] += hours - sizes.sum
      indexes.zip(sizes)
    end

    def catalog_rows = CATALOG[:history] + CATALOG[:sprint6_early]

    def own_hours(row)
      kids = catalog_rows.select { it[:parent] == row[:id] && it[:actual] }
      row[:actual] - kids.sum { it[:actual] }
    end

    def catalog_time
      catalog_rows.select { it[:actual] }.sort_by { [it[:sprint], it[:s], it[:id]] }.each do |row|
        hours = own_hours(row)
        next if hours < 0.5

        schedule(row, hours)
      end
    end

    def schedule(row, total)
      rng = Random.new(row[:id])
      key = row[:assignee].to_sym
      days = (row[:s]..row[:d]).map { sprint_day(row[:sprint], it) }
      sprint_days = (0..9).map { sprint_day(row[:sprint], it) }
      entity = wp(row[:id])
      span = days.first..days.last
      own = total

      review = total >= 4 ? [half(total * 0.12), 0.5].max.clamp(0.5, 1.5) : 0
      accept = %w[story bug].include?(row[:type]) && total >= 3 ? 0.5 : 0
      own -= review + accept
      if review.positive?
        reviewer = [REVIEWER.fetch(key), :bob, :frank, :sam].find { it != key && !away?(it, days.last) }
        place(reviewer, days, days.size - 1, review, :dev, entity, "代码评审", span, sprint_days)
      end
      place(:ada, days, days.size - 1, accept, :req, entity, "验收", span, sprint_days) if accept.positive?

      chunks = split(own, days.size, rng)
      chunks.each_with_index do |(index, hours), n|
        last = n == chunks.size - 1
        test = last && hours >= 1.5 ? (hours >= 3 ? 1.0 : 0.5) : 0
        place(key, days, index, hours - test, key == :sam ? :manage : :dev, entity, DEV_NOTES.sample(random: rng), span, sprint_days)
        place(key, days, index, test, :test, entity, TEST_NOTES.sample(random: rng), span, sprint_days) if test.positive?
      end
    end

    # Acceptance and review time on the Sprint 4-6 packages that AssistantSeed::TimeLog already booked for the assignee.
    def legacy_time
      AssistantSeed::WORK_PACKAGE_ROWS.select { it[:st] == :closed && it[:d] && it[:who] }.each do |row|
        day = ctx.backward(ctx.d(row[:d]))
        entity = wp(row[:id])
        place(:ada, [day], 0, 0.5, :req, entity, "验收", nil) if %i[story bug].include?(row[:ty])
        next unless row[:est].to_i >= 8

        reviewer = [REVIEWER.fetch(row[:who], :frank), :bob, :frank].find { it != row[:who] && !away?(it, day) }
        place(reviewer, [day], 0, 0.5, :dev, entity, "代码评审", nil)
      end
    end

    def overhead_time
      (-11..-1).each do |week|
        monday = ctx.d(week * 7)
        rng = Random.new(week + 100)
        [[1, 2.0], [3, 1.5]].each_with_index do |(offset, hours), n|
          epic = wp(EPICS[(week + n) % EPICS.size])
          add(:ada, monday + offset, hours, :req, epic, EPIC_NOTES.sample(random: rng))
        end
        add(:sam, monday + 2, 1.0, :manage, wp(200), "迭代运转：燃尽、阻碍与站会记录")
        add(:sam, monday, 1.0, :manage, wp(200), "迭代计划与待办维护")
      end
    end

    def meeting_time
      Meeting.where(project:).where(start_time: ...ctx.now).includes(:participants).find_each do |meeting|
        date = meeting.start_time.in_time_zone.to_date
        hours = [(meeting.duration.to_f * 4).round / 4.0, 0.5].max
        meeting.participants.select(&:attended).each do |participant|
          key = PEOPLE.key(participant.user_id)
          next if key.nil? || ((meeting.id + participant.user_id) % 8).zero? || unfilled?(key, date)
          next if away?(key, date) || @booked[[key, date]] + hours > 8.0

          kind = { sam: :manage, ada: :req }.fetch(key, :other)
          add(key, date, hours, kind, meeting, "参会：#{meeting.title}", fixed: true)
        end
      end
    end

    def unfilled?(key, date) = date == ctx.d(4) && %i[bob ben fiona quinn].include?(key)

    def week_time
      WEEK_PLAN.each do |key, days|
        days.each do |offset, rows|
          rows.each { |id, hours, kind, comment| add(key, ctx.d(offset), hours, kind, wp(id), comment, fixed: true) }
        end
      end
      add(:ben, ctx.d(-10), 1.5, :dev, wp(69), "权限设计：休假前收尾", fixed: true)
    end

    # "One day logged too much": Bob pulls neighbouring days of the same work packages into one day.
    def crowd_bob
      done = 0
      [1, 2, 3].each do |sprint|
        break if done == 2

        days = (0..9).map { sprint_day(sprint, it) }
        target = days.max_by { |day| @booked[[:bob, day]] + movable(day).sum { it[:hours] } }
        next if @booked[[:bob, target]] + movable(target).sum { it[:hours] } < 9.0

        movable(target).sort_by { (it[:date] - target).abs }.each do |entry|
          break if @booked[[:bob, target]] >= 9.5
          next if @booked[[:bob, target]] + entry[:hours] > 9.75

          @booked[[:bob, entry[:date]]] -= entry[:hours]
          @booked[[:bob, target]] += entry[:hours]
          entry[:date] = target
        end
        done += 1
      end
    end

    def movable(target)
      @plan.select do |e|
        e[:key] == :bob && !e[:fixed] && e[:date] != target && e[:span]&.cover?(target) && (e[:date] - target).abs <= 5
      end
    end

    def activity(entry)
      return ACT.fetch(entry[:kind]) unless entry[:kind] == :other

      @other_activity ||= TimeEntryActivity.find_by(name: "其他")&.id || ACT[:manage]
    end

    def persist
      order = PEOPLE.keys
      @plan.sort_by { [it[:date], order.index(it[:key]), it[:seq]] }.each do |e|
        user = user(e[:key])
        stamp = stamp_for(e)
        entry = TimeEntry.create!(project:, user:, logged_by: user, entity: e[:entity], hours: e[:hours], spent_on: e[:date],
                                  activity_id: activity(e), comments: e[:comment].to_s, created_at: stamp, updated_at: stamp)
        ctx.retime(entry, stamp, 1.minute)
      end
    end

    def stamp_for(entry)
      rng = Random.new(entry[:seq])
      stamp = if rng.rand < 0.15
                ctx.at(ctx.forward(entry[:date] + 1), "09:#{format('%02d', 5 + rng.rand(40))}")
              else
                ctx.at(entry[:date], "#{17 + rng.rand(2)}:#{format('%02d', rng.rand(55))}")
              end
      [stamp, ctx.now].min
    end

    def costing
      types = cost_types
      v11 = budget(name: "v1.1 商业化版预算", author: :ada, date: ctx.d(-36), types:,
                   labor: { ada: 6, sam: 12, bob: 40, fiona: 16, ben: 8, quinn: 12 },
                   material: [[:cloud, 9_000, "预发布与压测环境云资源"], [:gpu, 400, "压测占用推理 GPU"],
                              [:tokens, 50, "联调与压测的模型调用"], [:outsource, 5, "外包测试：支付、计费与发布前回归"]])
      v20 = budget(name: "v2.0 团队版预算", author: :ada, date: ctx.d(-20), types:,
                   labor: { ada: 120, sam: 160, bob: 220, fiona: 300, ben: 200, quinn: 120, frank: 40, mia: 40 },
                   material: [[:cloud, 60_000, "协同与权限测试环境、生产扩容"], [:gpu, 2_000, "检索评测与重排序实验"],
                              [:tokens, 400, "助理与续写的模型调用"], [:outsource, 30, "外包测试：协同、导出与兼容性"]])
      { 21 => v11, 22 => v20 }.each do |version_id, record|
        WorkPackage.where(project_id: project.id, version_id:).update_all(budget_id: record.id)
      end
      cost_entries(types)
      say("budgets v1.1 #{v11.budget.to_f} / v2.0 #{v20.budget.to_f}")
    end

    def cost_types
      COST_TYPES.transform_values do |spec|
        type = CostType.create!(name: spec[:name], unit: spec[:unit], unit_plural: spec[:unit], default: spec[:default] || false,
                                for_all_projects: true)
        CostRate.create!(cost_type: type, valid_from: ctx.d(-100), rate: spec[:rate])
        type
      end
    end

    def budget(name:, author:, date:, types:, labor:, material:)
      record = Budget.new(project:, author: user(author), subject: name, fixed_date: ctx.d(-35),
                          description: "人力按角色费率折算，物料为云服务、GPU、模型调用与外包测试。")
      labor.each { |key, hours| record.labor_budget_items.build(budget: record, user: user(key), hours:, comments: "") }
      material.each { |type, units, note| record.material_budget_items.build(budget: record, cost_type: types.fetch(type), units:, comments: note) }
      record.save!
      stamp = ctx.at(date, "10:00")
      record.update_columns(created_at: stamp, updated_at: stamp)
      ctx.retime(record, stamp, 1.day)
      record
    end

    def cost_entries(types)
      rows = [
        [89, :cloud, 4_200, :bob, ctx.d(2), "网关压测环境云资源（并发 200）"],
        [89, :gpu, 160, :bob, ctx.d(2), "限流压测占用推理 GPU"],
        [73, :tokens, 38, :bob, ctx.d(1), "用量统计联调的真实模型调用"],
        [116, :cloud, 3_600, :sam, ctx.d(-3), "预发布环境 9 月云账单分摊"],
        [116, :cloud, 2_900, :sam, ctx.d(3), "迁移演练环境临时扩容"],
        [79, :outsource, 3, :sam, ctx.d(1), "外包测试：试用到期与降级场景回归"],
        [104, :outsource, 2, :sam, ctx.d(-4), "外包测试：支付回调压力测试"],
        [116, :outsource, 2, :sam, ctx.d(3), "外包测试：发布前冒烟回归"],
        [81, :cloud, 2_600, :fiona, ctx.d(-6), "协同编辑服务压测环境"],
        [69, :cloud, 1_100, :bob, ctx.d(-5), "知识库权限测试环境"],
        [108, :outsource, 1, :sam, ctx.d(1), "外包测试：多人协同兼容性"],
        [202, :gpu, 240, :frank, sprint_day(1, 3), "内网 GPU 机器租用：部署与推理验证"],
        [219, :cloud, 1_800, :sam, sprint_day(1, 8), "监控与日志服务首月费用"],
        [243, :tokens, 60, :mia, sprint_day(3, 2), "三种嵌入模型召回对比的调用费用"],
        [61, :cloud, 3_000, :ben, ctx.d(-32), "向量库选型：三种向量库试用实例"]
      ]
      rows.each do |id, type, units, key, date, comment|
        next if date > @cap

        user = user(key)
        stamp = ctx.at(date, "17:30")
        entry = CostEntry.create!(project:, entity: wp(id), user:, logged_by: user, cost_type: types.fetch(type), units:,
                                  spent_on: date, comments: comment, created_at: stamp, updated_at: stamp)
        entry.update_columns(created_at: stamp, updated_at: stamp)
      end
    end
  end
end
