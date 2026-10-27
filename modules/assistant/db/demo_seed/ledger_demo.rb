# frozen_string_literal: true

require_relative "ledger_demo_reader"
require_relative "ledger_demo_record"
require_relative "ledger_demo_people"

module DemoSeed
  # The assistant's own books for the demo world: what it understood (Intents), what it noticed and did (Signals,
  # Actions, receipts), how it is doing (scorecard), the idea garden and the member appraisals.
  #
  # `call` is a normal demo step (it runs before the runner clears Signals and Actions and sweeps): the understanding
  # and the people-side records. The runner then calls `before_sweep` (receipts that go through the action layer,
  # while the sweep can still see their effects) and `after_sweep` (the month of notices behind the scorecard).
  class LedgerDemo
    include Support

    class << self
      attr_accessor :state

      def before_sweep(_ctx) = state&.before_sweep
      def after_sweep(_ctx) = state&.after_sweep
    end

    def call
      self.class.state = self
      @reading = LedgerReader.new(ctx).call
      Assistant::Proactive::ProjectSettings.write!(project, lead_ids: [user(:sam).id, user(:ada).id])
      ensure_retention_adr
    end

    def before_sweep
      @record = LedgerRecord.new(ctx)
      @people = LedgerPeople.new(ctx)
      @people.mute_rules
      @people.ideas
      @record.receipts
      @reading.unowned_items.each do |item, made|
        next if item.meeting.title == "Sprint 5 回顾会"

        Assistant::Understanding::UnownedItems.offer(item, made) if made.any? { it.owner_id.nil? }
      end
    end

    def after_sweep
      @people.drop_harvested_ideas
      @record.drafts
      @record.weekly_status
      @record.history
      @people.appraisals
      show_now
    end

    private

    RETENTION_ADR = <<~'MD'

      ## ADR-016 对话历史默认保留 90 天

      | 状态 | 有效 |
      |---|---|
      | 日期 | 9月24日 |
      | 决定人 | <mention class="mention" data-id="30" data-type="user" data-text="@Ada Nakamura">@Ada Nakamura</mention> |
      | 关联 | #340 |

      **背景**　对话历史要有统一的保留期，免得存储无限增长，用户的对话也不该留得太久。

      **选项**

      1. 永久保留：简单，但存储和合规都有成本。
      2. 默认保留 90 天，到期后自动删除。

      **结论**　选 2。对话历史默认保留 90 天，到期后自动删除。

      > Ada：保留期先定 90 天，到期自动删除。那就这样。（#340，9月24日）
    MD

    # #340's description now says per-plan retention; the decision record has to say what it said before (Quinn asks
    # about it). Added only when the docs step did not write that decision.
    def ensure_retention_adr
      page = project.wiki.find_page("决定记录：详述")
      return if page.nil? || page.text.include?("保留 90 天")

      as(:sam) do
        page.text = "#{page.text.rstrip}\n#{RETENTION_ADR}"
        page.journal_notes = "补记 ADR-016"
        page.save!
      end
      stamp = ctx.at(3, "09:10")
      connection = ActiveRecord::Base.connection
      connection.execute("SET CONSTRAINTS non_overlapping_journals_validity_periods DEFERRED")
      journals = Journal.where(journable_type: "WikiPage", journable_id: page.id).order(:version).to_a
      journals.last.update_columns(created_at: stamp, updated_at: stamp, validity_period: (stamp...nil))
      journals[-2]&.update_columns(validity_period: (journals[-2].created_at...stamp))
      connection.execute("SET CONSTRAINTS non_overlapping_journals_validity_periods IMMEDIATE")
      page.update_columns(updated_at: stamp)
    end

    # The sweep ran on the calendar as it is (the demo may be built on a weekend), so what it queued for the next working
    # day's brief would stay invisible until then; the brief shows it from now.
    def show_now
      Assistant::Signal.where(project:, state: "pending", channel: %w[brief notification], outcome: nil)
                       .where("deliver_at > ?", ctx.now).update_all(deliver_at: ctx.now)
    end
  end
end
