# frozen_string_literal: true

module DemoSeed
  module DocsWikiPages
    private

    RISKS = [
      { id: "R0", since: -63, what: "扫描版 PDF 无法解析，用户上传后得到空结果", impact: "中", owner: "{ben}",
        plan: "Sprint 2 只处理有文本层的文档，扫描件的风险记在这里", status: ->(d) { d < -10 ? "关注" : "已关闭：提示上线，OCR 放到 v2.0（{adr:ocr}）" }, refs: "#62 #99" },
      { id: "R1", since: -14, what: "v1.1 有硬日期，但 Sprint 6 带过来的未完成项压在容量最低的一周", impact: "高", owner: "{ada}",
        plan: "Sprint 7 计划会上二选一：守日期，或砍范围。砍范围时要先说清楚砍哪几项、对谁有影响",
        status: ->(d) { d < 2 ? "关注" : "升高，等 Sprint 7 计划会决定" }, refs: "#73 #100 #104 #116" },
      { id: "R2", since: -14, what: "配额扣减并发超扣：同一账号会被多扣，属于计费类缺陷", impact: "高", owner: "{bob}",
        plan: "按 {adr:reserve} 做预扣加结算；修复后补并发回归用例", status: ->(_) { "进行中" }, refs: "#100" },
      { id: "R5", since: -14, what: "对账口径依赖财务确认，口径变了历史流水要重算", impact: "中", owner: "{sam}",
        plan: "流水只追加（{adr:ledger}），口径变化只重算不改历史；我来盯财务的回复", status: ->(d) { d < 0 ? "等待财务" : "财务已回复口径，Bob 对账后关闭" }, refs: "#75 #102" },
      { id: "R9", since: -14, what: "续写与 RAG 类任务实际工时约为估算的 1.6 倍（12 个样本）", impact: "中", owner: "{ben}",
        plan: "估算时先乘 1.6，或者拆到 3 点以内；Ben 记录实际工时对照", status: ->(_) { "关注" }, refs: "#56 #92" },
      { id: "R3", since: -5, what: "用量统计迟迟没有进展，配额告警 UI 排在它后面，依赖链上全是 v1.1 的范围", impact: "高", owner: "{bob}",
        plan: "计划会前确认还剩多少工作量，确认是否需要第二个人接手", status: ->(d) { d < 2 ? "关注" : "升高" }, refs: "#73 #76" },
      { id: "R4", since: -5, what: "支付回调要保证幂等，否则重复回调会重复入账", impact: "高", owner: "{bob}",
        plan: "按回调号去重；补重复回调的用例", status: ->(_) { "进行中" }, refs: "#104" },
      { id: "R7", since: -5, what: "知识库权限已连续两个迭代没有完成，范围收窄后截止日顺延到 Sprint 6 末", impact: "中", owner: "{ben}",
        plan: "只做知识库级和文档级两层（{adr:permissions}）；Ben 回来后重新估剩余工作量", status: ->(d) { d < 4 ? "关注" : "截止日已过，需要重新排" }, refs: "#69 #95" },
      { id: "R8", since: -5, what: "多人同时编辑是 13 点的大故事，按整体做放不进一个迭代", impact: "中", owner: "{fiona}",
        plan: "待办梳理会建议拆成三个故事，见 {adr:split}", status: ->(d) { d < 2 ? "关注" : "已逾期，等拆分结论" }, refs: "#81 #108 #109" },
      { id: "R10", since: -5, what: "Frank 和 Mia 借调到数据平台组，检索和评测方面的问题要先找 Sam 转", impact: "中", owner: "{sam}",
        plan: "需要他们配合的事先找我；评测集补样本见 #98", status: ->(_) { "关注" }, refs: "#98 #121" },
      { id: "R6", since: 2, what: "Bob 从 10 月 21 日起请假三天（#75 的评论里说过），正好覆盖 v1.1 发布前后", impact: "高", owner: "{sam}",
        plan: "把 #73 #100 #104 的交接对象在 Sprint 7 计划会上定下来", status: ->(_) { "已知，待安排" }, refs: "#73 #100 #104" },
      { id: "R11", since: 2, what: "发布前检查清单的四项（迁移脚本、配额开关、回滚方案、对外公告）还没有逐项确认", impact: "中", owner: "{sam}",
        plan: "Sprint 7 第一周逐项过，每项写负责人和日期", status: ->(_) { "进行中" }, refs: "#116" },
      { id: "R12", since: 4, what: "评审会的演示环境和开发环境共用，Sprint 6 评审时页面空白了半分钟", impact: "低但会重复", owner: "无",
        plan: "Sprint 6 回顾会的第三条改进，待认领", status: ->(_) { "无人认领" }, refs: "" },
      { id: "R13", since: 4, what: "向量库客户端升级（#121）在三次回顾会上都被提起，现在只有第一步有人认领", impact: "低但在累积", owner: "{bob}",
        plan: "Bob 先列出回归用例清单；他周三起请假，之后需要有人接", status: ->(_) { "刚起步" }, refs: "#121" }
    ].freeze

    RETRO = {
      1 => { days: [-77, -66], commit: "20", velocity: "18", goal: "推理服务与网关可跑通",
             good: "站会真的只有十五分钟；PR 评审很快，Frank 评审时讲得清楚。",
             items: [["进迭代前每个故事都带上验收标准", "{ada}", "已落实，Sprint 2 回顾里没有再提返工"],
                     ["搭一个常驻的演示环境", "{frank}", "做过一版，Sprint 4 和 Sprint 6 的评审会上都被冲掉过"],
                     ["缺陷清单没人看，需要有人每周梳理一次", "无", "无人认领"]] },
      2 => { days: [-63, -52], commit: "24", velocity: "22", goal: "文档上传与解析",
             good: "样本文档集让每次改动都有对照；验收标准写完再开工，没有返工。",
             items: [["站会用计时器，十五分钟到就停", "{sam}", "已落实"],
                     ["估点前先翻一遍同类任务的历史实际工时", "{ben}", "没有改变结果：Sprint 5 统计出同类任务实际是估算的 1.6 倍"],
                     ["CI 提速：缓存依赖、拆掉不必要的步骤", "无", "无人认领"]] },
      3 => { days: [-49, -38], commit: "26", velocity: "25", goal: "向量库与切片基线",
             good: "v1.0 发布没出大事；向量库选型当天就出了结论。",
             items: [["容量表里加上值班扣减", "{sam}", "已落实"],
                     ["向量库踩坑笔记写到维基", "{frank}", "维基里至今没有这一页"],
                     ["线上告警阈值调整并通知大家", "{bob}", "已落实，见[[监控与告警]]"]] },
      4 => { days: [-35, -24], commit: "28", velocity: "27", goal: "引用溯源与幻觉拦截",
             good: "流式出字适合演示；向量库部署比估的顺；评测集开始有用，改切片能立刻看到数。",
             items: [["评审队列里挂二十四小时提醒", "{sam}", "已落实，Sprint 6 时 PR 平均等待 11 小时"],
                     ["演示环境加锁，演示前不部署", "{frank}", "Sprint 6 评审会上演示页面仍被冲掉过"],
                     ["评估升级向量库客户端", "无", "无人认领，#121 在这之后才建"]] },
      5 => { days: [-21, -10], commit: "31", velocity: "31", goal: "商业化闭环",
             good: "引用溯源提前一天完成；评测集让回归更有底气。",
             items: [["估算时标出同类任务的历史倍数", "{ben}", "休假前没来得及做，Sprint 6 回顾又提了一次"],
                     ["把测试提前介入写进迭代流程", "{sam}", "已落实，见 {adr:testearly} 和[[测试策略]]"],
                     ["评测集的持续维护", "无", "无人认领"]] },
      6 => { days: [-7, 4], commit: "38", velocity: "29", goal: "协作编辑与分享",
             good: "Quinn 一周接了五个包，节奏没乱；提测提前了，#79 是迭代中段就被测出来的，不是评审前一天。",
             items: [["#121 升级向量库客户端：先把需要回归的用例清单列出来", "{bob}", "已认领，Bob 周三起请假，只能起个头"],
                     ["#56 #92 按同类乘 1.6 重新估算", "{ben}", "已认领，Sprint 7 计划会前给出"],
                     ["评审会用独立的演示环境，不和开发环境共用", "无", "无人认领"]] }
    }.freeze

    def risk_register
      versions = [[-63, "16:00", "建立风险登记"], [-14, "15:00", "记入计费相关风险"], [-5, "17:00", "周中同步会之后更新"], [2, "16:30", "待办梳理会之前更新"],
                  [4, "17:40", "Sprint 6 评审会之后更新"]].map do |day, hm, note|
        [day, hm, :sam, risk_text(day), note]
      end
      write_page("风险登记", versions)
    end

    def risk_text(as_of)
      rows = RISKS.select { |risk| risk[:since] <= as_of }.map do |risk|
        "| #{risk[:id]} | #{risk[:what]} | #{risk[:impact]} | #{risk[:owner]} | #{risk[:plan]} | #{risk[:status].call(as_of)} | #{risk[:refs]} |"
      end
      <<~MD
        # 风险登记

        每周一和每次计划会之前由 {sam} 更新。登记的是"可能发生、发生了会影响交付"的事，已经发生的问题请直接记成工作包。

        | 编号 | 风险 | 影响 | 负责人 | 应对 | 状态 | 关联 |
        |---|---|---|---|---|---|---|
        #{rows.join("\n")}

        关闭的风险不删，状态改成"已关闭"并写关闭原因。相关决定见[[决定记录：详述]]。
      MD
    end

    def retrospectives
      versions = [[-35, "16:30", "补记 Sprint 1 到 3", 3], [-24, "17:30", "记入 Sprint 4", 4], [-10, "17:20", "记入 Sprint 5", 5],
                  [4, "17:10", "记入 Sprint 6", 6]].map do |day, hm, note, upto|
        [day, hm, :sam, retro_text(upto), note]
      end
      write_page("迭代回顾汇总", versions)
    end

    def retro_text(upto)
      sections = (1..upto).map { |n| retro_section(n) }
      recurring = []
      recurring << "- 演示环境：Sprint 1 要求搭常驻环境，Sprint 4 又被覆盖、加了锁#{upto >= 6 ? '，Sprint 6 评审会上又被冲掉，这次的改进没人认领' : ''}。" if upto >= 4
      recurring << "- #121 向量库客户端升级：Sprint 4、Sprint 5#{upto >= 6 ? '、Sprint 6' : ''} 的回顾会都提到，至今没有排进任何迭代。" if upto >= 5
      recurring << "- 估算偏乐观：Sprint 2、Sprint 5#{upto >= 6 ? '、Sprint 6' : ''} 都提过，同类任务实际工时约为估算的 1.6 倍。" if upto >= 5
      unowned = (1..upto).sum { |n| RETRO.fetch(n)[:items].count { |item| item[1] == "无" } }
      recurring << "- 到目前为止有 #{unowned} 条改进没有人认领，认领了的基本都落实了。" if upto >= 5
      <<~MD
        # 迭代回顾汇总

        每次回顾会产出三条改进，每条写清楚谁认领、做到了没有。认领人空着的，下次计划会先问有没有人接。

        #{recurring.empty? ? '' : "## 反复被提起的事\n\n#{recurring.join("\n")}\n"}
        #{sections.reverse.join("\n")}
      MD
    end

    def retro_section(number)
      data = RETRO.fetch(number)
      rows = data[:items].map { |what, owner, state| "| #{what} | #{owner} | #{state} |" }
      <<~MD
        ## Sprint #{number}（{d:#{data[:days].first}} 至 {d:#{data[:days].last}}）

        迭代目标：#{data[:goal]}。承诺 #{data[:commit]} 点，完成 #{data[:velocity]} 点。

        做得好：#{data[:good]}

        | 改进 | 认领人 | 落实情况 |
        |---|---|---|
        #{rows.join("\n")}
      MD
    end

    GLOSSARY = {
      product: [
        ["知识库", "用户上传资料后形成的集合，写作时的依据都来自它。", "不叫\"资料库\""],
        ["切片", "资料入库前按标题和长度切成的段落，检索的最小单位。", "#60"],
        ["召回", "按问题从知识库里找出相关切片。", ""],
        ["引用溯源", "生成内容里的每个论断都能点回原文位置。", "#64"],
        ["幻觉拦截", "没有依据的内容降级成提示，而不是照常输出。", "#65"],
        ["置信度阈值", "检索分数低于它时触发幻觉拦截。", "#67"],
        ["模型降级", "主模型不可用或超时时切到备用模型，用户会看到提示文案。", "#55 #90；与\"套餐降级\"不是一回事"]
      ],
      billing: [
        ["配额", "套餐里每月可用的调用量。", "不叫\"额度\""],
        ["用量", "实际发生的调用量，按 token 折算。", "#73"],
        ["预扣与结算", "请求开始时先扣一个估计值，结束后按实际用量补扣或退还。", "{adr:reserve}"],
        ["超扣", "并发请求让同一账号被多扣。", "#100"],
        ["套餐降级", "用户从高档套餐换到低档，权益要随之回收。", "#103；与\"模型降级\"不是一回事"],
        ["试用期", "新账号 14 天，到期后调用必须被拒绝。", "#79"]
      ],
      team: [
        ["提测", "开发完成当天把工作包状态改成\"测试中\"，不等到迭代末。", "{adr:testearly}"],
        ["压线", "离硬日期的缓冲不足一个迭代，Sprint 7 的 v1.1 就是。", ""],
        ["黄金集", "人工标注过的评测集，改检索或改提示词之前都要在它上面跑一遍。", "#63"],
        ["断流", "长文生成中途流式输出中断。", "#47"],
        ["红线", "计费和权限相关的缺陷，一律从 P0 起评级。", "[[缺陷分级标准]]"],
        ["带过去", "迭代结束时没完成的工作包，原样带入下个迭代，并在计划会上重新确认。", ""]
      ],
      wording: [
        ["知识库", "资料库、文件夹", "界面、文档、公告一律用\"知识库\""],
        ["引用溯源", "出处追踪、来源定位", "可以简称\"溯源\"，不用英文"],
        ["套餐", "订阅计划、会员", "含义是价格档位，不是用户身份"],
        ["配额", "额度、限额", ""],
        ["团队版", "企业版、协作版", "v2.0 的正式名称"],
        ["评审会", "演示会、验收会", "迭代末的演示会议"],
        ["扫描件", "图片版 PDF", "提示文案里写\"这是扫描件，暂不支持文字识别\""]
      ]
    }.freeze

    def glossary
      versions = [[-59, "11:00", :sam, glossary_text(:early), "建立术语表"],
                  [-17, "16:20", :ada, glossary_text(:billing), "补充计费相关术语和统一用词"],
                  [-4, "15:10", :sam, glossary_text(:full), "加入团队自己的说法，给新人读"]]
      write_page("术语表", versions)
    end

    def glossary_text(stage)
      table = ->(rows, headers) { "| #{headers.join(' | ')} |\n|#{'---|' * headers.size}\n#{rows.map { |row| "| #{row.join(' | ')} |" }.join("\n")}" }
      parts = ["# 术语表\n\n写文档、写公告、写评论时用这里的说法。新成员先读这一页和[[决定记录]]。\n"]
      parts << "## 产品术语\n\n#{table.call(GLOSSARY[:product], %w[词 含义 备注])}\n"
      parts << "## 计费术语\n\n#{table.call(GLOSSARY[:billing], %w[词 含义 备注])}\n" unless stage == :early
      parts << "## 团队自己的说法\n\n#{table.call(GLOSSARY[:team], %w[词 含义 备注])}\n" if stage == :full
      wording = stage == :full ? GLOSSARY[:wording] : GLOSSARY[:wording].first(3)
      parts << "## 统一用词\n\n写作时用左边，避免右边。\n\n#{table.call(wording, %w[用 避免 说明])}\n" unless stage == :early
      parts.join("\n")
    end

    def velocity_baseline
      versions = [[-38, "17:00", "记入 Sprint 3", 3], [-24, "17:40", "记入 Sprint 4", 4], [-10, "17:30", "记入 Sprint 5", 5],
                  [4, "17:20", "记入 Sprint 6", 6]].map do |day, hm, note, upto|
        [day, hm, :sam, velocity_text(upto), note]
      end
      write_page("速度与估算基线", versions)
    end

    def velocity_text(upto)
      rows = (1..upto).map do |n|
        data = RETRO.fetch(n)
        "| Sprint #{n} | #{data[:commit]} | #{data[:velocity]} | #{data[:commit].to_i - data[:velocity].to_i} |"
      end
      recent = upto >= 6 ? "最近三个迭代（Sprint 4 到 6）平均 29 点。Sprint 6 承诺 38 点，实际完成 29 点，缺口 9 点带入 Sprint 7。" : "最近三个迭代的平均速度是计划会承诺的上限。"
      extra = upto >= 5 ? "\n## 估算偏差\n\n续写和 RAG 类任务，实际工时是估算的 1.6 倍（12 个已关闭任务的样本）。其他类型没有看到系统性偏差。计划这类任务时先乘 1.6，或者拆到 3 点以内。\n" : ""
      <<~MD
        # 速度与估算基线

        ## 点数与工时

        故事点用斐波那契数列（1、2、3、5、8、13）。1 点约 3 到 4 小时；13 点的故事应当在梳理会上拆开，见[[待办梳理与拆分约定]]。

        ## 各迭代速度

        | 迭代 | 承诺 | 完成 | 结转 |
        |---|---:|---:|---:|
        #{rows.join("\n")}

        #{recent}
        #{extra}
        速度只用来决定下个迭代承诺多少，不用来比较人。
      MD
    end

    def test_strategy
      versions = [[-33, "14:00", :sam, test_text(false), "建立测试策略"],
                  [-10, "17:50", :sam, test_text(true), "加入提测规则和计费回归"]]
      write_page("测试策略", versions)
    end

    def test_text(with_rules)
      rules = with_rules ? <<~'MD' : ""

        ## 提测

        开发完成当天把工作包状态改成"测试中"，并在评论里写清楚怎么验证（{adr:testearly}）。缺陷不要攒到迭代末。

        ## 计费和权限的额外要求

        1. 涉及计费、权限的改动需要 2 人评审。
        2. 改动后跑对账脚本，对比前后账单总额。
        3. 配额扣减的改动必须带并发用例（32 并发为基线）。
        4. 缺陷从 P0 起评级，见[[缺陷分级标准]]。
      MD
      <<~MD
        # 测试策略

        ## 分层

        | 层 | 谁写 | 什么时候跑 | 目标 |
        |---|---|---|---|
        | 单元测试 | 开发 | 每次提交 | 逻辑正确 |
        | 集成测试 | 开发 | 每次合并 | 服务之间的约定不破 |
        | 端到端 | 测试 | 提测时和发布前 | 用户路径走得通 |
        | 评测集 | 算法 | 改检索或提示词之前 | 召回和忠实度不退步 |

        ## 评测集

        黄金集见 #63，目前 412 条。中文长文样本不够，补充在 #98。改检索、改切片、改提示词之前，必须在黄金集上跑一次并把结果贴在工作包里。

        ## 发布前

        回归范围以[[v1.1 发布说明（草稿）]]里列出的条目为准。v1.0 的结果见 {doc:v1.0 测试报告}。
        #{rules}
      MD
    end

    def user_journeys
      versions = [[-21, "11:00", :fiona, journey_text(false), "整理两条主要旅程"],
                  [-3, "15:30", :ada, journey_text(true), "加上试用到付费这一条"]]
      write_page("用户旅程", versions)
    end

    def journey_text(with_upgrade)
      upgrade = with_upgrade ? <<~'MD' : ""

        ## 旅程三：试用到付费

        | 步骤 | 用户做什么 | 现在的体验 | 工作包 |
        |---|---|---|---|
        | 1 | 注册后试用 14 天 | 试用期内不限次数 | |
        | 2 | 用到配额八成 | 收到配额告警（UI 在做） | #76 |
        | 3 | 到期或配额用尽 | 必须被拒绝并提示升级（目前到期后仍可调用，已登记缺陷） | #79 |
        | 4 | 升级套餐 | 升级当月的配额口径还没有定论 | #74 |
        | 5 | 查看账单 | 账单历史排在后面 | #77 |
      MD
      <<~MD
        # 用户旅程

        用来对齐"用户在哪一步会卡住"。画像见[[用户画像]]。

        ## 旅程一：专业写作者（P1）

        | 步骤 | 用户做什么 | 现在的体验 | 工作包 |
        |---|---|---|---|
        | 1 | 上传资料 | PDF、DOCX、Markdown 可以；扫描件会被提示暂不支持 | #58 #62 |
        | 2 | 按选题提问、写作 | 回答带出处，点击可回原文 | #64 #66 |
        | 3 | 续写长文 | 章节衔接偶尔断裂 | #91 #92 |
        | 4 | 找回旧对话 | 按关键字搜索历史对话 | #86 |
        | 5 | 导出交付 | Word、PDF、Markdown；批注暂时带不出去 | #83 #112 #113 |

        ## 旅程二：团队内容岗（P2）

        | 步骤 | 用户做什么 | 现在的体验 | 工作包 |
        |---|---|---|---|
        | 1 | 建共享知识库 | 权限只有知识库和文档两层 | #69 |
        | 2 | 多人写同一篇 | 协同编辑还在做，光标同步有延迟 | #81 #108 |
        | 3 | 评论和提及 | 评论里 @ 的通知在做 | #82 #110 |
        | 4 | 分享给外部审稿 | 只读链接 | #84 |
        #{upgrade}
      MD
    end

    def meeting_archive
      write_page("会议纪要归档", [[-30, "10:20", :sam, meeting_archive_text(-30), "建立归档索引"],
                                [4, "17:50", :sam, meeting_archive_text(4), "补上 Sprint 6 的会议"]])
    end

    def meeting_archive_text(as_of)
      cutoff = t(as_of, "23:59")
      meetings = Meeting.where(project:).where(start_time: ..cutoff).order(:start_time)
      rows = meetings.map { |meeting| "| #{meeting.start_time.in_time_zone.strftime('%-m月%-d日')} | meeting##{meeting.id} | #{meeting.state == 'closed' ? '已记录' : '待补'} |" }
      <<~MD
        # 会议纪要归档

        所有迭代会议的纪要都在会议模块里，这一页只做索引。每场会议结束后 24 小时内由主持人补齐结论和行动项。

        | 日期 | 会议 | 纪要 |
        |---|---|---|
        #{rows.join("\n")}

        决定类的结论同时记入[[决定记录]]。
      MD
    end

    def tech_debt
      write_page("技术债清单", [[-21, "10:30", :ben, tech_debt_text(false), "建立清单，先放 #121"],
                              [-10, "17:40", :ben, tech_debt_text(true), "Sprint 5 回顾后更新"]])
    end

    def tech_debt_text(after_retro)
      latest = after_retro ? "Sprint 4、Sprint 5 回顾会都提到，决定 v1.1 之后再做" : "Sprint 4 回顾会提到"
      <<~MD
        # 技术债清单

        技术债不另立项目，登记在这里，真要做的时候再建工作包。排期时看"最近提起"一栏，提得越多越该排。

        | 债务 | 影响 | 状态 | 最近提起 | 工作包 |
        |---|---|---|---|---|
        | 向量库客户端升级 | 新版本的检索接口有变化，不升级会越拉越远；升级要回归全部检索用例（约 1.5 个工作日） | 搁置 | #{latest} | #121 |
        | 中文长文评测样本不足 | 召回评测对长文偏乐观 | 进行中 | Sprint 5 | #98 |
        | staging 夜间重置脚本偶发失败 | 早上的测试环境数据不干净 | 未登记 | Sprint 2 回顾 | |
        | SSE 断线重连缺端到端用例 | 断流类缺陷只能人工验证 | 未登记 | Sprint 4 | #47 |

        OCR 不是技术债，是产品范围，已经决定放到 v2.0，见 {adr:ocr}。
      MD
    end

    def refinement_rules
      write_page("待办梳理与拆分约定", [[-54, "15:40", :sam, <<~'MD', "建立约定"]])
        # 待办梳理与拆分约定

        待办梳理每周三下午，Product Owner 和研发参加。

        ## 进入迭代前要满足（Ready）

        1. 有验收标准，写在工作包描述里。
        2. 有估算，故事点用斐波那契数列。
        3. 依赖的人和工作包已经列出来。
        4. 大小合适：8 点以内直接进，13 点的故事应当在梳理会上拆开。

        ## 怎么拆

        - 按用户能看到的结果拆，不按前端后端分层。
        - 每个子故事独立可验收。
        - 拆开以后，父故事保留为史诗或特性，不再计点。

        ## 例外

        拆分会引入明显的接口工作时，可以不拆，但要在[[决定记录：详述]]里写明原因。
      MD
    end

    def release_notes_draft
      versions = [[-3, "14:00", :ada, release_notes_text(false), "起草 v1.1 发布说明"],
                  [2, "17:00", :sam, release_notes_text(true), "标出还没有确认的条目"]]
      write_page("v1.1 发布说明（草稿）", versions)
    end

    def release_notes_text(marked)
      tag = ->(text) { marked ? " [待确认：#{text}]" : "" }
      <<~MD
        # v1.1 发布说明（草稿）

        状态：草稿。计划发布日期：{d:11}（{v:v1.1 商业化版}）。发布前由 {ada} 逐条确认。

        ## 新增

        - 用量统计与配额扣减：每个账号的调用量按套餐实时统计和扣减（#73）。#{tag.call('是否能随 v1.1 发布，取决于 Sprint 7 计划会的决定')}
        - 套餐与升级流程：在应用内升级套餐（#74）。
        - 配额告警：用量接近配额时提醒，用尽时给出降级提示（#76）。#{tag.call('排在 #73 之后')}

        ## 修复

        - 试用到期后仍可无限调用（#79）。
        - 配额扣减并发超扣（#100）。
        - 支付回调重复入账（#104）。

        ## 已知限制

        - 扫描件暂不支持文字识别，OCR 计划在 v2.0 提供。
        - 多人同时编辑属于 v2.0 团队版，不在 v1.1 范围内。

        ## 升级须知

        升级套餐当月的配额怎么计算，口径尚未定稿。#{tag.call('Ada 在论坛里答应过给出口径，见 ' + '{m:升级套餐后，当月配额怎么算？}')}

        检查项见 {doc:v1.1 发布检查清单}。
      MD
    end

    def v2_scope
      write_page("v2.0 团队版范围（草案）", [[-4, "16:00", :ada, <<~'MD', "起草范围"]])
        # v2.0 团队版范围（草案）

        目标：让内容团队多人一起写。Beta：{d:39}，正式版：{d:67}。

        ## 肯定要做

        | 能力 | 工作包 | 说明 |
        |---|---|---|
        | 多人同时编辑 | #81 | 拆分方式待定，见 {adr:split} |
        | 评论与提及 | #82 | |
        | 公开分享链接 | #84 | |
        | 团队席位与成员管理 | #78 | |
        | 知识库权限 | #69 | 先做两层 |
        | OCR | | 见 {adr:ocr} |

        ## 候选，还没有定

        - 导出保留批注：一家出版社编辑团队提出，愿意为团队版付费。批注类型还没有跟客户确认。
        - 写作模板市场：#85，来自一家内容机构。只有一个客户提过。
        - 团队管理员的用量仪表盘：依赖 #101。

        ## 依据

        - 内测问卷（42 份）：19 份表示愿意为团队版付费，14 份要看价格。
        - 论坛"用户反馈"和"产品想法"里的讨论。
      MD
    end
  end
end
