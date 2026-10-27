# frozen_string_literal: true

# rubocop:disable Layout/LineLength, Metrics/AbcSize, Metrics/PerceivedComplexity

require "zlib"
require "base64"
require_relative "support"

module DemoSeed
  # Pull requests, check runs and GitHub users for the quill demo (设定书 §6).
  #
  # Repositories: quill-team/quill-core (inference, gateway, retrieval, billing) and quill-team/quill-web (editor,
  # collaboration, UI). 45 PRs: 31 merged, 9 open, 5 closed unmerged. Work packages are linked the way the GitHub
  # integration does it: every "OP#n" found in title or body. Merge times sit minutes before the work package's first
  # move to 开发完成/测试中/已关闭, taken from the work package journals, so they follow whatever Backbone produced.
  #
  # Deliberate material for the demo
  # - Wrong link: quill-core PR for #79 (试用到期后配额检查生效, Quinn) is titled and described with OP#68, so it is linked
  #   to #68 (跨文档同名章节溯源) and #79 has no PR; #68 has two PRs.
  # - Failing checks at the latest run: #100 (race test, open), #73 (draft, stale since the last push), #330 (draft),
  #   #75 (Quinn, lint, open), #104 first attempt (integration test, closed), #121 (retrieval regression, closed).
  #   #108 has a flaky e2e that went red once and green on re-run.
  # - Proxy merges: Frank merges every PR of Quinn (no merge right yet); Frank merges #55 although Bob wrote it.
  # - Replaced attempts: #104 (closed first PR), #55 (static-weight approach), #64 (anchor approach), #81 (CRDT spike).
  #
  # GitHub user <-> host user (one to one, login = first-last): ada-nakamura, sam-okafor, frank-delgado, fiona-walsh,
  # bob-fischer, ben-iversen, mia-petrova, quinn-adeyemi. Committers are the work package assignees. Commits per PR are not
  # stored by the integration, so they only show up as additions/deletions/changed files.
  #
  # Two PRs (#409 -> #62, #412 -> #94) are created by AssistantSeed::Community; they are adopted and rewritten here.
  class Git
    include Support

    ORG = "quill-team"
    REPOS = { core: "quill-core", web: "quill-web" }.freeze
    CHECKS = { core: %w[lint unit-test integration-test], web: %w[lint unit-test e2e] }.freeze
    ADOPTED = { 62 => 9_000_409, 94 => 9_000_412 }.freeze
    ACTIONS_APP_ID = 15_368
    CHECK_SECONDS = { "lint" => 45..70, "unit-test" => 150..260, "integration-test" => 380..560, "e2e" => 520..700 }.freeze
    STATUS_IDS = { doing: 7, devdone: 8, testing: 9, closed: 12 }.freeze

    PEOPLE = {
      ada: ["ada-nakamura", "A", [196, 90, 60]], sam: ["sam-okafor", "S", [46, 125, 110]],
      frank: ["frank-delgado", "F", [60, 90, 170]], fiona: ["fiona-walsh", "F", [170, 70, 130]],
      bob: ["bob-fischer", "B", [200, 120, 40]], ben: ["ben-iversen", "B", [90, 60, 160]],
      mia: ["mia-petrova", "M", [40, 140, 150]], quinn: ["quinn-adeyemi", "Q", [120, 140, 50]]
    }.freeze

    SIZES = {
      xs: { add: 8..40, del: 2..12, files: 1..2, cm: 0..1, rc: 0..2, life: 6 },
      s: { add: 40..120, del: 5..30, files: 2..4, cm: 1..2, rc: 1..4, life: 20 },
      m: { add: 120..350, del: 20..90, files: 4..9, cm: 2..4, rc: 3..9, life: 40 },
      l: { add: 350..900, del: 60..250, files: 8..18, cm: 3..6, rc: 6..15, life: 70 },
      xl: { add: 900..2400, del: 150..600, files: 15..40, cm: 5..9, rc: 10..22, life: 120 }
    }.freeze

    LABEL_TYPES = {
      "fix" => %w[bug d73a4a], "feat" => %w[enhancement a2eeef], "chore" => %w[chore fef2c0],
      "docs" => %w[documentation 0075ca], "test" => %w[tests bfd4f2], "spike" => %w[spike d4c5f9]
    }.freeze
    AREA_COLORS = %w[5319e7 0e8a16 1d76db b60205 fbca04 006b75 c2e0c6 e99695].freeze

    FONT = {
      "A" => %w[01110 10001 10001 11111 10001 10001 10001], "S" => %w[01111 10000 10000 01110 00001 00001 11110],
      "F" => %w[11111 10000 10000 11110 10000 10000 10000], "B" => %w[11110 10001 10001 11110 10001 10001 11110],
      "M" => %w[10001 11011 10101 10101 10001 10001 10001], "Q" => %w[01110 10001 10001 10001 10101 10010 01101],
      "C" => %w[01110 10001 10000 10000 10000 10001 01110], "I" => %w[01110 00100 00100 00100 00100 00100 01110]
    }.freeze

    # id: work package that drives the timeline; ref lines come from "OP#n" in title/b. Open PRs carry open: [day, hm, day, hm].
    PULLS = [
      # Sprint 1
      { id: 202, repo: :core, who: :frank, sz: :l, rev: %i[bob mia], title: "feat(inference): 本地部署开源基座模型，命令行可完整推理 (OP#202)",
        b: ["新增 serving 目录，封装模型加载与推理入口", "提供 quill infer 子命令，输出完整回复与耗时"], t: "内网 GPU 机器上跑通 20 条样例，显存占用约 14GB" },
      { id: 206, repo: :core, who: :bob, sz: :m, rev: %i[frank], title: "feat(gateway): 路由转发与上游健康探测 (OP#206)",
        b: ["按路径转发到推理服务，上游不健康时摘除节点", "探测间隔与失败阈值走配置"], t: "本地起两个假上游，手动停掉一个，请求自动落到另一个" },
      { id: 213, repo: :core, who: :bob, sz: :xs, rev: %i[frank], title: "fix(gateway): 上游超时后释放连接 (OP#213)",
        b: ["超时分支补上连接归还，避免连接池被占满"], t: "并发 20 压测 30 分钟，连接数稳定在 12 以内" },
      { id: 211, repo: :web, who: :fiona, sz: :s, rev: %i[bob], title: "feat(chat): 对话面板对接网关，联调鉴权头与错误码 (OP#211)",
        b: ["面板请求带上网关要求的鉴权头", "401、429、504 分别映射成面板里的提示"], t: "对着测试网关手动点过三种错误" },
      # Sprint 2
      { id: 222, repo: :core, who: :bob, sz: :m, rev: %i[frank ben], title: "feat(upload): 分片上传接口与对象存储 (OP#222)",
        b: ["分片上传、合并与校验和", "文件落对象存储，返回文档编号"], t: "50MB 文件分 10 片上传，校验和一致" },
      { id: 223, repo: :core, who: :ben, sz: :m, life: 90, rev: %i[frank], title: "feat(parser): PDF 文本层提取，去页眉页脚与断行连字符 (OP#223)",
        b: ["用版面坐标识别页眉页脚", "合并跨行断开的单词，保留段落边界"], t: "拿 12 份真实 PDF 对过，页眉页脚基本去干净，两份双栏排版还有错行" },
      { id: 235, repo: :core, who: :bob, sz: :s, rev: %i[frank], title: "fix(upload): 超过 20MB 的文件上传失败时给出明确提示 (OP#235)",
        b: ["网关请求体上限与上传接口上限对齐", "超限返回 413 和可读的错误文案"], t: "上传 25MB 文件，面板出现“文件超过 20MB”" },
      { id: 231, repo: :web, who: :fiona, sz: :m, rev: %i[ben], title: "feat(upload): 拖拽上传组件与分片进度条 (OP#231)",
        b: ["拖拽与点选两种入口", "各分片进度汇总成一条进度条"], t: "Chrome、Safari 各传一个 80MB 文件" },
      # Sprint 3
      { id: 246, repo: :core, who: :ben, sz: :l, life: 120, rev: %i[mia frank], title: "feat(retrieval): Faiss 索引批量构建与持久化 (OP#246)",
        b: ["批量构建索引并落盘，启动时加载", "构建过程分批写，失败可从断点继续"], t: "10 万片段建索引约 6 分钟，重启后加载 4 秒" },
      { id: 259, repo: :core, who: :ben, sz: :s, rev: %i[mia], title: "fix(retrieval): 重建索引时并发检索读到半成品 (OP#259)",
        b: ["重建写到临时文件，完成后原子替换", "替换期间读请求仍走旧索引"], t: "重建的同时 50 并发检索，没有再出现空结果" },
      { id: 257, repo: :core, who: :bob, sz: :m, rev: %i[frank], title: "feat(auth): API Key 哈希存储与轮换，旧 Key 有宽限期 (OP#257)",
        b: ["Key 只存哈希，创建后只展示一次明文", "轮换时旧 Key 保留 24 小时宽限期"], t: "轮换后新旧 Key 都可用，24 小时后旧 Key 返回 401" },
      # Sprint 4 / 5
      { id: 47, repo: :core, who: :bob, sz: :s, rev: %i[frank fiona], title: "fix(stream): 长文本生成被网关切断后自动重连 (OP#47)",
        b: ["网关空闲超时从 120 秒调到 300 秒", "断流时返回可重连的错误码，前端据此重连"], t: "生成 3000 字，中途断网，恢复后接着生成" },
      { id: 61, repo: :core, who: :ben, sz: :m, rev: %i[mia], title: "chore(retrieval): 部署向量库并接入健康检查 (OP#61)",
        b: ["向量库的部署脚本与配置", "接入监控，连接数和查询耗时可见"], t: "预发环境部署两次，脚本幂等" },
      { id: 62, repo: :core, who: :ben, sz: :s, rev: %i[frank], title: "fix(parser): 扫描版 PDF 解析为空时给出明确提示 (OP#62)",
        b: ["检测到没有文本层时返回专门的错误码", "界面提示改为“扫描件暂不支持文字提取”"], t: "用两份扫描件和一份正常 PDF 对照" },
      { id: 66, repo: :web, who: :fiona, sz: :m, rev: %i[ben frank], title: "feat(citation): 点击引用后在原文高亮并滚动定位 (OP#66)",
        b: ["引用点击后滚动到对应段落并高亮", "原文过长时用段落锚点，不用字符偏移"], t: "手动点了 30 个引用，位置都对" },
      { id: 102, repo: :core, who: :bob, sz: :xs, rev: %i[frank], title: "fix(billing): 账单金额统一按分四舍五入 (OP#102)",
        b: ["和财务确认的口径：每条流水先取整再汇总"], t: "补了 9 个边界用例" },
      { id: 67, repo: :core, who: :mia, sz: :s, rev: %i[frank ben], title: "feat(guard): 检索分数低于阈值时不生成，提示没有依据 (OP#67)",
        b: ["阈值走配置，默认 0.42", "低于阈值直接返回“没有找到依据”"], t: "评测集 50 题里，无依据题的误答从 11 题降到 2 题" },
      # Sprint 6
      { id: 94, repo: :core, who: :ben, sz: :s, rev: %i[mia], title: "fix(parser): DOCX 合并单元格解析不再丢内容 (OP#94)",
        b: ["合并单元格的内容复制到被合并的每一格", "补了横向、纵向、混合三种合并的用例"], t: "拿客户给的两份样例文档比对" },
      { id: 343, repo: :core, who: :bob, sz: :xs, rev: %i[ben], title: "fix(gateway): 限流提示文案与 OpenAPI 文档一致 (OP#343)",
        b: ["网关限流提示改成文档里的那句话"], t: "对着文档逐条核对" },
      { id: 342, repo: :web, who: :fiona, sz: :s, rev: %i[ben], title: "fix(editor): 流式渲染结束后保留撤销栈 (OP#342)",
        b: ["流式结束时不再整体替换文档节点", "补了一条端到端用例覆盖“生成后撤销”"], t: "生成后连按三次撤销，回到生成前的状态" },
      { id: 86, repo: :web, who: :fiona, sz: :m, rev: %i[ben], title: "feat(chat): 对话历史按项目归档与关键字搜索 (OP#86)",
        b: ["会话按项目分组归档", "搜索支持标题与消息内容"], t: "300 条会话下搜索响应在 200ms 内" },
      { id: 108, repo: :web, who: :fiona, sz: :m, rev: %i[frank ben], flaky: %w[e2e], title: "fix(collab): 多人编辑时光标同步延迟降到 300ms 内 (OP#108)",
        b: ["光标位置改为增量推送并合并同一帧内的多次更新", "三人同时编辑时只推送发生变化的光标"], t: "三台电脑同时编辑，光标延迟约 180ms" },
      { id: 110, repo: :web, who: :fiona, sz: :m, rev: %i[bob], title: "feat(comment): 评论 @ 提及的站内与邮件通知 (OP#110)",
        b: ["被 @ 的人收到站内通知和邮件", "通知点开直接跳到评论位置"], t: "两个账号互相 @，站内与邮件都收到" },
      { id: 99, repo: :core, who: :quinn, sz: :m, rev: %i[ben frank], merger: :frank, title: "test(parser): 扫描件解析回归用例，覆盖无文本层、倾斜和混合页 (OP#99)",
        b: ["新增 9 个回归用例和 3 份样例文件", "样例文件放在 testdata 目录，体积控制在 2MB 内"], t: "本地全部通过。样例文件的命名规则我是照评测集那边的约定对的，不知道理解对不对" },
      { id: 54, repo: :web, who: :fiona, sz: :l, rev: %i[ben frank], title: "feat(chat): 对话会话保存、重命名与归档 (OP#54)",
        b: ["会话列表支持重命名、归档、恢复", "归档的会话默认折叠"], t: "手动走过重命名、归档、恢复三条路径" },
      { id: 74, repo: :web, who: :fiona, sz: :l, rev: %i[bob ada], title: "feat(billing-ui): 套餐对比与在线升级流程 (OP#74)",
        b: ["套餐差异对比表", "升级流程接入支付页，成功后刷新配额"], t: "测试环境走通升级；产品验收由 Ada 过目" },
      { id: 79, repo: :core, who: :quinn, sz: :s, rev: %i[bob frank], merger: :frank, title: "fix(billing): 试用到期后配额检查生效，拒绝继续调用 (OP#68)",
        b: ["网关在鉴权后检查试用是否到期", "到期账号返回 402 和升级入口"], t: "用到期账号调用，返回 402", refs: [68] },
      { id: 68, repo: :core, who: :quinn, sz: :s, rev: %i[ben frank], merger: :frank, title: "fix(citation): 跨文档同名章节的溯源按文档限定定位 (OP#68)",
        b: ["章节定位先限定文档编号，再匹配标题", "补了两篇文档同名章节的用例"], t: "照缺陷里的复现步骤点了一遍，不再跳到另一篇" },
      { id: 104, repo: :core, who: :bob, sz: :m, rev: %i[frank mia], title: "fix(billing): 支付回调幂等：按交易号去重并加唯一索引 (OP#104)",
        b: ["回调先按交易号查重，重复回调直接返回成功", "订单表加交易号唯一索引，迁移脚本可回滚"], t: "同一笔回调连发 5 次，订单只变更一次" },
      { id: 55, repo: :core, who: :bob, sz: :l, merger: :frank, rev: %i[frank mia], title: "feat(router): 模型路由与降级策略，按成本与延迟选择 (OP#55)",
        b: ["路由按成本权重和近 5 分钟延迟打分", "主模型连续失败 3 次自动降级到备用模型"], t: "压测中手动停主模型，30 秒内全部切到备用模型" },
      { id: 82, repo: :web, who: :fiona, sz: :l, rev: %i[ben bob], title: "feat(comment): 选中文字发评论，用 @ 提及同事 (OP#82)",
        b: ["选区评论与高亮", "@ 提及下拉按项目成员过滤"], t: "两人同时评论同一段文字，互不覆盖" },
      # Closed without merge
      { id: 104, key: :first_try, repo: :core, who: :bob, sz: :m, state: :closed, shift: 30, rev: %i[frank], cm: 5, rc: 6,
        title: "feat(billing): 支付回调幂等处理（首版）(OP#104)",
        b: ["回调进来先查订单状态再更新"], t: "本地单个回调正常",
        fail: { "integration-test" => ["TestPaymentCallbackIdempotent 失败", "同一笔回调并发两次，创建了两条订单；期望 1 条，实际 2 条"] },
        close_note: "先查后写有竞态，集成测试复现了重复订单。关闭，改用交易号唯一索引的方案重做。" },
      { id: 121, repo: :core, who: :bob, sz: :m, state: :closed, end: [-12, "17:20"], life: 55, rev: %i[mia], cm: 4, rc: 5,
        title: "chore(deps): 升级向量库客户端到 2.x (OP#121)",
        b: ["客户端升级并适配新的批量接口"], t: "仅跑了冒烟用例",
        fail: { "integration-test" => ["检索回归 12 条用例失败", "新版返回的分数尺度变了，阈值相关的 12 条回归用例不再成立"] },
        close_note: "回归用例要整体重标，本迭代排不下，先搁置，工作包保持 暂缓。" },
      { id: 55, key: :static, repo: :core, who: :bob, sz: :m, state: :closed, shift: 96, rev: %i[frank], cm: 8, rc: 10,
        title: "feat(router): 模型路由方案 A：静态权重（已废弃）(OP#55)",
        b: ["按固定权重在两个模型间分流"], t: "仅在本地验证",
        close_note: "评审会上定了按成本与延迟动态打分，静态权重不再做，关闭。" },
      { id: 64, key: :anchor, repo: :core, who: :frank, sz: :m, state: :closed, shift: 60, rev: %i[mia ben], cm: 6, rc: 7,
        title: "feat(citation): 引用溯源：论断锚点方案（已被取代）(OP#64)",
        b: ["在生成文本里埋锚点标记，回溯时按标记定位"], t: "能跑通单篇文档",
        close_note: "锚点在改写后会丢，换成段落编号方案，关闭后重做。" },
      { id: 81, key: :crdt, repo: :web, who: :fiona, sz: :l, state: :closed, end: [-9, "17:00"], life: 40, rev: %i[frank ben], cm: 7, rc: 11,
        title: "spike(collab): CRDT 原型（已废弃，改用 OT 方案）(OP#81)",
        b: ["用 CRDT 库做了两人同时编辑的原型"], t: "原型可用，三人以上包体积和内存都偏大",
        close_note: "原型体积太大，团队版先不引入，关闭。" },
      # Open
      { id: 73, repo: :core, who: :bob, sz: :l, draft: true, open: [-10, "14:05", -9, "16:40"], rev: %i[frank], cm: 3, rc: 2,
        title: "feat(billing): 用量统计与配额扣减（WIP）(OP#73)",
        b: ["按账号累计调用量，按套餐配额实时扣减", "用量写入流水，后续按天聚合"], t: "本地跑通单账号扣减，聚合逻辑还没写完",
        fail: { "unit-test" => ["usage_aggregator 3 个用例失败", "test_daily_rollup 在时区边界处少算一天；test_partial_refund 等 2 个用例失败"] } },
      { id: 100, repo: :core, who: :bob, sz: :s, open: [1, "15:20", 3, "11:05"], rev: %i[frank mia], cm: 3, rc: 4,
        title: "fix(billing): 配额扣减加行锁，消除并发超扣 (OP#100)",
        b: ["扣减改为 SELECT FOR UPDATE 后再写", "依赖 OP#73 的扣减接口"], t: "本地 50 并发正常；CI 的竞态用例还没过",
        fail: { "integration-test" => ["TestConcurrentDeduct 失败", "100 并发各扣 1，期望余额 0，实际 -20；行锁只覆盖了单实例，多实例部署下仍会超扣"] },
        earlier_fail: { "integration-test" => ["TestConcurrentDeduct 失败", "期望余额 0，实际 -37"] } },
      { id: 75, repo: :core, who: :quinn, sz: :m, open: [3, "10:15", 4, "16:30"], rev: %i[frank], cm: 6, rc: 14,
        title: "feat(billing): 计费事件流水表与对账口径 (OP#75)",
        b: ["新增计费事件流水表，每次扣减一条记录", "对账口径按财务给的 3 条规则实现"], t: "本地跑过，对账口径第 2 条我理解对吗？请 Frank 看一下",
        fail: { "lint" => ["代码风格检查未通过", "3 个问题：2 处缩进不一致，1 个未使用的变量"] } },
      { id: 88, repo: :core, who: :ben, sz: :m, open: [1, "11:00", 4, "10:30"], rev: %i[frank], cm: 2, rc: 5,
        title: "docs(api): 对外接口 OpenAPI 描述 (OP#88)",
        b: ["补全对外接口的请求、响应与错误码", "用示例请求校验文档与实现一致"], t: "文档校验通过" },
      { id: 116, repo: :core, who: :sam, sz: :s, open: [2, "14:30", 4, "15:10"], rev: %i[frank bob], cm: 2, rc: 3,
        title: "chore(release): v1.1 发布前检查脚本，含迁移预检、配额开关与回滚演练 (OP#116)",
        b: ["迁移预检脚本，发现不可逆迁移直接失败", "配额开关与回滚步骤写进 runbook"], t: "在预发环境演练过一次回滚" },
      { id: 69, repo: :core, who: :ben, sz: :xl, open: [-6, "10:00", 4, "18:05"], rev: %i[frank mia], cm: 9, rc: 22,
        title: "feat(kb): 知识库与文档两级权限 (OP#69)",
        b: ["知识库级与文档级权限模型，按成员或角色共享", "检索阶段按权限过滤候选片段"], t: "权限矩阵 24 个用例全绿；缓存失效部分另开任务做" },
      { id: 81, repo: :web, who: :fiona, sz: :xl, open: [-12, "10:30", 4, "17:55"], rev: %i[frank ben], cm: 8, rc: 17, running: %w[e2e],
        title: "feat(collab): 多人同时编辑：光标可见、内容不丢 (OP#81)",
        b: ["基于 OT 的协同编辑，服务端排序", "离线合并留到后续工作包"], t: "三人同时编辑 30 分钟，内容一致；离线合并未包含" },
      { id: 339, repo: :web, who: :fiona, sz: :m, draft: true, skip: %w[e2e], open: [3, "14:00", 4, "11:00"], rev: %i[ben], cm: 1, rc: 1,
        title: "chore(deps): 前端依赖升级与构建提速（WIP）(OP#339)",
        b: ["升级主要依赖，清理未使用的包", "构建缓存键改为按锁文件计算"], t: "本地构建从 7 分钟降到 3 分半，部分依赖还没升完" },
      { id: 330, repo: :core, who: :ben, sz: :m, draft: true, open: [2, "11:30", 4, "12:20"], rev: %i[frank], cm: 1, rc: 2,
        title: "fix(parser): 超长 PDF 分块解析，降低峰值内存（WIP）(OP#330)",
        b: ["按 50 页分块解析并及时释放", "合并阶段只保留文本，不保留版面对象"], t: "400 页 PDF 峰值内存还在 1.9GB",
        fail: { "unit-test" => ["test_large_pdf_peak_memory 失败", "峰值内存 1.9GB 超过上限 1.5GB"] } }
    ].freeze

    def call
      @runs = 0
      users = github_users
      reset_previous
      specs = PULLS.each_with_index.filter_map { |spec, index| plan(spec, index) }
      number_and_create(specs, users)
      say("git: #{GithubPullRequest.where(repository: repo_names).count} PRs, #{GithubCheckRun.count} check runs")
    end

    private

    def repo_names = REPOS.values.map { "#{ORG}/#{it}" }

    def github_users
      PEOPLE.each_with_index.to_h do |(key, (login, initial, color)), index|
        record = GithubUser.find_or_initialize_by(github_id: 4_200_100 + index)
        record.update!(github_login: login, github_html_url: "https://github.com/#{login}",
                       github_avatar_url: avatar(initial, color))
        [key, record]
      end
    end

    def reset_previous
      GithubPullRequest.where(repository: repo_names).find_each(&:destroy)
    end

    # --- planning ---------------------------------------------------------------------------------------------

    def plan(spec, index)
      work_package = WorkPackage.find_by(id: spec[:id])
      unless work_package
        say("git: skip PR for missing work package ##{spec[:id]}")
        return nil
      end

      rng = Random.new((index * 7919) + 13)
      size = SIZES.fetch(spec[:sz])
      state = spec[:state] || (spec[:open] ? :open : :merged)
      ending = ending_time(spec, state, work_package, rng)
      created = created_time(spec, state, work_package, ending, size, rng)
      spec.merge(rng:, size:, state:, ending:, created:, work_package:)
    end

    def ending_time(spec, state, work_package, rng)
      return ctx.at(spec[:open][2], spec[:open][3]) if state == :open
      return ctx.at(spec[:end][0], spec[:end][1]) if spec[:end]

      anchor = anchor_time(work_package)
      return fallback_time(work_package) unless anchor
      return working_hours(anchor - spec.fetch(:shift).hours, rng) if state == :closed

      candidate = anchor - rng.rand(20..170).minutes
      candidate = anchor - 15.minutes unless candidate.to_date == anchor.to_date
      [candidate, ctx.now - 1.hour].min
    end

    def fallback_time(work_package)
      day = work_package.due_date || ctx.today
      [ctx.at(day, "16:40"), ctx.now - 1.hour].min
    end

    def created_time(spec, state, work_package, ending, size, rng)
      return ctx.at(spec[:open][0], spec[:open][1]) if state == :open

      life = spec[:life] || size[:life]
      created = working_hours(ending - life.hours, rng)
      floor = work_package.start_date && ctx.at(work_package.start_date, "09:30")
      created = [created, floor].max if floor && floor < ending - 1.hour
      created = working_hours(ending - rng.rand(30..90).minutes, rng) if created >= ending - 20.minutes
      created
    end

    def working_hours(time, rng)
      time -= 1.day until ctx.weekday?(time.to_date)
      return time.change(hour: 17, min: rng.rand(0..45)) if time.hour > 18
      return time unless time.hour < 9

      previous = time - 1.day
      previous -= 1.day until ctx.weekday?(previous.to_date)
      previous.change(hour: 16, min: rng.rand(15..59))
    end

    def anchor_time(work_package)
      journals(work_package).find { |_, status| status.in?(STATUS_IDS.values_at(:devdone, :testing, :closed)) }&.first
    end

    def journals(work_package)
      @journals ||= {}
      @journals[work_package.id] ||= Journal.where(journable_type: "WorkPackage", journable_id: work_package.id)
                                            .order(:version).map { [it.created_at, it.data&.status_id] }
    end

    # --- creation ---------------------------------------------------------------------------------------------

    def number_and_create(specs, users)
      counters = Hash.new(0)
      specs.sort_by { it[:created] }.each do |spec|
        repo = spec[:repo]
        counters[repo] += counters[repo].zero? || !spec[:rng].rand(4).zero? ? 1 : 2
        create_pull(spec, counters[repo], users)
      end
    end

    def create_pull(spec, number, users)
      rng = spec[:rng]
      author = users.fetch(spec[:who])
      merger = users.fetch(spec[:merger] || spec[:who])
      merged = spec[:state] == :merged
      body = body_for(spec)
      attrs = pull_attributes(spec, number, author, merger, merged, body, rng)
      pull = adopted(spec) || GithubPullRequest.new
      pull.update!(attrs)
      pull.work_packages = linked_work_packages(spec[:title], body)
      create_checks(pull, spec)
      pull.update_columns(updated_at: spec[:ending], github_updated_at: spec[:ending])
    end

    def adopted(spec)
      return unless spec[:state] == :merged

      github_id = ADOPTED[spec[:id]]
      GithubPullRequest.find_by(github_id:) if github_id
    end

    def pull_attributes(spec, number, author, merger, merged, body, rng)
      size = spec[:size]
      repo = "#{ORG}/#{REPOS.fetch(spec[:repo])}"
      open = spec[:state] == :open
      {
        github_id: 8_000_000 + (spec[:repo] == :core ? 0 : 500_000) + number, number:, github_user: author,
        github_html_url: "https://github.com/#{repo}/pull/#{number}", repository: repo,
        repository_html_url: "https://github.com/#{repo}", state: open ? "open" : "closed", title: spec[:title], body:,
        draft: spec[:draft] || false, merged:, merged_by: (merger if merged), merged_at: (spec[:ending] if merged),
        merge_commit_sha: (Digest::SHA1.hexdigest("#{repo}/#{number}") if merged),
        comments_count: spec[:cm] || rng.rand(size[:cm]), review_comments_count: spec[:rc] || rng.rand(size[:rc]),
        additions_count: rng.rand(size[:add]), deletions_count: rng.rand(size[:del]), changed_files_count: rng.rand(size[:files]),
        labels: labels_for(spec[:title]), github_updated_at: spec[:ending], created_at: spec[:created], updated_at: spec[:ending]
      }
    end

    def labels_for(title)
      type, area = title.match(/\A(\w+)\(([\w-]+)\)/).captures
      name, color = LABEL_TYPES.fetch(type)
      [{ "color" => color, "name" => name }, { "color" => AREA_COLORS[area.sum % AREA_COLORS.size], "name" => area }]
    end

    def body_for(spec)
      refs = spec[:refs] || [spec[:id]]
      reviewers = spec[:rev].map { "@#{PEOPLE.fetch(it).first}" }.join(" ")
      lines = ["## 变更", *spec[:b].map { "- #{it}" }, "", "## 测试", spec[:t], "", "关联：#{refs.map { "OP##{it}" }.join(' ')}"]
      lines << "评审：#{reviewers}#{'（待评审）' if spec[:state] == :open}"
      lines << "合并：@#{PEOPLE.fetch(spec[:merger]).first} 代合并（#{PEOPLE.fetch(spec[:who]).first} 暂无合并权限）" if proxied?(spec)
      lines << "关闭说明：#{spec[:close_note]}" if spec[:close_note]
      lines.join("\n")
    end

    def proxied?(spec) = spec[:merger] && spec[:merger] != spec[:who] && spec[:who] == :quinn

    def linked_work_packages(title, body)
      ids = "#{title}\n#{body}".scan(/OP#(\d+)/).flatten.map(&:to_i).uniq
      WorkPackage.where(id: ids, project:).to_a
    end

    # --- check runs -------------------------------------------------------------------------------------------

    def create_checks(pull, spec)
      rng = spec[:rng]
      pushed = [spec[:ending] - rng.rand(25..70).minutes, spec[:created] + 10.minutes].max
      pushed = spec[:ending] - rng.rand(5..25).minutes if spec[:state] == :open
      CHECKS.fetch(spec[:repo]).each do |name|
        next create_flaky(pull, spec, name, pushed, rng) if spec[:flaky]&.include?(name)

        if spec[:earlier_fail]&.key?(name)
          create_run(pull, spec, name, pushed - 3.hours, rng, outcome: :failure, detail: spec[:earlier_fail][name])
        end
        create_run(pull, spec, name, pushed, rng, **outcome_for(spec, name))
      end
    end

    def outcome_for(spec, name)
      return { outcome: :failure, detail: spec[:fail][name] } if spec[:fail]&.key?(name)
      return { outcome: :running } if spec[:running]&.include?(name)
      return { outcome: :skipped } if spec[:skip]&.include?(name)

      { outcome: :success }
    end

    def create_flaky(pull, spec, name, pushed, rng)
      detail = ["#{name} 偶发失败", "WebSocket 连接被重置，与代码改动无关；重新运行通过"]
      create_run(pull, spec, name, pushed - 35.minutes, rng, outcome: :failure, detail:)
      create_run(pull, spec, name, pushed, rng, outcome: :success)
    end

    def create_run(pull, spec, name, started, rng, outcome:, detail: nil)
      @runs += 1
      id = 5_000_000 + @runs
      running = outcome == :running
      url = "https://github.com/#{pull.repository}/actions/runs/#{id}"
      completed = started + duration(name, rng).seconds
      title, summary = detail || summary_for(name, outcome, spec[:size], rng)
      GithubCheckRun.create!(
        github_pull_request: pull, github_id: id, github_html_url: url, details_url: url, app_id: ACTIONS_APP_ID,
        github_app_owner_avatar_url: app_avatar, name:, status: running ? "in_progress" : "completed",
        conclusion: (outcome == :running ? nil : outcome.to_s), output_title: title, output_summary: summary,
        started_at: started, completed_at: (completed unless running), created_at: started, updated_at: completed
      )
    end

    def duration(name, rng) = rng.rand(CHECK_SECONDS.fetch(name))

    def summary_for(name, outcome, size, rng)
      return ["已跳过", "本次改动不涉及界面，未运行"] if outcome == :skipped
      return ["运行中", "已排队，等待 runner"] if outcome == :running

      count = rng.rand(size[:files]) + 1
      case name
      when "lint" then ["代码风格检查通过", "0 个问题，检查了 #{count * 9} 个文件"]
      when "unit-test" then ["单元测试通过", "#{(count * 17) + 40} 个用例通过，0 个失败"]
      when "integration-test" then ["集成测试通过", "#{(count * 3) + 18} 个用例通过，0 个失败"]
      else ["端到端测试通过", "#{count + 11} 个场景通过，0 个失败"]
      end
    end

    # --- avatars ----------------------------------------------------------------------------------------------

    def avatar(letters, color) = png_data_uri(48, color, letters, 3)

    def app_avatar = @app_avatar ||= png_data_uri(48, [36, 41, 47], "CI", 2)

    def png_data_uri(size, color, letters, scale)
      bitmap = glyph_pixels(letters, scale)
      rows = Array.new(size) do |y|
        Array.new(size) do |x|
          alpha = ((size / 2.0) - Math.hypot(x - ((size - 1) / 2.0), y - ((size - 1) / 2.0))).clamp(0, 1)
          ink = bitmap[[x - ((size - bitmap_width(letters, scale)) / 2), y - ((size - (7 * scale)) / 2)]]
          (ink ? [255, 255, 255] : color).pack("C3") + [(alpha * 255).round].pack("C")
        end.join
      end
      "data:image/png;base64,#{Base64.strict_encode64(png(size, rows))}"
    end

    def bitmap_width(letters, scale) = (letters.size * 5 * scale) + ((letters.size - 1) * scale)

    def glyph_pixels(letters, scale)
      pixels = {}
      letters.each_char.with_index do |char, position|
        FONT.fetch(char).each_with_index do |row, y|
          row.each_char.with_index do |bit, x|
            next unless bit == "1"

            scale.times { |dy| scale.times { |dx| pixels[[(position * 6 * scale) + (x * scale) + dx, (y * scale) + dy]] = true } }
          end
        end
      end
      pixels
    end

    def png(size, rows)
      raw = rows.map { "\x00".b + it.b }.join
      chunk = ->(type, data) { [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N") }
      "\x89PNG\r\n\x1a\n".b + chunk.call("IHDR", [size, size, 8, 6, 0, 0, 0].pack("NNCCCCC")) +
        chunk.call("IDAT", Zlib::Deflate.deflate(raw)) + chunk.call("IEND", "".b)
    end
  end
end
# rubocop:enable Layout/LineLength, Metrics/AbcSize, Metrics/PerceivedComplexity
