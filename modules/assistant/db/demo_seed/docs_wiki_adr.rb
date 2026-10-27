# frozen_string_literal: true

module DemoSeed
  module DocsWikiAdr
    private

    ADR_INTRO = <<~'MD'
      # 决定记录：详述

      [[决定记录]] 是一张一页能读完的索引；这一页是每条决定的完整版。每条决定写清五件事：背景、考虑过的选项、结论、谁定的、关联的工作包。

      写法约定：

      1. 编号按决定的先后顺序，不重排，不删除。
      2. 被推翻或被取代的决定不删，状态里写明是被哪一条、哪个变化推翻的。
      3. 结论里要有原话的，直接引用，并注明出处。
      4. 有待办的决定，把待办和负责人写在结论后面。
    MD

    ADR_DEFS = [
      {
        key: :sse, title: "流式输出用 SSE，不用 WebSocket", day: -77, by: :frank, recorder: :sam, refs: "#44 #45 #47",
        background: "对话生成是服务端单向推送，前端只需要接收。Sprint 1 要在两周内打通主链路。",
        options: "1. WebSocket：双向，但要自己处理心跳和重连，网关也要改。\n2. SSE：单向，浏览器原生支持，走普通 HTTP，代理友好。\n3. 长轮询：简单，但首字延迟拿不到 800ms 内。",
        conclusion: "用 SSE。断线用 Last-Event-ID 续传。\n\n> Frank：SSE。双向用不上。（Sprint 1 计划会）",
        status: ->(_) { "有效" }
      },
      {
        key: :ratelimit, title: "网关限流推迟，等商业化再按套餐设计", day: -66, by: :ada, recorder: :sam, refs: "#45 #89",
        background: "Sprint 1 的网关只负责转发。有人提出现在就加限流，免得以后返工。",
        options: "1. 现在做统一限流：简单，但没有套餐概念，以后要重做。\n2. 推迟：等有商业化需求，按套餐设计限流。",
        conclusion: "选 2。网关限流推迟，等有商业化需求再按套餐设计。\n\n> 评审会结论：网关限流推迟，等有商业化需求再按套餐设计。（Sprint 1 评审会）",
        status: ->(_) { "已落实，限流策略由 #89 完成" }
      },
      {
        key: :pgvector, title: "向量库用 pgvector，暂不引入 Qdrant", day: -47, by: :frank, recorder: :sam, refs: "#61 #59 {m:为什么选 pgvector 而不是 Qdrant？}",
        background: "Sprint 3 的目标是向量库与切片基线。数据量预估在百万级切片以内，团队只有两个人熟悉运维。",
        options: "1. Qdrant：检索性能更好，要单独部署和备份。\n2. pgvector：和业务库同源，事务一致，运维成本低；千万级以后再评估。",
        conclusion: "用 pgvector。向量到千万级时再评估迁移，迁移方案另写，不在这一条里。\n\n小团队运维简单优先，这个取舍在论坛主题里被 Bob 确认过。",
        status: ->(_) { "有效" }
      },
      {
        key: :granularity, title: "引用溯源的粒度是段落，不做句子级", day: -33, by: :ada, recorder: :sam, refs: "#64 #66 #68",
        background: "Mia 提出两种粒度。句子级的定位更准，但切片要重做；段落级可以直接复用 Sprint 3 的切片。",
        options: "1. 句子级：用户体验最好，成本是重切、重建索引，约多两周。\n2. 段落级：用现有切片，定位到段落并高亮。",
        conclusion: "先做段落级，v1.1 之后再看用户是否真的嫌粗。\n\n> Ada：用户要的是能回到原文，不是精确到句子。那就这样：段落级。",
        status: ->(_) { "有效。跨文档同名章节会跳错位置，见 #68" }
      },
      {
        key: :fulltext, title: "对话历史搜索改用全文检索，不进向量库", day: [9, 13], recorded_day: -28, by: :ada, recorder: :sam, refs: "#86 {m:对话历史搜索：全文检索还是向量？}",
        background: "#86 的原型把会话摘要写进向量库，查询约 600 ms。Mia 在 3 万条会话样本上比较过：关键词类查询两者召回接近，向量的索引体积约是全文的 11 倍。",
        options: "1. 向量语义搜索：能支持\"上次那个关于定价的讨论\"这类说法，成本高。\n2. PostgreSQL 全文检索：快、便宜，语义类查询基本不可用。\n3. 两者并行：体验最好，复杂度翻倍。",
        conclusion: "改为全文检索，语义类查询暂不支持。9 月 13 日 Fiona 在论坛主题里确认，Ada 回复接受。\n\n> Ada：可以。那就这样：全文检索，负责人是我。中文分词方案我来确认，结论回到这个帖子。\n\n待办：确认生产库能否安装中文分词扩展，结论回写本条。负责人：Ada。",
        status: ->(_) { "有效。待办未回写" }
      },
      {
        key: :ledger, title: "计费事件流水只追加，对账靠重算", day: -20, by: :frank, recorder: :sam, refs: "#75 #102",
        background: "对账口径需要财务确认，口径可能变。如果流水能被改，每次口径变化都会留下说不清的差异。",
        options: "1. 流水可更正：对账简单，审计困难。\n2. 流水只追加，更正用冲正记录；对账时按口径重算。",
        conclusion: "流水只追加。口径变化时重算，不改历史。\n\n> Frank：流水只加不改。",
        status: ->(_) { "有效" }
      },
      {
        key: :rounding, title: "账单金额逐条折算后四舍五入到分", day: -17, by: :ada, recorder: :sam, refs: "#102 {m:账单金额取整口径}",
        background: "Bob 给出两种做法，月底差异约 0.3%。用户会拿明细去加总，总额对不上就是投诉。",
        options: "1. 汇总后再四舍五入：总额准，明细加起来可能差几分。\n2. 每条流水折算后四舍五入到分，月度总额等于明细之和。",
        conclusion: "选 2。\n\n> Ada：那就这样：每条流水折算后四舍五入到分，月度总额等于明细之和。",
        status: ->(_) { "有效" }
      },
      {
        key: :reserve, title: "配额扣减采用预扣加结算，网关不直接减", day: -13, by: :frank, recorder: :sam, refs: "#73 #100",
        background: "压测时 32 并发约 4% 的请求让同一账号超额扣减，原因是读余额和写余额不在一个事务里。",
        options: "1. 网关加分布式锁：快，但锁粒度大，拖慢所有请求。\n2. 网关只预扣，计费服务在请求结束后结算差额。\n3. 数据库行锁：简单，热点账号会排队。",
        conclusion: "选 2。#100 按计费类缺陷处理，起步就是 P0。\n\n> Frank：预扣加结算。别在网关里直接减。",
        status: ->(_) { "有效。#100 的修复依赖这条" }
      },
      {
        key: :ocr, title: "扫描件先在界面上提示，OCR 放到 v2.0", day: -10, by: :ada, recorder: :sam, refs: "#62 #99",
        background: "上传失败的 PDF 里大部分是扫描件。做 OCR 要选引擎、评估成本，v1.1 来不及。",
        options: "1. 现在做 OCR：覆盖面广，v1.1 日期保不住。\n2. 提示用户这是扫描件，暂不支持文字识别；OCR 放到 v2.0。",
        conclusion: "选 2。提示文案已随 v1.0.3 上线，#99 补回归用例。\n\n> Ada：决定：OCR 放 v2.0，先把提示写明白。",
        status: ->(_) { "有效" }
      },
      {
        key: :testearly, title: "测试提前介入：开发完成当天就提测", day: -10, by: :ada, recorder: :sam, refs: "Sprint 5 回顾会",
        background: "Sprint 5 的缺陷大多在迭代最后两天才被发现，修复挤占了下个迭代的开头。",
        options: "1. 保持现状，迭代末集中测试。\n2. 开发完成当天提测，状态用\"测试中\"，缺陷不要攒到迭代末。",
        conclusion: "选 2。从 Sprint 6 开始执行。Sam 在论坛里发过一次提醒，Ada 回复同意。",
        status: ->(_) { "有效" }
      },
      {
        key: :wholeedit, title: "多人同时编辑 #81 整体做完，不拆分", day: -7, by: :ada, recorder: :sam, refs: "#81 #108 #109",
        background: "Sprint 6 计划会上 Fiona 估 40 小时。光标同步、内容合并、离线冲突互相依赖，拆开会多出接口工作。",
        options: "1. 拆成三个故事，分三个迭代交付。\n2. 整体做，Sprint 6 内完成。",
        conclusion: "选 2。\n\n> Ada：我的意见是先整体做，不拆。做不完的话周中再看。",
        status: ->(as_of) { as_of >= 2 ? "已被后来的变化推翻（见 {adr:split}）" : "有效" }
      },
      {
        key: :permissions, title: "权限只做知识库级和文档级两层", day: -5, by: :ada, recorder: :sam, refs: "#69 #95",
        background: "#69 已经连续两个迭代没有完成，范围一直在变大：项目级、角色级、临时授权都被提过。",
        options: "1. 保留四层权限：完整，但做不完。\n2. 只做知识库级和文档级两层，成员或角色可共享。其余放到后面。",
        conclusion: "选 2。#69 的截止日顺延到本迭代末。\n\n出处：Sprint 6 周中同步会第 3 项。",
        status: ->(_) { "有效" }
      },
      {
        key: :routing, title: "模型路由先按成本、再按延迟排序", day: -5, by: :ada, recorder: :sam, refs: "#55 #89 #90",
        background: "备用模型切换的顺序影响账单。延迟差在 200 ms 以内用户感知不明显。",
        options: "1. 先按延迟：体验稳，成本高。\n2. 先按成本、再按延迟：成本低，高峰期可能慢一点。",
        conclusion: "选 2。降级时的提示文案见 #90。",
        status: ->(_) { "有效" }
      },
      {
        key: :wed73, title: "#73 周三提测，不再改期", day: 0, by: :ada, recorder: :sam, refs: "#73 #76 #116",
        background: "#73 用量统计第二次改期。财务终于回了对账口径，Bob 做完要对一遍。#76 配额告警 UI 要等 #73 的接口，周三提测，#76 才能周四开始。",
        options: "1. 再给 Bob 一次改期：宽松，但 #76 和发布检查清单都往后挤。\n2. 周三提测，不再改期；周三没提测，就谈 v1.1 的范围。",
        conclusion: "选 2。\n\n> Ada：那就这样：#73 周三提测，不再改期。周三没提测，周中同步会上再谈范围。",
        status: ->(as_of) { as_of >= 2 ? "条件已触发：{d:2} 没有提测，#73 带入 Sprint 7，范围问题移到 Sprint 7 计划会" : "有效，截止 {d:2}" }
      },
      {
        key: :split, title: "把 #81 拆成三个故事", day: 2, by: :ada, recorder: :sam, refs: "#81 #108 #109",
        background: "#81 已经逾期，13 点的故事在计划里一直占着整块容量。待办梳理会上有人建议拆分。",
        options: "1. 继续整体做：不用重新估算，但 Sprint 7 容量放不下。\n2. 拆成光标同步、内容合并、离线冲突三个故事，每个不超过 5 点。",
        conclusion: "建议拆成三个故事，由 Ada 在 Sprint 7 计划会上确认。这一条一旦确认，{adr:wholeedit} 作废。",
        status: ->(_) { "提议中，待 Sprint 7 计划会确认" }
      }
    ].freeze

    def decision_details
      dated = ADR_DEFS.map { |adr| [adr, adr_stamp(adr)] }.sort_by(&:last)
      backfilled, later = dated.partition { |adr, _| adr[:day].is_a?(Integer) && adr[:day] < -35 }.map { |group| group.map(&:first) }
      versions = [[-38, "16:30", :sam, adr_page(backfilled, -38), "补记前两条决定"]]
      later.each_with_index do |adr, index|
        written_on = adr[:day].is_a?(Integer) ? adr[:day] : adr[:recorded_day]
        versions << [written_on, adr_stamp(adr).strftime("%H:%M"), adr[:recorder],
                     adr_page(backfilled + later.first(index + 1), written_on), "记入 ADR-#{format('%03d', ADR_DEFS.index(adr) + 1)}"]
      end
      write_page("决定记录：详述", versions, parent: project.wiki.pages.find_by!(title: "决定记录"))
    end

    def adr_stamp(adr)
      day = adr[:day].is_a?(Integer) ? adr[:day] : adr[:recorded_day]
      t(day, adr[:day] == 2 ? "17:30" : "16:00")
    end

    def adr_page(adrs, as_of)
      sections = adrs.map { |adr| adr_section(adr, as_of) }
      "#{ADR_INTRO}\n#{sections.join("\n")}"
    end

    def adr_section(adr, as_of)
      id = format("%03d", ADR_DEFS.index(adr) + 1)
      <<~MD
        ## ADR-#{id} #{adr[:title]}

        | 状态 | #{adr[:status].call(as_of)} |
        |---|---|
        | 日期 | {d:#{adr[:day].is_a?(Integer) ? adr[:day] : "[#{adr[:day].join(',')}]"}} |
        | 决定人 | {#{adr[:by]}} |
        | 关联 | #{adr[:refs]} |

        **背景**　#{adr[:background]}

        **选项**

        #{adr[:options]}

        **结论**　#{adr[:conclusion]}
      MD
    end
  end
end
