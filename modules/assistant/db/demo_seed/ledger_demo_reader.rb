# frozen_string_literal: true

require_relative "ledger_demo_table"

# rubocop:disable Layout/LineLength
module DemoSeed
  # Turns LedgerTable into Intents. Rows marked `model: true` go through the real reader (the language model) with a
  # time budget; anything that fails, times out or disagrees with the row falls back to the row, so the seed never
  # depends on the model and never fails because of it.
  class LedgerReader
    MODEL_BUDGET = 12.minutes
    MAX_MODEL_FAILURES = 3
    RULE_VERSION = "seed"

    Row = Data.define(:kind, :wp, :who, :find, :title, :opts, :journal)

    attr_reader :report

    def initialize(ctx, use_model: ENV["LEDGER_DEMO_MODEL"] != "0")
      @ctx = ctx
      @use_model = use_model && Assistant::Llm.configured?
      @report = Hash.new(0)
      @model_failures = 0
      @started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @missing = []
    end

    def call
      rows = resolve(LedgerTable.rows)
      without_event_listeners do
        rows.sort_by { it.journal.created_at }.each { read(it) }
      end
      link_parents(rows)
      settle_acceptance_ledger
      retention_decisions
      meeting_items
      history_action_items
      mark_every_comment_read
      @ctx.say("demo: ledger reading #{report.sort.map { |k, v| "#{k}=#{v}" }.join(' ')} missing=#{@missing.size}")
      @missing.each { @ctx.say("demo: ledger row not found: #{it}") }
      self
    end

    def unowned_items = @unowned_items ||= []

    private

    attr_reader :ctx

    def people = AssistantSeed::PEOPLE

    def user(key) = key && ctx.user(key)

    def project = ctx.project

    def journal_for(wp, who, find)
      scope = Journal.where(journable_type: "WorkPackage", journable_id: wp, user_id: people.fetch(who))
                     .where("notes LIKE ?", "%#{Journal.sanitize_sql_like(find)}%").order(:created_at)
      scope.first
    end

    def resolve(table)
      table.filter_map do |kind, wp, who, find, title, opts|
        journal = journal_for(wp, who, find)
        unless journal
          @missing << "##{wp} #{who} #{find}"
          next
        end

        Row.new(kind:, wp:, who:, find:, title:, opts:, journal:)
      end
    end

    def read(row)
      intent = (model_read(row) if row.opts[:model] && model_allowed?) || rule_read(row)
      report[row.opts[:model] && intent.extractor_version != RULE_VERSION ? "model" : "rule"] += 1
      report["misread"] += 1 if row.opts[:misread]
      intent
    end

    def model_allowed?
      @use_model && @model_failures < MAX_MODEL_FAILURES &&
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @started) < MODEL_BUDGET
    end

    # The same event the reader sends on success normally starts proposals, promise date changes and signals; the seed
    # wants the reading only, the rest comes from the sweep.
    def without_event_listeners
      event = Assistant::Understanding::Extractor::EXTRACTED_EVENT
      singleton = OpenProject::Notifications.singleton_class
      singleton.alias_method :ledger_demo_send, :send
      singleton.define_method(:send) { |name, *args, **kw| name.to_s == event ? nil : ledger_demo_send(name, *args, **kw) }
      User.current = ctx.admin
      yield
    ensure
      singleton.alias_method :send, :ledger_demo_send
      singleton.remove_method :ledger_demo_send
    end

    def model_read(row)
      journal = row.journal
      subject = journal.journable
      before = Intent.where(subject:).index_by(&:id).transform_values(&:attributes)
      newest = Intent.maximum(:id).to_i
      Assistant::Understanding::Extractor.for_journal(journal).call
      made = Intent.where(source: journal).where("id > ?", newest).to_a
      restore(before, subject)
      match = made.find { matches?(it, row) }
      (made - [match]).each(&:destroy!)
      unless match
        @model_failures += 1 if made.empty?
        return nil
      end
      @model_failures = 0
      apply_overrides(match, row)
      match
    rescue StandardError => e
      @model_failures += 1
      @ctx.say("demo: model reading failed for #{row.find.truncate(24)}: #{e.class} #{e.message.truncate(80)}")
      nil
    end

    def restore(before, subject)
      Intent.where(subject:, id: before.keys).find_each do |intent|
        original = before.fetch(intent.id)
        changed = original.select { |name, value| intent.attributes[name] != value && !%w[updated_at].include?(name) }
        intent.update_columns(changed) if changed.any?
      end
    end

    def matches?(intent, row)
      expected = row.opts.fetch(:owner, row.who)
      return false unless intent.owner_id == user(expected)&.id

      row.kind == :objection ? intent.parent_id.present? : intent.kind == kind_of(row)
    end

    def kind_of(row) = row.kind == :objection ? "question" : row.kind.to_s

    def rule_read(row)
      journal = row.journal
      kind = kind_of(row)
      subject = journal.journable
      owner_key = row.opts.fetch(:owner, row.who)
      due_on = due_of(row)
      status = row.opts[:status] || { "commitment" => "open", "deferral" => "open", "question" => "open", "decision" => "active" }.fetch(kind)
      intent = Intent.create!(
        project:, kind:, status:, strength: strength_of(row, kind), title: row.title, quote: row.opts[:quote] || quote_of(journal.notes, row.find),
        owner: user(owner_key), counterparty: user(row.opts[:to]), source: journal, subject:,
        work_package: (subject if subject.is_a?(WorkPackage)), said_due_expression: row.opts[:says], said_due_on: due_on,
        moves: row.opts[:moves].to_i, stated_at: journal.created_at, extractor_version: RULE_VERSION
      )
      apply_overrides(intent, row)
      intent
    end

    def strength_of(row, kind)
      return "requested" if kind == "question" && row.kind != :objection

      row.opts[:str] || "firm"
    end

    def due_of(row)
      return unless row.kind.in?(%i[commitment deferral])
      return ctx.d(row.opts[:due_on]) if row.opts[:due_on]
      return unless row.opts[:due]

      stated_on = row.journal.created_at.in_time_zone(row.journal.user.time_zone || Time.zone).to_date
      resolver = Assistant::Understanding::DueResolver.new(project:, stated_on:, work_package: row.journal.journable)
      resolver.call(row.opts[:due]).due_on
    end

    def quote_of(notes, find)
      sentence = notes.to_s.split(/(?<=[。！？])|\n/).find { it.include?(find) }&.strip
      sentence.presence || find
    end

    # What happened to the item afterwards, as far as the model could not know when it read the comment.
    def apply_overrides(intent, row)
      changes = {}
      changes[:said_due_on] = ctx.d(row.opts[:due_on]) if row.opts[:due_on] && intent.commitment_like?
      changes[:said_due_expression] = row.opts[:says] if row.opts[:says] && intent.said_due_expression.blank?
      changes[:moves] = row.opts[:moves].to_i if row.opts.key?(:moves)
      changes[:counterparty] = user(row.opts[:to]) if row.opts[:to] && intent.counterparty.nil?
      changes[:strength] = row.opts[:str] if row.opts[:str] && intent.kind != "decision"
      changes.merge!(ending_of(intent, row)) if row.opts[:status]
      intent.update!(changes) if changes.any?
      intent.update_columns(work_package_id: row.journal.journable_id) if intent.work_package_id.nil? && row.journal.journable.is_a?(WorkPackage)
    end

    def ending_of(intent, row)
      status = row.opts.fetch(:status)
      evidence = row.opts[:by] && journal_for(*row.opts[:by].values_at(0, 1, 2))
      resolved = evidence&.created_at || fallback_resolution(intent)
      attributes = { status:, resolved_at: resolved }
      attributes[:answered_by] = evidence if status == "answered" && evidence
      attributes
    end

    def fallback_resolution(intent)
      moment = intent.said_due_on ? ctx.at(intent.said_due_on, "17:00") : intent.stated_at + 1.day
      [moment, ctx.now - 1.hour].min
    end

    def link_parents(rows)
      rows.select { it.opts[:parent] }.each do |row|
        parent = parent_decision(row.opts[:parent]) or next
        Intent.where(source: row.journal, kind: "question").where.not(id: parent.id).update_all(parent_id: parent.id)
      end
      rows.select { it.opts[:superseded_by] }.each do |row|
        old = Intent.find_by(source: row.journal, kind: "decision") or next
        newer_journal = journal_for(*row.opts[:superseded_by]) or next
        newer = Intent.find_by(source: newer_journal, kind: "decision") or next
        old.update!(status: "superseded", resolved_at: newer.stated_at)
        newer.update!(supersedes: old)
      end
      rows.select { it.opts[:by] && it.kind == :question }.each do |row|
        evidence = journal_for(*row.opts[:by].values_at(0, 1, 2)) or next
        Intent.where(source: row.journal, kind: "question").update_all(status: "answered", resolved_at: evidence.created_at, answered_by_type: "Journal", answered_by_id: evidence.id)
      end
    end

    def parent_decision(spec)
      return Intent.where(kind: "decision").where("title LIKE ?", "%#{Intent.sanitize_sql_like(spec[1])}%").order(:stated_at).last if spec[0] == :title

      journal = journal_for(*spec.values_at(0, 1, 2)) or return
      Intent.find_by(source: journal, kind: "decision")
    end

    # 对话历史保留期 (#340): the description was 90 days, then per plan. The decision record page still repeats the first.
    def retention_decisions
      first = Journal.where(journable_type: "WorkPackage", journable_id: 340, version: 4).first
      changed = Journal.where(journable_type: "WorkPackage", journable_id: 340, version: 6).first
      return @missing << "#340 retention journals" unless first && changed

      old = Intent.create!(project:, kind: "decision", status: "superseded", strength: "firm", title: "对话历史默认保留 90 天，到期后自动删除",
                           quote: "对话历史默认保留 90 天，到期后自动删除。", owner: user(:ada), source: first, subject: first.journable, work_package_id: 340,
                           stated_at: first.created_at, resolved_at: changed.created_at, extractor_version: RULE_VERSION)
      Intent.create!(project:, kind: "decision", status: "active", strength: "firm", title: "对话历史按套餐保留：试用 30 天、标准 90 天、旗舰 365 天",
                     quote: "对话历史按套餐保留：试用 30 天、标准 90 天、旗舰 365 天；到期后先归档，管理员可导出，不再自动删除。", owner: user(:ada),
                     source: changed, subject: changed.journable, work_package_id: 340, stated_at: changed.created_at, supersedes: old,
                     extractor_version: RULE_VERSION)
      report["rule"] += 2
    end

    # The fourteen readings the acceptance seed wrote, brought up to date with what was said this week.
    def settle_acceptance_ledger
      settle(:question, 75, :sam, answered_by: [75, :ben, "回答 Sam 上周的问题"])
      settle(:question, 69, :fiona, answered_by: [69, :ben, "回答 Fiona 上周的问题"])
      settle(:question, 68, :ada, answered_by: [68, :ada, "跨文档先在当前页内跳转"])
      settle(:commitment, 110, :sam, done_by: [110, :sam, "我试了：站内、邮件都能收到"])
      settle(:commitment, 69, :ben, moves: 1, said_due_on: ctx.d(3), said_due_expression: "明天")
    end

    def settle(kind, wp, owner, answered_by: nil, done_by: nil, **attributes)
      intent = Intent.find_by(kind: kind.to_s, work_package_id: wp, owner: user(owner), extractor_version: "seed") or return
      evidence = journal_for(*(answered_by || done_by)) if answered_by || done_by
      attributes.merge!(status: "answered", resolved_at: evidence.created_at, answered_by: evidence) if answered_by && evidence
      attributes.merge!(status: "done", resolved_at: evidence.created_at) if done_by && evidence
      intent.update!(attributes)
    end

    ACTION_LINE = /\A-\s*(?<who>[^：]+)：(?<text>.+?)(?:（(?<month>\d+)月(?<day>\d+)日前）)?\z/
    ACTION_ITEMS = [
      ["Sprint 5 回顾会", "本次行动项", /\A无人认领/],
      ["Sprint 6 回顾会", "本次行动项", nil],
      ["待办梳理（Backlog Refinement）", "本次行动项", /\A无人认领/]
    ].freeze

    def meeting_items
      ACTION_ITEMS.each do |meeting_title, item_title, only|
        meeting = Meeting.where(project:, title: meeting_title).order(:start_time).last
        item = meeting&.agenda_items&.find_by(title: item_title)
        unless item
          @missing << "#{meeting_title}/#{item_title}"
          next
        end

        made = item.notes.to_s.lines.filter_map { |line| action_intent(item, meeting, line.strip, only) }
        unowned_items << [item, made] if made.any? { it.owner_id.nil? }
      end
    end

    def action_intent(item, meeting, line, only)
      match = ACTION_LINE.match(line) or return
      return if only && !only.match?(match[:who])

      owner = person_named(match[:who])
      return unless owner || match[:who] == "无人认领"

      due = (Date.new(ctx.monday.year, match[:month].to_i, match[:day].to_i) if match[:month])
      ref = match[:text][/#(\d+)/, 1]&.to_i
      report["meeting"] += 1
      Intent.create!(
        project:, kind: "commitment", status: "open", strength: "firm", title: match[:text].gsub(/(?<=#\d) (?=#)/, "、").truncate(120), quote: line, owner:,
        counterparty: (user(:sam) unless owner.nil? || owner == user(:sam)), source: item, subject: meeting, work_package_id: (ref if ref && WorkPackage.exists?(ref)), said_due_on: due,
        stated_at: meeting.start_time, extractor_version: RULE_VERSION
      )
    end

    HISTORY_CUTOFF_DAY = -4
    DONE_MARK = /（已完成）/
    CARRIED_MARK = /（做了一半）|（没做）|（部分完成）/

    # Every earlier meeting's "本次行动项" is read by rule (structured lines: who, what, by when). What became of each
    # is read from the next meeting's "上次行动项" line for the same person.
    def history_action_items
      meetings = Meeting.where(project:).order(:start_time).to_a
      cutoff = ctx.at(HISTORY_CUTOFF_DAY, "00:00")
      meetings.each_with_index do |meeting, index|
        break if meeting.start_time >= cutoff

        item = meeting.agenda_items.find_by(title: "本次行动项") or next
        recap_meeting = meetings.drop(index + 1).find { it.agenda_items.exists?(title: "上次行动项") }
        recap = recap_meeting&.agenda_items&.find_by(title: "上次行动项")&.notes.to_s.lines.map(&:strip)
        bullets = item.notes.to_s.lines.filter_map { ACTION_LINE.match(it.strip) }.select { person_named(it[:who]) }
        bullets.each { history_intent(item, meeting, it, bullets, recap_meeting, recap.to_a) }
      end
    end

    def history_intent(item, meeting, match, bullets, recap_meeting, recap)
      owner = person_named(match[:who])
      due = (Date.new(ctx.monday.year, match[:month].to_i, match[:day].to_i) if match[:month])
      status, resolved = ending_from_recap(match, owner, bullets, recap_meeting, recap)
      report["history_meeting"] += 1
      Intent.create!(
        project:, kind: "commitment", status:, strength: "firm", title: match[:text].truncate(120), quote: match[0].delete_prefix("- "), owner:,
        source: item, subject: meeting, said_due_on: due,
        stated_at: meeting.start_time, resolved_at: resolved, extractor_version: RULE_VERSION
      )
    end

    def ending_from_recap(match, owner, bullets, recap_meeting, recap)
      resolved = recap_meeting&.start_time || ctx.now - 1.day
      resolved = [resolved, ctx.at(Date.new(ctx.monday.year, match[:month].to_i, match[:day].to_i), "17:00")].min if match[:month]
      lines = recap.select { it.start_with?("- #{owner.firstname}：") }
      mine = bullets.count { it[:who] == match[:who] }
      line = lines.max_by { Assistant::Text.overlap(match[:text], it).first }
      line = nil unless line && (Assistant::Text.overlap(match[:text], line).first >= 0.2 || (lines.size == 1 && mine == 1))
      return ["done", resolved] unless line

      [line.match?(CARRIED_MARK) ? "superseded" : "done", resolved]
    end

    def person_named(name)
      key = people.keys.find { ctx.user(it).firstname == name }
      user(key)
    end

    def mark_every_comment_read
      version = Assistant::Understanding::Prompt::VERSION
      read = Assistant::Extraction.where(source_type: "Journal", extractor_version: version).pluck(:source_id).to_set
      Journal.where(journable_type: "WorkPackage", journable_id: WorkPackage.where(project:).select(:id)).where.not(notes: [nil, ""]).find_each do |journal|
        next if read.include?(journal.id)

        Assistant::Extraction.create!(project:, source: journal, extractor_version: version, source_digest: Digest::SHA256.hexdigest(journal.notes),
                                      status: "succeeded", items_count: Intent.where(source: journal).count,
                                      created_at: journal.created_at, updated_at: journal.created_at)
      end
    end

    Intent = Assistant::Intent
  end
end
# rubocop:enable Layout/LineLength
