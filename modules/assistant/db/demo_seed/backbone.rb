# frozen_string_literal: true

require "yaml"

module DemoSeed
  # Sprint 1-3 history, the backlog pool, story points, the Sprint 6 finish and the version/milestone
  # scaffolding. Everything it creates is declared in catalog.yml.
  class Backbone
    include Support

    CATALOG = YAML.safe_load_file(File.expand_path("catalog.yml", __dir__), symbolize_names: true).freeze
    STATUS = AssistantSeed::STATUSES.merge(failed: 11).freeze
    BUCKETS = { refinement: "待打磨 (Refinement)", next_up: "下一迭代 (Next Up)", icebox: "Icebox（暂缓）" }.freeze
    FAILING_TESTS = [205, 221, 226, 245, 253].freeze
    HIGH_PRIORITY = [213, 330, 334, 335].freeze
    NEW_VERSION = "v0.9"
    RETENTION_DRAFT = "对话历史默认保留 90 天，到期后自动删除。"
    RETENTION_REVISED = "对话历史按套餐保留：试用 30 天、标准 90 天、旗舰 365 天；到期后先归档，管理员可导出，不再自动删除。"

    def call
      @rows = (CATALOG[:history] + CATALOG[:sprint6_early] + CATALOG[:backlog]).index_by { it[:id] }
      version
      sprints
      story_points
      leave_sprint_six
      ordered_rows.each { |row| play(row, steps_for(row)) }
      finish_sprint_six
      relations
      derive_ancestors
      close_version
      reset_sequence
      verify
    end

    private

    def sprint_plan = @sprint_plan ||= CATALOG[:sprints].to_h { [it[:name][/\d+/].to_i, it] }

    def day(sprint, index) = sprint_plan.fetch(sprint)[:from] + index + (index >= 5 ? 2 : 0)

    def slot(row, index, hm) = ctx.at(day(row[:sprint], index), hm)

    def who(row) = row[:assignee]&.to_sym

    def planner(row) = %w[epic feature story].include?(row[:type]) ? :ada : :sam

    def ordered_rows = @rows.values.sort_by { [depth(it), it[:id]] }

    def depth(row) = @rows[row[:parent]] ? 1 + depth(@rows[row[:parent]]) : 0

    def children(row) = @rows.values.select { it[:parent] == row[:id] }

    def span(row)
      kids = children(row).select { it[:sprint] == row[:sprint] }.map { span(it) }
      [[row[:s], *kids.map(&:first)].min, [row[:d], *kids.map(&:last)].max]
    end

    # ---- scaffolding ----

    def version
      @version = Version.create!(project:, name: "v0.9 内部预览版", description: "S1–S3 的内部预览，推理服务、文档解析与向量检索基线。",
                                 status: "open", sharing: "none", start_date: ctx.d(-77), effective_date: ctx.d(-38))
      @version.update_columns(created_at: ctx.at(-80, "10:00"), updated_at: ctx.at(-80, "10:00"))
    end

    def close_version = @version.update!(status: "closed")

    def version_id(ref) = ref == NEW_VERSION ? @version.id : ref

    def sprints
      [1, 2, 3].each do |number|
        plan = sprint_plan.fetch(number)
        sprint = Sprint.create!(project:, name: plan[:name], start_date: ctx.d(plan[:from]), finish_date: ctx.d(plan[:to]),
                                status: "completed", started_at: ctx.at(plan[:from], "09:30"),
                                completed_at: ctx.at(plan[:to], "17:30"))
        SprintGoal.create!(sprint:, project:, text: plan[:goal])
      end
      (4..7).each { |number| rewrite_goal(number, sprint_plan.fetch(number)[:goal]) }
    end

    def rewrite_goal(number, text)
      sprint = Sprint.find_by!(project:, name: "Sprint #{number}")
      SprintGoal.find_or_initialize_by(sprint:, project:).update!(text:)
    end

    def sprint_id(number) = (@sprint_ids ||= {})[number] ||= Sprint.find_by!(project:, name: "Sprint #{number}").id

    def bucket_id(key) = (@bucket_ids ||= {})[key] ||= BacklogBucket.find_by!(project:, name: BUCKETS.fetch(key)).id

    # ---- changes to the pre-existing #42-#121 ----

    def story_points
      CATALOG[:existing][:points].each_value do |group|
        group.each { |id, points| patch(id, story_points: points) }
      end
    end

    def leave_sprint_six
      patch(69, sprint_id: nil, backlog_bucket_id: bucket_id(:next_up))
      patch(81, sprint_id: nil, backlog_bucket_id: bucket_id(:refinement))
      patch(112, sprint_id: sprint_id(7))
      [69, 81, 112].each do |id|
        wp = WorkPackage.find(id)
        siblings = WorkPackage.where(project_id: project.id, sprint_id: wp.sprint_id, backlog_bucket_id: wp.backlog_bucket_id).where.not(id:)
        wp.update_columns(position: siblings.maximum(:position).to_i + 1)
      end
    end

    # Writes the columns on the work package and on every one of its journals, so history stays consistent.
    def patch(id, attributes)
      WorkPackage.find(id).update_columns(attributes)
      data_ids = Journal.where(journable_type: "WorkPackage", journable_id: id, data_type: Journal::WorkPackageJournal.name).pluck(:data_id)
      Journal::WorkPackageJournal.where(id: data_ids).find_each { it.update_columns(attributes) }
    end

    def finish_sprint_six
      limit = ctx.now - 30.minutes
      CATALOG[:existing][:s6_final_week].each { |id, moves| play_existing(id, moves.map { |day, status| [day, status.to_sym] }, limit) }
      CATALOG[:existing][:s6_progress].each do |id, moves|
        play_existing(id, moves.map { |day, remaining| [day, remaining] }, limit)
      end
    end

    EXISTING_HOURS = { doing: "09:40", devdone: "11:30", testing: "10:30", closed: "11:10" }.freeze

    def play_existing(id, moves, limit)
      wp = WorkPackage.find(id)
      last = Journal.where(journable_type: "WorkPackage", journable_id: id).maximum(:created_at)
      moves.each do |day, change|
        hm = change.is_a?(Symbol) ? EXISTING_HOURS.fetch(change) : "15:00"
        hm = "16:20" if change == :closed && wp.type_id == AssistantSeed::TYPES[:story]
        at = [ctx.at(day, hm), last + 7.minutes].max
        at = [at, limit].min
        set = change.is_a?(Symbol) ? { status: change } : { rem: change }
        set[:rem] = 0 if %i[devdone testing closed].include?(change)
        actor = change == :closed ? closer(wp) : AssistantSeed::PEOPLE.key(wp.assigned_to_id)
        write(wp, at, actor, set)
        last = at
      end
    end

    def closer(wp) = wp.type_id == AssistantSeed::TYPES[:story] ? :ada : :sam

    # ---- timelines ----

    def steps_for(row)
      return backlog_steps(row) if CATALOG[:backlog].include?(row)

      case row[:type]
      when "epic" then epic_steps(row)
      when "feature" then feature_steps(row)
      when "story" then story_steps(row)
      when "bug" then bug_steps(row)
      else task_steps(row)
      end
    end

    def born(row)
      (@born ||= {})[row[:id]] ||= begin
        at = initial_time(row)
        parent = @rows[row[:parent]]
        parent ? [at, born(parent) + 10.minutes].max : at
      end
    end

    def initial_time(row)
      return ctx.at(row[:born], "09:10") if row[:born] && row[:sprint].nil?
      return ctx.at(row[:born], "16:20") if row[:born]

      sprint = row[:sprint]
      first = sprint == 1
      case row[:type]
      when "feature" then first ? slot(row, 0, "08:20") : ctx.at(day(sprint, 0) - 6 - (row[:id] % 3), "09:10")
      when "story" then first ? slot(row, 0, "08:35") : ctx.at(day(sprint, 0) - 3 - (row[:id] % 3), "09:30")
      else
        s = span(row).first
        s.zero? ? slot(row, 0, "08:50") : slot(row, s - 1, "14:10")
      end
    end

    def clear_time(row)
      return slot(row, 0, "09:00") if row[:sprint] == 1

      ctx.at(day(row[:sprint], 0) - 2 - (row[:id] % 2), "10:05")
    end

    def creation(row) = { at: born(row), who: planner(row), create: true }

    def planned(row)
      s, d = span(row)
      { status: row[:type] == "bug" ? :confirmed : :planned, who: who(row), ver: version_id(row[:version]), sprint: row[:sprint],
        est: row[:est], rem: row[:est], points: row[:points], prio: (:high if HIGH_PRIORITY.include?(row[:id])),
        start: ctx.d(day(row[:sprint], s)), due: ctx.d(day(row[:sprint], d)) }.compact
    end

    def started(row) = { at: slot(row, span(row).first, span(row).first.zero? ? "13:30" : "09:40"), who: who(row), set: { status: :doing, rem: row[:est] } }

    def epic_steps(row)
      stamp = ctx.at(row[:born], "09:10")
      [creation(row), { at: stamp + 30.minutes, who: :ada, set: { status: :clear } },
       { at: stamp + 70.minutes, who: :ada, set: { status: :planned, who: :sam } },
       { at: stamp + 110.minutes, who: :ada, set: { status: :doing } }] + infra_notes(row)
    end

    INFRA_SCOPE = [[-6, "10:30", "流水线、监控、日志与开发环境，让团队每次合并都有底。S6 起技术债（统一错误码、前端依赖升级、推理运行时升级、旧会话数据清理）归入本史诗，见 #336–#339。"],
                   [3, "16:10", "流水线、监控、日志与开发环境，让团队每次合并都有底。技术债条目已按价值排序，其中前端依赖升级排在下一迭代，其余暂缓；Sam 每个迭代回顾时复核一次。"]].freeze

    def infra_notes(row)
      return [] unless row[:id] == 200

      limit = ctx.now - 30.minutes
      INFRA_SCOPE.map { |day, hm, desc| { at: [ctx.at(day, hm), limit].min, who: :sam, set: { desc: } } }
    end

    def feature_steps(row)
      s, d = span(row)
      [creation(row), { at: clear_time(row), who: :ada, set: { status: :clear } },
       { at: slot(row, 0, "11:00"), who: :ada, set: planned(row).merge(status: :planned) },
       { at: slot(row, s, s.zero? ? "13:40" : "09:30"), who: who(row), set: { status: :doing } },
       { at: slot(row, d, "17:50"), who: :ada, set: { status: :closed } }]
    end

    def story_steps(row)
      s, d = span(row)
      steps = [creation(row), { at: clear_time(row), who: :ada, set: { status: :clear } },
               { at: slot(row, 0, "11:05"), who: :ada, set: planned(row) }, started(row)]
      steps.concat(FAILING_TESTS.include?(row[:id]) ? failing_tail(row, s, d) : passing_tail(row, s, d))
      steps << { at: slot(row, d, "16:40"), who: :ada, set: { status: :closed, rem: 0 } }
    end

    def passing_tail(row, start, finish)
      tail = []
      tail << { at: slot(row, (start + finish) / 2, "14:20"), who: who(row), set: { rem: (row[:est] * 0.4).round } } if finish - start >= 3
      built = [start, finish - 2].max
      tail << { at: slot(row, built, "11:20"), who: who(row), set: { status: :devdone, rem: 0 } }
      tail << { at: slot(row, [built, finish - 1].max, "14:10"), who: who(row), set: { status: :testing, rem: 0 } }
    end

    def failing_tail(row, start, finish)
      first = [start, finish - 3].max
      second = [first, finish - 2].max
      [{ at: slot(row, first, "14:10"), who: who(row), set: { status: :testing, rem: 0 } },
       { at: slot(row, second, "15:30"), who: :sam, set: { status: :failed, rem: 2 } },
       { at: slot(row, [second, finish - 1].max, "10:30"), who: who(row), set: { status: :testing, rem: 0 } }]
    end

    def bug_steps(row)
      s, d = span(row)
      stamp = born(row)
      early = { at: stamp + 25.minutes, who: :sam, set: planned(row) }
      [creation(row), early, started(row)] + passing_tail(row, s, d) +
        [{ at: slot(row, d, "15:50"), who: :sam, set: { status: :closed, rem: 0 } }]
    end

    def task_steps(row)
      s, d = span(row)
      built = [s, d - 1].max
      [creation(row), { at: born(row) + 12.minutes, who: who(row), set: planned(row) }, started(row),
       { at: slot(row, built, "11:20"), who: who(row), set: { status: :devdone, rem: 0 } },
       { at: slot(row, d, "15:20"), who: :sam, set: { status: :closed, rem: 0 } }]
    end

    # ---- backlog pool ----

    def backlog_steps(row)
      return milestone_steps(row) if row[:type] == "milestone"
      return forgotten_decision_steps(row) if row[:id] == 313

      author = row[:author]&.to_sym || :ada
      stamp = ctx.at(row[:born], "10:20")
      steps = [{ at: stamp, who: author, create: true }]
      steps << estimate_step(row, row[:born] + 1) if row[:points] || row[:est]
      path(row).each_with_index do |status, index|
        steps << { at: ctx.at([row[:born] + 2 + (2 * index), -3].min, "11:00"), who: :ada, set: { status:, who: who(row), ver: version_id(row[:version]) }.compact }
      end
      steps << { at: steps.last[:at] + 20.minutes, who: :sam, set: { bucket: row[:bucket].to_sym } } if row[:bucket]
      steps << retention_revision(row) if row[:edited_after_decision]
      steps
    end

    def path(row)
      case row[:status]
      when "clarifying" then [:clarifying]
      when "clear" then %i[clarifying clear]
      when "backlog" then %i[clarifying clear backlog]
      when "confirmed" then row[:type] == "bug" ? [:confirmed] : (row[:type] == "story" ? %i[clarifying clear confirmed] : %i[clarifying confirmed])
      else []
      end
    end

    def estimate_step(row, offset)
      { at: ctx.at([offset, -3].min, "15:30"), who: who(row) || :ada,
        set: { points: row[:points], est: row[:est], rem: row[:est], prio: (:high if HIGH_PRIORITY.include?(row[:id])) }.compact }
    end

    def milestone_steps(row)
      date = ctx.forward(ctx.d(row[:due]))
      [{ at: ctx.at(row[:born], "10:20"), who: :sam, create: true, set: { who: who(row), ver: version_id(row[:version]), start: date, due: date } }]
    end

    # Fiona proposed and confirmed this on a Sunday (M-29, 13 September in the demo calendar); nothing happened since.
    def forgotten_decision_steps(row)
      stamp = ctx.at(ctx.d(row[:born]), "10:12")
      [{ at: stamp, who: :fiona, create: true },
       { at: stamp + 25.minutes, who: :fiona,
         set: { status: :confirmed, who: :ada, points: row[:points], est: row[:est], rem: row[:est], bucket: :refinement } }]
    end

    def retention_revision(row)
      { at: ctx.at(row[:edited_after_decision], "16:20"), who: :ada, set: { desc: RETENTION_REVISED, est: 16, rem: 16 } }
    end

    # ---- playing steps ----

    def play(row, steps)
      last = nil
      steps.each do |step|
        at = last ? [step[:at], last + 7.minutes].max : step[:at]
        if step[:create]
          User.current = ctx.user(step[:who])
          create(row, step, at)
        else
          write(WorkPackage.find(row[:id]), at, step[:who], step[:set])
        end
        last = at
      end
    end

    def create(row, step, at)
      description = row[:id] == 340 ? RETENTION_DRAFT : row[:desc]
      wp = WorkPackage.new(project:, type_id: AssistantSeed::TYPES.fetch(row[:type].to_sym), status_id: STATUS[:new],
                           priority_id: AssistantSeed::PRIORITIES[:normal], author: ctx.user(step[:who]), subject: row[:subject],
                           description:, parent_id: row[:parent], schedule_manually: true)
      wp.id = row[:id]
      wp.created_at = wp.updated_at = at
      assign(wp, step[:set] || {})
      wp.save!
    end

    def write(wp, at, actor, set)
      User.current = actor == :assistant ? AssistantUser.first : ctx.user(actor)
      assign(wp, set)
      wp.updated_at = at
      wp.save!
    end

    def assign(wp, set)
      set.each do |key, value|
        case key
        when :who then wp.assigned_to_id = AssistantSeed::PEOPLE.fetch(value)
        when :status then wp.status_id = STATUS.fetch(value)
        when :prio then wp.priority_id = AssistantSeed::PRIORITIES.fetch(value)
        when :ver then wp.version_id = value
        when :sprint then wp.sprint_id = sprint_id(value)
        when :bucket then wp.backlog_bucket_id = bucket_id(value)
        when :points then wp.story_points = value
        when :start then wp.start_date = value
        when :due then wp.due_date = value
        when :est then wp.estimated_hours = value
        when :rem then wp.remaining_hours = value
        when :desc then wp.description = value
        end
      end
      wp.done_ratio = percent(wp)
    end

    def percent(wp)
      return 100 if wp.status_id == STATUS[:closed]
      return 0 unless wp.estimated_hours&.positive? && wp.remaining_hours

      (100 * (wp.estimated_hours - wp.remaining_hours) / wp.estimated_hours).round.clamp(0, 100)
    end

    # ---- relations, roll-up, checks ----

    def relations
      CATALOG[:relations].each do |from, to, kind|
        next if Relation.exists?(from_id: from, to_id: to) || Relation.exists?(from_id: to, to_id: from)

        Relation.create!(from_id: from, to_id: to, relation_type: kind, lag: 0)
      end
    end

    def derive_ancestors
      parent_ids = WorkPackage.where(project:).where.not(parent_id: nil).distinct.pluck(:parent_id)
      level = ->(id) { (parent = WorkPackage.where(id:).pick(:parent_id)) ? 1 + level.(parent) : 0 }
      parent_ids.sort_by { -level.(it) }.each do |parent_id|
        parent = WorkPackage.find(parent_id)
        parent.update_columns(derived_values(WorkPackage.where(parent_id:).to_a, parent))
      end
    end

    def derived_values(kids, parent)
      est = kids.sum { it.derived_estimated_hours || it.estimated_hours || 0 }
      rem = kids.sum { it.derived_remaining_hours || it.remaining_hours || 0 }
      starts = kids.filter_map(&:start_date)
      dues = kids.filter_map(&:due_date)
      { derived_estimated_hours: est.positive? ? est : nil, derived_remaining_hours: est.positive? ? rem : nil,
        derived_done_ratio: est.positive? ? (100 * (est - rem) / est).round : nil,
        start_date: starts.min || parent.start_date, due_date: dues.max || parent.due_date }
    end

    def reset_sequence
      ActiveRecord::Base.connection.execute("SELECT setval('work_packages_id_seq', (SELECT MAX(id) FROM work_packages))")
    end

    def verify
      closed = Status.find(STATUS[:closed]).id
      velocity = ->(number) { WorkPackage.where(sprint_id: sprint_id(number)).sum(:story_points) }
      done = ->(number) { WorkPackage.where(sprint_id: sprint_id(number), status_id: closed).sum(:story_points) }
      (1..6).each do |number|
        expected = sprint_plan.fetch(number)[:velocity]
        say("sprint #{number}: committed #{velocity.(number)}, done #{done.(number)} (expected #{expected})")
        say("sprint #{number} velocity mismatch") unless done.(number) == expected
      end
      say("backbone work packages: #{@rows.size} created, project total #{WorkPackage.where(project:).count}")
    end
  end
end
