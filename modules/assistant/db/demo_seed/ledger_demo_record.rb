# frozen_string_literal: true

# rubocop:disable Layout/LineLength
module DemoSeed
  # What the assistant did and was told about it: receipts that really went through the action layer (and are dated
  # when they happened), plus the thirty days of notices behind the scorecard.
  class LedgerRecord
    Signals = Assistant::Understanding::Signals

    def initialize(ctx)
      @ctx = ctx
    end

    # Receipts: the pipeline's own entry points, fed the sentences the people wrote. Called after the runner cleared
    # Actions and before the sweep, so the sweep sees their effects (Bob's leave, for one).
    def receipts
      User.current = ctx.admin
      leave_receipt
      time_receipts
      pull_request_receipt
      action_item_receipt
    end

    def history
      NoticeHistory.new(ctx).call
    end

    # Two words already written for Sam, waiting for him to send them. They are
    # ordinary Propose actions, so the brief treats them like any other draft.
    def drafts
      [["#100 配额扣减并发超扣", 100, "@Bob Fischer「老账号一次性脚本，周日凌晨跑」进展如何？"],
       ["#104 支付回调幂等处理", 104, "@Bob Fischer「压测报告补到维基测试策略页」进展如何？"]].each do |title, wp_id, text|
        next unless WorkPackage.exists?(wp_id)

        locale_of(user(:sam)) do
          Assistant::Actions::Propose.call(
            kind: "reply_draft", title: "问 Bob：#{title}",
            steps: [{ "op" => "comment", "as" => "person", "type" => "WorkPackage", "id" => wp_id, "attributes" => { "notes" => text } }],
            on_behalf_of: user(:sam), project: ctx.project, auto_execute: false
          )
        end
      end
    rescue StandardError => e
      ctx.say("demo: drafts skipped: #{e.class} #{e.message.truncate(100)}")
    end

    # The weekly status duty is due on Fridays; the demo may be built on another
    # day, so it is run once here to give the brief a real status draft.
    def weekly_status
      duty = Assistant::Duty.find_by(project: ctx.project, kind: "weekly_status")
      return unless duty

      locale_of(user(:sam)) { Assistant::Duties::WeeklyStatus.new(duty).call }
    rescue StandardError => e
      ctx.say("demo: weekly status skipped: #{e.class} #{e.message.truncate(100)}")
    end

    private

    attr_reader :ctx

    def user(key) = ctx.user(key)

    def journal(wp, who, find)
      Journal.where(journable_type: "WorkPackage", journable_id: wp, user_id: AssistantSeed::PEOPLE.fetch(who))
             .where("notes LIKE ?", "%#{Journal.sanitize_sql_like(find)}%").order(:created_at).first
    end

    def locale_of(person, &) = OpenProject::LocaleHelper.with_locale_for(person, &)

    def backdate(action, executed_at, undone_at: nil)
      action.update_columns(created_at: executed_at - 3.seconds, updated_at: undone_at || executed_at, executed_at:)
      action.update_columns(undone_at:) if undone_at
    end

    def attempt(label)
      yield
    rescue StandardError => e
      ctx.say("demo: receipt skipped (#{label}): #{e.class} #{e.message.truncate(100)}")
      nil
    end

    # "我下周三起请假三天" -> the leave is booked, the receipt says so, and absence_ripple has something to find.
    def leave_receipt
      attempt("leave") do
        source = journal(73, :bob, "年假一个月前就批了") or return
        actions = locale_of(user(:bob)) do
          Signals.new(source, [{ "type" => "time_off", "certainty" => "certain", "quote" => "我这周三起请假三天（周三到周五）",
                                 "from" => { "kind" => "weekday", "value" => 3, "next_week" => false },
                                 "to" => { "kind" => "weekday", "value" => 5, "next_week" => false } }]).call
        end
        Array(actions).compact.each do |action|
          backdate(action, source.created_at + 20.seconds)
          UserNonWorkingTime.where(user_id: user(:bob).id).update_all(created_at: source.created_at + 20.seconds, updated_at: source.created_at + 20.seconds)
        end
      end
    end

    # "排查这个花了三小时" is logged for Bob and stays; Ben's "多花了一个半小时" is logged and Ben takes it back, because
    # the three hours he logged that day already include it.
    def time_receipts
      attempt("time spent") do
        source = journal(73, :bob, "排查这个花了三小时") or return
        made = locale_of(user(:bob)) { Signals.new(source, [time_signal("排查这个花了三小时", 3)]).call }
        Array(made).compact.each { backdate(it, source.created_at + 25.seconds) }
      end
      attempt("time spent undone") do
        source = journal(94, :ben, "多花了一个半小时") or return
        made = locale_of(user(:ben)) { Signals.new(source, [time_signal("多花了一个半小时", 1.5)]).call }
        Array(made).compact.each do |action|
          next unless action.executed?

          Assistant::Actions::Undo.call(action, user: user(:ben))
          backdate(action, source.created_at + 25.seconds, undone_at: source.created_at + 40.minutes)
        end
      end
    end

    def time_signal(quote, hours) = { "type" => "time_spent", "certainty" => "certain", "quote" => quote, "target" => "this", "hours" => hours }

    # PR #22 is titled OP#68 but is the fix for #79; Quinn confirms the link the assistant offered.
    def pull_request_receipt
      attempt("pull request") do
        pull = GithubPullRequest.find_by(number: 22) or return
        quinn = user(:quinn)
        source = journal(79, :quinn, "降级场景也测完了") or return
        action = locale_of(quinn) do
          Assistant::Actions::Propose.call(
            kind: "link_pull_request", title: I18n.t("assistant.duties.advance_merged_pr.link_title", number: pull.number, id: 79),
            steps: [{ "op" => "link_pull_request", "type" => "GithubPullRequest", "id" => pull.id, "attributes" => { "work_package_id" => 79 } }],
            on_behalf_of: quinn, project: ctx.project, subject: WorkPackage.find(79),
            basis: [Assistant::Basis.for(source, quote: "降级场景也测完了")], auto_execute: false
          )
        end
        next unless action.proposed?

        Assistant::Actions::Execute.call(action, decided_by: quinn)
        backdate(action.reload, source.created_at + 2.hours)
      end
    end

    # Sprint 5's retro left "评测集的持续维护" with nobody; Sam took it.
    def action_item_receipt
      attempt("action item") do
        item = MeetingAgendaItem.joins(:meeting).where(meetings: { project_id: ctx.project.id, title: "Sprint 5 回顾会" }, title: "本次行动项").first or return
        intents = Assistant::Intent.where(source: item, owner_id: nil)
        return if intents.empty?

        Assistant::Understanding::UnownedItems.offer(item, intents.to_a)
        signals = Assistant::Signal.where(detector: "meeting_unowned").where("payload ->> 'agenda_item_id' = ?", item.id.to_s)
        action = Assistant::Action.where(id: signals.flat_map { |s| s.options.filter_map { it["action_id"] } }, kind: "meeting_action_item")
                                  .detect { it.title.include?(user(:sam).name) } or return
        taken_at = ctx.at(0, "08:55")
        locale_of(user(:sam)) { Assistant::Actions::Execute.call(action, decided_by: user(:sam)) }
        backdate(action.reload, taken_at)
        signals.update_all(state: "dismissed", outcome: "adopted", outcome_at: taken_at, delivered_at: taken_at - 2.days, seen_at: taken_at - 1.day)
      end
    end
  end

  # The month behind the scorecard: notices already delivered and what came of each. The rows are written by hand,
  # because a past sweep cannot be rerun on today's data; they follow the people and work packages of the story.
  # Muted rules (Ada: calendar_crunch, Fiona: idle_capacity) are set before the sweep by LedgerDemo#mute_rules.
  class NoticeHistory
    MUTED = { ada: "calendar_crunch", fiona: "idle_capacity" }.freeze

    # who, detector, day (offset from Monday), time, subject, headline, outcome, days until the outcome, channel, act_by day
    ROWS = [
      [:sam, "sprint_planning_prep", -10, "15:10", [Meeting, "Sprint 6 计划会"], "Sprint 6 计划会：已排 31 点，余 4 点，3 项无人负责", "adopted", 3, "brief", -7],
      [:sam, "version_checkpoint", -7, "09:05", [Version, "v1.1 商业化版"], "v1.1 商业化版距发布 14 个工作日：完成 41%，2 项无人负责", "adopted", 0, "brief", 11],
      [:sam, "retro_follow_up", -11, "10:00", [Project, nil], "Sprint 5 回顾会明天开：上次说好的 2 件事还没有人做", "adopted", 1, "notification", -10],
      [:sam, "hours_over_estimate", -10, "09:30", [WorkPackage, 104], "#104 已记 15 小时，达估算的 125%，还需 4 小时", "ignored", 7, "notification", nil],
      [:sam, "recognition", -7, "16:05", [Project, nil], "三人答疑与维基编辑已汇总，可以在评审会上说", "adopted", 4, "brief", nil],
      [:sam, "idle_capacity", -8, "09:20", [WorkPackage, 101], "Sam 有 40 小时空档，#101 已 19 天无人负责，待指派", "rejected", 0, "brief", nil],
      [:ada, "calendar_crunch", -21, "09:10", [Project, nil], "本周可用 72 小时，排了 96 小时，涉及 6 个工作包", "ignored", 7, "brief", nil],
      [:ada, "calendar_crunch", -14, "09:10", [Project, nil], "本周可用 70 小时，排了 101 小时，涉及 7 个工作包", "rejected", 1, "brief", nil],
      [:ada, "calendar_crunch", -7, "09:10", [Project, nil], "本周可用 66 小时，排了 108 小时，涉及 8 个工作包", "muted", 0, "brief", nil],
      [:ada, "weak_decision", -13, "11:00", [WorkPackage, 65], "拦截阈值 9/30 维持现状，单人决定未引数据，待验证", "known", 0, "inline", nil],
      [:ada, "unanswered_forum_question", -9, "10:00", [Message, 222], "产品想法帖「长文生成前先给大纲确认」2 个工作日无回答，你负责过 #83", "adopted", 1, "brief", nil],
      [:ada, "meeting_prep", -5, "13:00", [Meeting, "Sprint 6 周中同步会"], "Sprint 6 周中同步会 70 分钟后开始：上次说好的 3 件事，1 件没人动", "adopted", 0, "notification", -5],
      [:bob, "commitment_ladder", -5, "09:15", [WorkPackage, 73], "答应 Sam 的「#73 联调」周四到期，余 18 小时无空档", "edited", 0, "notification", -4],
      [:bob, "hours_over_estimate", -4, "10:00", [WorkPackage, 100], "#100 已记 22 小时，达估算的 183%", "wrong", 1, "notification", nil],
      [:bob, "calendar_crunch", -7, "09:10", [Project, nil], "本周可用 40 小时，排了 52 小时，涉及 5 个工作包", "adopted", 1, "brief", -3],
      [:ben, "merged_not_advanced", 0, "09:10", [WorkPackage, 94], "PR #412 已合并 5 天，#94 还在“进行中”", "resolved", 2, "notification", nil],
      [:ben, "commitment_ladder", 1, "09:15", [WorkPackage, 88], "答应 Sam 的「#88 接口文档」周四到期，剩 24 小时，可用 12 小时", "rejected", 1, "notification", 3],
      [:ben, "stalled", -14, "09:15", [WorkPackage, 94], "#94 已 5 个工作日无动静，截止 9/30", "ignored", 7, "notification", nil],
      [:ben, "calendar_crunch", -7, "09:10", [Project, nil], "本周可用 38 小时，排了 62 小时，涉及 6 个工作包", "rejected", 0, "brief", nil],
      [:ben, "said_time_spent", 2, "10:21", [WorkPackage, 94], "记下了：#94 一个半小时", "undone", 0, "inline", nil],
      [:fiona, "stalled", -3, "10:00", [WorkPackage, 81], "#81 已 6 个工作日无变动，截止 10/9", "wrong", 0, "notification", nil],
      [:fiona, "commitment_ladder", -5, "09:20", [WorkPackage, 110], "答应 Sam 的「评论通知联调」周三到期，可用 14 小时需 12 小时", "adopted", 1, "notification", -3],
      [:fiona, "idle_capacity", -12, "09:20", [Project, nil], "Fiona 有 24 小时空档，#101 无人负责", "muted", 0, "brief", nil],
      [:quinn, "assigned_with_history", 0, "08:42", [WorkPackage, 68], "你接手 #68：2 个决定、Ada 的问题还没定", "adopted", 0, "inline", nil],
      [:quinn, "assigned_with_history", 0, "08:43", [WorkPackage, 75], "你接手 #75：5 个决定，口径还在等财务", "adopted", 0, "inline", nil],
      [:quinn, "assigned_with_history", 0, "08:44", [WorkPackage, 79], "你接手 #79：13 条评论，Bob 的补丁已合并", "adopted", 0, "inline", nil],
      [:quinn, "assigned_with_history", 0, "08:45", [WorkPackage, 98], "你接手 #98：9 条评论，Frank 已整理 32 篇", "adopted", 1, "inline", nil],
      [:quinn, "assigned_with_history", 0, "08:46", [WorkPackage, 99], "你接手 #99：用例在上面，不够的再补", "known", 0, "inline", nil]
    ].freeze

    # Said to nobody, and why: recipient, detector, day, subject, headline, the gate that held it back
    HELD = [
      [:fiona, "stalled", 1, [WorkPackage, 109], "#109 离线合并 5 个工作日无动静，可能在 #81 里一起做", "uncertain"],
      [:sam, "third_reschedule", 2, [WorkPackage, 73], "#73 的截止日已改过 2 次，第三次改期前先问一句", "early"],
      [:ben, "commitment_ladder", 3, [Project, nil], "周一前要给 #88 的日期，又要重估 #56 #92，手上的时间来不及", "too_late"],
      [:bob, "idle_capacity", 4, [Project, nil], "Bob 周三起休假三天，#97 无人接，但手上已满", "cannot_act"]
    ].freeze

    def initialize(ctx)
      @ctx = ctx
    end

    def call
      made = ROWS.each_with_index.filter_map { |row, index| write(row, index) }
      held = HELD.each_with_index.filter_map { |row, index| write_held(row, index) }
      ctx.say("demo: notice history #{made.size} delivered, #{held.size} held back")
    end

    private

    attr_reader :ctx

    def write(row, index)
      who, detector, day, hm, (klass, id), headline, outcome, after, channel, act_by = row
      return unless I18n.exists?("assistant.insights.detectors.#{detector}.title")

      at = ctx.at(day, hm)
      done_at = outcome_time(at, after)
      subject = lookup(klass, id)
      action = undone_action if outcome == "undone"
      Assistant::Signal.create!(
        detector:, fingerprint: "history|#{index}", recipient: ctx.user(who), project: ctx.project, subject:, action:,
        channel:, state: outcome == "ignored" ? "expired" : "dismissed", score: 30, deliver_at: at, delivered_at: at, seen_at: seen_at(outcome, at),
        outcome:, outcome_at: done_at, created_at: at, updated_at: done_at,
        payload: { "headline" => headline, "because" => [], "nature" => "own", "certainty" => "fact", "options" => [],
                   "gate" => [], "facts" => ({ "act_by" => ctx.at(act_by, "09:00").to_date.iso8601 } if act_by) || {} }
      )
    rescue StandardError => e
      ctx.say("demo: history row #{index} skipped: #{e.class} #{e.message.truncate(80)}")
      nil
    end

    def write_held(row, index)
      who, detector, day, (klass, id), headline, reason = row
      return unless I18n.exists?("assistant.insights.detectors.#{detector}.title")

      at = ctx.at(day, "09:12")
      Assistant::Signal.create!(
        detector:, fingerprint: "held|#{index}", recipient: ctx.user(who), project: ctx.project, subject: lookup(klass, id), channel: "brief",
        state: "held", score: 0, deliver_at: at, created_at: at, updated_at: at,
        payload: { "headline" => headline, "because" => [], "nature" => "own", "certainty" => "likely", "options" => [], "gate" => [reason], "pooled" => true, "facts" => {} }
      )
    rescue StandardError => e
      ctx.say("demo: held row #{index} skipped: #{e.class} #{e.message.truncate(80)}")
      nil
    end

    def lookup(klass, id)
      return if id.nil?
      return klass.find_by(id:) unless id.is_a?(String)

      klass == Version ? klass.find_by(name: id) : klass.find_by(project_id: ctx.project.id, title: id)
    end

    def outcome_time(at, after) = [at + after.days + 2.hours, ctx.now - 1.hour].min

    def seen_at(outcome, at) = outcome == "ignored" ? at + 20.minutes : at + 30.minutes

    def undone_action = Assistant::Action.where(status: "undone").order(:id).last
  end
end
# rubocop:enable Layout/LineLength
