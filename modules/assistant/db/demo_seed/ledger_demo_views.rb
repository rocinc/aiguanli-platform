# frozen_string_literal: true

# Reads the demo world the way each person sees it and stores the rendered words (no screenshots).
#
#   DATABASE_URL=... RAILS_ENV=development bundle exec rails runner modules/assistant/db/demo_seed/ledger_demo_views.rb
#
# Writes tmp/ledger-views.md (one section per person, rendered text only). Opening other people's
# performance pages is recorded in the database like any view, so run it on a sandbox copy.
require "nokogiri"
require_relative "../acceptance_seed/context"

module DemoSeed
  class LedgerViews
    PASSWORD = "Quill-Dev-2026!"
    TARGET = Rails.root.join("tmp/ledger-views.md")
    STOCK = ["稍后", "明天上午", "到期前一天", "今天下午", "下周一", "这类事不用告诉我", "在这个项目", "所有项目", "这不对", "事实错了", "我已经知道",
             "不是我的事", "时机不对", "说一句", "先不动", "确认", "婉拒", "改了什么、为什么", "等待决定", "需要你点头", "替你", "·", "改", "更短",
             "更具体", "换个说法", "更正式", "停止", "‹", "›", "展开项目菜单", "内容", "撤销", "再写一版", "还想怎么改？",
             "可以直接改字；选中一段，只改这一段。", "这一段已改。"].to_set.freeze

    # label, path, (optional) maximum characters kept
    PEOPLE = {
      "sam.sm" => ["Sam Okafor · Scrum Master / 项目管理员", [
        ["我的页面 · 今天（简报）", "/assistant/today"],
        ["AI 助理桌子 · 替你盯着的", "/projects/quill/assistant?tab=watching"],
        ["AI 助理桌子 · 职责", "/projects/quill/assistant?tab=duties"],
        ["AI 助理桌子 · 想法", "/projects/quill/assistant?tab=ideas"],
        ["AI 助理桌子 · 它做得怎么样", "/projects/quill/assistant?tab=insights"],
        ["#73 工作包页顶一行", "/assistant/work_packages/73/line"],
        ["#116 工作包页顶一行", "/assistant/work_packages/116/line"],
        ["#116 中 Sam 自己那句被读成了什么", [:reading, 116, :sam, "Bob 说过周四给回滚方案"]],
        ["版本 v1.1 商业化版", "/versions/21"],
        ["会议 · Sprint 7 计划会", "/meetings/274"],
        ["成员表现 · 团队表", "/projects/quill/members/performance"],
        ["成员表现 · Bob", "/projects/quill/members/34/performance"],
        ["成员表现 · Ben", "/projects/quill/members/35/performance"],
        ["成员表现 · Fiona", "/projects/quill/members/33/performance"]
      ]],
      "ada.po" => ["Ada Nakamura · 产品负责人", [
        ["我的页面 · 今天（简报）", "/assistant/today"],
        ["AI 助理桌子 · 替你盯着的", "/projects/quill/assistant?tab=watching"],
        ["AI 助理桌子 · 想法", "/projects/quill/assistant?tab=ideas"],
        ["AI 助理桌子 · 它做得怎么样", "/projects/quill/assistant?tab=insights"],
        ["#313 工作包页顶一行（9/13 的决定）", "/assistant/work_packages/313/line"],
        ["#340 工作包页顶一行", "/assistant/work_packages/340/line"],
        ["#81 工作包页顶一行", "/assistant/work_packages/81/line"],
        ["版本 v1.1 商业化版", "/versions/21"],
        ["会议 · Sprint 7 计划会", "/meetings/274"],
        ["维基 · 决定记录", "/projects/quill/wiki/%E5%86%B3%E5%AE%9A%E8%AE%B0%E5%BD%95"]
      ]],
      "bob.be" => ["Bob Fischer · 后端", [
        ["我的页面 · 今天（简报）", "/assistant/today"],
        ["AI 助理桌子 · 替你盯着的", "/projects/quill/assistant?tab=watching"],
        ["#73 工作包页顶一行", "/assistant/work_packages/73/line"],
        ["#73 中 Bob 那句条件句被读成了什么", [:reading, 73, :bob, "如果财务周一前把最终口径发我"]],
        ["我的表现", "/projects/quill/members/34/performance"]
      ]],
      "ben.be" => ["Ben Iversen · 全栈", [
        ["我的页面 · 今天（简报）", "/assistant/today"],
        ["AI 助理桌子 · 替你盯着的", "/projects/quill/assistant?tab=watching"],
        ["#88 工作包页顶一行", "/assistant/work_packages/88/line"],
        ["#88 中 Ben 撤回的那句被读成了什么", [:reading, 88, :ben, "周四前给出文档这件事我没做到"]],
        ["#69 工作包页顶一行", "/assistant/work_packages/69/line"],
        ["我的表现", "/projects/quill/members/35/performance"]
      ]],
      "fiona.fe" => ["Fiona Walsh · 前端", [
        ["我的页面 · 今天（简报）", "/assistant/today"],
        ["AI 助理桌子 · 替你盯着的", "/projects/quill/assistant?tab=watching"],
        ["#81 工作包页顶一行", "/assistant/work_packages/81/line"],
        ["我的表现", "/projects/quill/members/33/performance"]
      ]],
      "quinn.qa" => ["Quinn Adeyemi · 新成员", [
        ["我的页面 · 今天（简报）", "/assistant/today"],
        ["AI 助理桌子 · 替你盯着的", "/projects/quill/assistant?tab=watching"],
        ["#68 工作包页顶一行", "/assistant/work_packages/68/line"],
        ["#68 中 Quinn 向助理提的问题（应当仍没有回答）", [:reading, 68, :quinn, "之前有过类似的决定吗"]],
        ["#79 工作包页顶一行", "/assistant/work_packages/79/line"],
        ["#75 工作包页顶一行", "/assistant/work_packages/75/line"]
      ]]
    }.freeze

    def self.call = new.call

    def call
      sections = PEOPLE.map { |login, (title, pages)| section(login, title, pages) }
      File.write(TARGET, header + sections.join("\n") + "\n")
      puts "wrote #{TARGET}"
    end

    private

    def header
      <<~MD
        # 演示：各人所见（渲染文字存档）

        每个视角用该人的账号登录沙箱库，取页面渲染后的正文文字，不含截图。每条提示底下的通用控制行（稍后、这类事不用告诉我、这不对……）在存档里省略，只留文字内容。日期以种子运行当天为准。

      MD
    end

    def section(login, title, pages)
      session = login_as(login)
      body = pages.map do |label, path|
        text = path.is_a?(Array) ? reading(session, path) : fetch(session, path)
        "### #{label}\n\n#{text.presence || '（空）'}\n"
      end
      "## #{title}\n\n#{body.join("\n")}"
    end

    def login_as(login)
      session = ActionDispatch::Integration::Session.new(Rails.application)
      session.host! "localhost"
      session.get("/login")
      token = Nokogiri::HTML(session.response.body).at_css("input[name=authenticity_token]")&.[]("value")
      session.post("/login", params: { username: login, password: PASSWORD, authenticity_token: token })
      session
    end

    def fetch(session, path)
      session.get(path, headers: { "Accept-Language" => "zh-CN" })
      hops = 0
      while session.response.status.in?([301, 302, 303]) && hops < 3
        session.get(session.response.location.sub(%r{\Ahttps?://[^/]+}, ""), headers: { "Accept-Language" => "zh-CN" })
        hops += 1
      end
      return "（HTTP #{session.response.status}）" unless session.response.status == 200

      clean(session.response.body)
    end

    def reading(session, (_, work_package, who, phrase))
      journal = Journal.where(journable_type: "WorkPackage", journable_id: work_package, user_id: AssistantSeed::PEOPLE.fetch(who))
                       .where("notes LIKE ?", "%#{Journal.sanitize_sql_like(phrase)}%").order(:created_at).first
      return "（找不到那条评论）" unless journal

      "评论原文：「#{Assistant::Text.plain(journal.notes).squish}」\n\n#{fetch(session, "/assistant/journals/#{journal.id}/reading")}"
    end

    def clean(html)
      doc = Nokogiri::HTML(html)
      doc.css("script,style,svg,noscript").remove
      root = doc.at_css("#content") || doc.at_css("main") || doc.at_css("body") || doc
      lines = root.text.gsub(/[ \t]+/, " ").lines.map(&:strip).reject { it.empty? || STOCK.include?(it) }
      lines.chunk_while { |a, b| a == b }.map(&:first).join("\n")
    end
  end
end

DemoSeed::LedgerViews.call
