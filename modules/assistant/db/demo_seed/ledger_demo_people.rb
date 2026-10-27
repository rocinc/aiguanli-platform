# frozen_string_literal: true

# rubocop:disable Layout/LineLength
module DemoSeed
  # The people-side books: the idea garden, the rules people asked not to hear about, and the appraisal records
  # (a member's own notes, who looked at their page, two written appraisals).
  class LedgerPeople
    def initialize(ctx)
      @ctx = ctx
    end

    # Ideas the garden holds: [title, state, mentions, extras]. A mention is [:message, id] (a forum topic, said by its
    # author) or [:journal, [work package, author, phrase]] (a comment).
    IDEAS = [
      ["写作模板市场", "adopted", [[:message, 165, "模板"], [:journal, [85, :ada, "论坛“用户反馈”里又有客户提到模板市场"]]], { work_package: 85 }],
      ["导出时保留批注", "open", [[:message, 159], [:journal, [323, :fiona, "导出 Word 时希望保留批注"]]], {}],
      ["检索先识别短问题：短的走关键词，长的走向量", "open", [[:journal, [67, :ben, "要是检索能先识别短问题就好了"]], [:journal, [59, :fiona, "搜“INV-2024-0132”这种编号能搜到吗"]], [:journal, [313, :ben, "要是检索能先识别出短问题就好了"]]], {}],
      ["全文检索兜短查询、向量管长问题的混合方案", "merged", [[:journal, [59, :ben, "要是把文档库搜索改成全文检索"]]], { into: 2 }],
      ["每次发布前，检查清单从上一次自动生成", "open", [[:journal, [116, :sam, "要是每次发布前清单能从上一次的自动生成就好了"]]], {}],
      ["向量库客户端加一层兼容层，升级只改一层", "open", [[:journal, [121, :bob, "要是向量库客户端有个兼容层就好了"]]], {}],
      ["长文生成前先给大纲确认", "open", [[:message, 222]], {}],
      ["续写时自动套用作者语气档案", "open", [[:message, 218]], {}],
      ["引用格式一键切换（GB/T 7714、APA）", "open", [[:message, 230]], {}],
      ["团队管理员的用量仪表盘", "open", [[:message, 233]], {}],
      ["新人第一周任务包", "open", [[:message, 236, "任务包"]], {}],
      ["移动端只读审稿", "set_aside", [[:message, 240]], { reason: "当前没有客户提，v2.0 之后再看" }],
      ["让模型总结会话标题", "set_aside", [[:journal, [87, :fiona, "请问要不要让模型总结一个标题"]]], { reason: "先截断，模型总结以后再说" }]
    ].freeze

    NOTES = [
      [:bob, "load", "这个季度有两周在做 #100 的并发超扣和 #75 的口径，#73 因此顺延了两次。下周三起的年假一个月前就批了。", -2],
      [:bob, "delivery", "#73 的两次改期里，有一次是在等财务的对账口径，我在周中同步会上说过。", -1],
      [:ben, "estimation", "续写和 RAG 类的活我确实估少了，回顾会上认了。现在每次估之前先翻一遍同类任务的历史工时。", 4],
      [:fiona, "collaboration", "Quinn 入项这一周，我花了不少时间带他看 #68 和 #99 的交接，评论多半是在回答他的问题，不是在做自己的包。", 2]
    ].freeze

    VIEWS = [
      [:sam, :bob, -9, "10:20"], [:sam, :bob, 3, "09:40"], [:ada, :ben, 2, "15:05"],
      [:sam, :fiona, -10, "16:10"], [:sam, :fiona, 2, "11:30"], [:ada, :fiona, 2, "17:20"]
    ].freeze

    def mute_rules
      NoticeHistory::MUTED.each do |who, detector|
        preference = Assistant::Preference.for(user(who))
        preference.update!(muted_detectors: (Array(preference.muted_detectors) | [detector]))
      end
    end

    def ideas
      Assistant::Idea.where(project:).destroy_all
      made = IDEAS.filter_map { |title, state, mentions, extras| idea(title, state, mentions, extras) }
      made.each_with_index do |idea, index|
        into = IDEAS[index][3][:into] && made[IDEAS[index][3][:into]]
        idea.merge_into!(into) if into
      end
      @last_idea_id = Assistant::Idea.maximum(:id)
      ctx.say("demo: ideas #{Assistant::Idea.where(project:).group(:state).count}")
    end

    # The sweep harvests ideas from comments by pattern ("能不能…？"), and some of what it picks up is a request, not an idea.
    def drop_harvested_ideas
      Assistant::Idea.where(project:).where("id > ?", @last_idea_id).destroy_all if @last_idea_id
    end

    def appraisals
      notes
      views
      written
    end

    private

    attr_reader :ctx

    def project = ctx.project

    def user(key) = ctx.user(key)

    def idea(title, state, mentions, extras)
      sources = mentions.filter_map { |kind, ref, keyword| source_of(kind, ref, keyword) }
      return if sources.empty?

      first = sources.map(&:last).min
      idea = Assistant::Idea.create!(project:, title:, state: state == "merged" ? "open" : state, work_package_id: extras[:work_package],
                                     set_aside_reason: extras[:reason], created_at: first, updated_at: sources.map(&:last).max)
      sources.each do |source, at, speaker, quote|
        Assistant::IdeaMention.create!(idea:, speaker:, source:, quote:, said_at: at, created_at: at, updated_at: at)
      end
      idea
    end

    def source_of(kind, ref, keyword = nil)
      if kind == :message
        message = Message.find_by(id: ref) or return
        [message, message.created_at, message.author, sentence(message.content, keyword)]
      else
        wp, who, phrase = ref
        journal = Journal.where(journable_type: "WorkPackage", journable_id: wp, user_id: AssistantSeed::PEOPLE.fetch(who))
                         .where("notes LIKE ?", "%#{Journal.sanitize_sql_like(phrase)}%").order(:created_at).first or return
        [journal, journal.created_at, journal.user, sentence(journal.notes, phrase)]
      end
    end

    def sentence(text, phrase = nil)
      plain = Assistant::Text.plain(text.to_s).squish
      found = plain.split(/(?<=[。！？])/).find { phrase.nil? || it.include?(phrase) }
      (found.presence || plain).strip.truncate(140)
    end

    def notes
      Assistant::AppraisalNote.where(project:).delete_all
      NOTES.each do |who, key, note, day|
        at = ctx.at(day, "17:40")
        Assistant::AppraisalNote.create!(subject: user(who), project:, metric_key: key, note:, created_at: at, updated_at: at)
      end
    end

    def views
      Assistant::AppraisalView.where(project:).delete_all
      VIEWS.each do |viewer, subject, day, hm|
        Assistant::AppraisalView.create!(viewer: user(viewer), subject: user(subject), project:, created_at: ctx.at(day, hm))
      end
    end

    # One finished appraisal (Fiona, by Sam) and one still being written (Ben): drafted by the real narrative writer,
    # skipped when the model is not there.
    def written
      return unless Assistant::Llm.configured?

      Assistant::Appraisal.where(project:).delete_all
      team = Assistant::Appraisals::Team.new(project:, from: ctx.today - 90, to: ctx.today)
      sam = user(:sam)
      draft_for(team, :fiona, sam, finalized_at: ctx.at(2, "17:30"))
      draft_for(team, :ben, sam)
    end

    def draft_for(team, who, author, finalized_at: nil)
      appraisal = OpenProject::LocaleHelper.with_locale_for(author) do
        Assistant::Appraisals::Narrative.new(team.profile(user(who)), author:).save_draft!
      end
      stamp = finalized_at || ctx.at(2, "16:50")
      appraisal.update_columns(created_at: stamp - 30.minutes, updated_at: stamp, finalized_at:)
    rescue StandardError => e
      ctx.say("demo: appraisal for #{who} skipped: #{e.class} #{e.message.truncate(80)}")
    end
  end
end
# rubocop:enable Layout/LineLength
