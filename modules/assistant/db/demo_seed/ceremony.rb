# frozen_string_literal: true

# rubocop:disable Layout/LineLength
module DemoSeed
  class Ceremony
    include Support

    NAMES = { ada: "Ada", sam: "Sam", frank: "Frank", bob: "Bob", ben: "Ben", fiona: "Fiona", mia: "Mia", quinn: "Quinn" }.freeze
    CORE = %i[sam ada frank bob ben fiona].freeze
    TEAM = (CORE + %i[mia]).freeze
    AFTER_LOAN = %i[sam ada fiona bob ben quinn].freeze

    def call
      User.current = ctx.admin
      backdate_memberships
      meetings.each { build(it) }
      amendments.each { amend(it) }
      say("meetings=#{Meeting.where(project:).count} agenda_items=#{MeetingAgendaItem.where(meeting_id: Meeting.where(project:).select(:id)).count}")
    end

    private

    JOINED = { ada: -80, sam: -80, frank: -80, bob: -80, ben: -80, fiona: -80, mia: -70 }.freeze

    def backdate_memberships
      JOINED.each do |key, day|
        stamp = ctx.at(day, "09:00")
        Member.where(project:, principal: user(key)).where(created_at: (stamp + 1.second)..).update_all(created_at: stamp, updated_at: stamp)
      end
    end

    def dl(offset) = ctx.day_label(ctx.d(offset))

    def talk(*lines) = lines.map { "- #{it}" }.join("\n")

    def todo(who, text, due = nil)
      tail = due ? "（#{dl(due)}前）" : ""
      who ? "#{NAMES.fetch(who)}：#{text}#{tail}" : "无人认领：#{text}#{tail}"
    end

    def actions(*rows) = item("本次行动项", 5, talk(*rows.map { todo(*it) }))

    def item(title, minutes, notes = nil, by: nil, out: []) = { title:, min: minutes, notes:, by:, out: }

    def wp_item(id, minutes, notes = nil, by: nil, out: []) = { wp: id, min: minutes, notes:, by:, out: }

    def dec(text) = [:decision, text]

    def info(text) = [:information, text]

    def meeting(title, host, day, hm, minutes, invited, sections:, absent: [], tentative: [])
      { title:, host:, day:, hm:, minutes:, invited:, absent:, tentative:, sections: }
    end

    def meetings
      [*sprint_one, *sprint_two, *sprint_three, *sprint_four, *sprint_five]
    end

    def sprint_one
      [
        meeting("Sprint 1 计划会", :sam, -77, "09:30", 90, CORE, sections: [
                  ["开场", [
                    item("Scrum 的几条约定", 5, talk(
                      "Sam：先说规矩，不多。迭代两周，周一计划，周五评审加回顾，站会十五分钟，超了我会举手。",
                      "Bob：故事点到底怎么换算成小时？",
                      "Sam：先粗着来，一点大概三四个小时，跑几个迭代再校准。",
                      "Ben：那十三点就是一周的活了？",
                      "Frank：十三点就是别做，先拆。",
                      "Ada：这句我同意，记下来。"
                    ), by: :sam)
                  ]],
                  ["议题", [
                    item("迭代目标：推理服务与网关可跑通", 10, talk(
                      "Ada：第一个迭代我不想要太多东西。就一件事——从编辑器发一句话，能经过网关到推理服务，再拿回一段文字。",
                      "Frank：文字不一定是好文字。",
                      "Ada：能出字就行，写得好是以后的事。",
                      "Fiona：请问网关要不要先支持限流？还是只管转发？",
                      "Frank：只转发。限流等有真实流量再说。",
                      "Ada：那就这样。"
                    ), by: :ada, out: [dec("Sprint 1 目标：推理服务与网关可跑通；网关先只做转发，不做限流。")]),
                    item("流式输出：SSE 还是 WebSocket", 12, talk(
                      "Fiona：请问前端要接 WebSocket 吗？",
                      "Frank：不用。流式是服务端往前端单向推，SSE 就够了，浏览器自带，走普通 HTTP，网关也不用改。",
                      "Bob：断线了怎么办？",
                      "Frank：Last-Event-ID 续传。",
                      "Ben：WebSocket 不是更高级吗？",
                      "Frank：高级不是理由。",
                      "Ada：Frank，你再说一遍结论，我好记。",
                      "Frank：SSE。双向用不上。"
                    ), by: :frank, out: [dec("流式输出用 SSE，不用 WebSocket；断线用 Last-Event-ID 续传。")]),
                    item("容量与承诺", 10, talk(
                      "Sam：六个人，每人每天按五个小时有效时间算，折下来大概二十点上下。",
                      "Ben：我觉得能多一点。",
                      "Frank：第一个迭代都不准，别逞强。",
                      "Bob：那就二十点？",
                      "Sam：行，二十点。完不成不要紧，我们要的是第一个速度数据。"
                    ), by: :sam, out: [dec("Sprint 1 承诺 20 点。")]),
                    wp_item(202, 8, talk(
                      "Frank：基座模型先在内网那台 GPU 机器上跑起来，命令行能出一次完整推理就算。",
                      "Ben：显存够吗？",
                      "Frank：量化以后够，Mia 周五前给显存测算。……哦，Mia 还没来。",
                      "Ada：那就 Bob 先搭容器，量化的事等 Mia 到了再说。"
                    ), by: :frank),
                    wp_item(205, 8, talk(
                      "Bob：网关骨架，转发、健康检查、超时。周五前一定有个能转发的版本。",
                      "Sam：我记下了。",
                      "Frank：超时要有明确错误，别让前端猜。"
                    ), by: :bob),
                    wp_item(209, 6, talk(
                      "Fiona：编辑器里的最小对话面板，先不做流式。请问分支怎么命名？",
                      "Sam：feature/ 加工作包编号。评审与合并规范我写进维基。"
                    ), by: :fiona),
                    wp_item(214, 6, talk(
                      "Sam：CI 我自己来，每次提交自动跑 lint 和单测，主干保护打开。",
                      "Ada：PRD 的首版范围我周三前补完。"
                    ), by: :sam)
                  ]],
                  ["行动项", [
                    actions([:sam, "把“迭代流程”和“评审与合并规范”两页写进维基", -75],
                            [:bob, "推理服务的部署脚本先 push 上来", -75],
                            [:ben, "把向量库的候选方案列一份发到群里", -74],
                            [:ada, "PRD 里“首版范围”一节补完", -75])
                  ]]
                ]),
        meeting("Sprint 1 待办梳理", :ada, -68, "15:00", 60, TEAM, absent: [:frank], sections: [
                  ["回顾", [
                    item("上次行动项", 10, talk(
                      "Sam：维基两页写完了，PR 24 小时内给第一次评审，大家看一下。（已完成）",
                      "Ada：PRD 首版范围补了。（已完成）",
                      "Bob：部署脚本 push 了，但没写说明，Fiona 周一照着跑没跑通。（做了一半）",
                      "Ben：向量库候选……我还没发。这周网关的活把我挤掉了。（没做）",
                      "Sam：那顺延，别再被挤了。"
                    ))
                  ]],
                  ["议题", [
                    item("欢迎 Mia", 5, talk(
                      "Ada：这周 Mia 加入，做算法。她先熟悉代码，不排任务。",
                      "Mia：我先读文档。请大家有空带我跑一遍本地环境。",
                      "Ben：我带你。别用我那个脚本。",
                      "Bob：他说的是我的脚本。"
                    )),
                    item("Sprint 2 候选：文档上传与解析", 25, talk(
                      "Ada：下个迭代的目标我想定成“文档上传与解析”。用户把 PDF、DOCX 丢进来，系统能读出正文和标题层级。",
                      "Ben：PDF 我来，DOCX 我也能一起做。",
                      "Mia：我建议先分开估。DOCX 的合并单元格、嵌套表格很容易炸。",
                      "Ben：那些后面再说，先把常见的跑通。",
                      "Mia：好，但请把“常见”写下来，不然验收时每个人理解不一样。",
                      "Ada：验收标准我来写，周五评审前补完。"
                    ), by: :ada, out: [dec("Sprint 2 目标：文档上传与解析；验收标准由 Ada 在周五前写完。")]),
                    item("上传组件的交互", 10, talk(
                      "Fiona：请问上传失败了，要红字提示还是弹窗？大文件要不要显示进度？",
                      "Ada：红字提示放在文件名旁边，进度条要。",
                      "Fiona：能不能限制单文件大小？",
                      "Ada：先二十兆，数字别写死在前端。"
                    ), by: :fiona)
                  ]],
                  ["行动项", [
                    actions([:ada, "Sprint 2 候选故事的验收标准写完", -66],
                            [:fiona, "上传组件的原型做出来给大家看", -63],
                            [:mia, "PDF、DOCX 解析库的对比表", -63],
                            [nil, "整理一批测试用的样本文档（PDF 和 DOCX 各十几份）", -63])
                  ]]
                ]),
        meeting("Sprint 1 评审会", :sam, -66, "14:00", 60, TEAM, sections: [
                  ["评审", [
                    item("Sprint 1 完成情况", 10, talk(
                      "Sam：承诺二十点，完成十八点，结转两点：网关的健康检查和日志落盘。",
                      "Ada：这个数可以，第一个迭代能有数据比什么都重要。",
                      "Frank：日志落盘我下周一做完。"
                    ), by: :sam, out: [info("Sprint 1 完成 18 点（承诺 20），结转 2 点。速度基线：18。")]),
                    item("演示：从编辑器到推理服务出第一段字", 20, talk(
                      "Frank：这是网关，这是推理服务，请求从这里进去……好，出字了。",
                      "Ada：出来的是什么？",
                      "Frank：“这是一段测试文字。”",
                      "Ada：这是固定的吧。",
                      "Frank：是固定的，模型这周才接上，下周换成真的。",
                      "Bob：我作证，路径是真的。",
                      "Ada：行。目标写的是“跑通”，没写“好用”，算达成。"
                    ), by: :frank),
                    wp_item(209, 10, talk(
                      "Fiona：这是编辑器里的对话面板，输入一句话，回复整段回来，现在还没有流式。",
                      "Ada：回复慢的时候界面是什么样子？",
                      "Fiona：有个转圈。错误态和空态我在做，网络断了会提示。",
                      "Ada：好，这就是我要的。"
                    ), by: :fiona),
                    wp_item(213, 5, talk(
                      "Bob：压测的时候发现的，上游超时以后网关不释放连接，十几分钟耗尽。已经修了。",
                      "Frank：这种问题第一次压测就该出来，好事。"
                    ), by: :bob),
                    item("推理服务的冷启动", 10, talk(
                      "Frank：冷启动大概一分半。",
                      "Fiona：请问用户会等一分半吗？",
                      "Frank：不会，上线后常驻，冷启动只发生在重启。",
                      "Ada：这条写进风险，别忘了。"
                    ), by: :frank),
                    item("网关要不要限流", 10, talk(
                      "Bob：限流上次说先不做，我有个想法，按账号限？",
                      "Ada：商业化以前不需要，先放着。",
                      "Frank：同意。但要把为什么不做、有哪些坑记到维基里，免得以后没人记得。"
                    ), out: [dec("网关限流推迟，等有商业化需求再按套餐设计。")])
                  ]],
                  ["行动项", [
                    actions([:frank, "把网关限流为什么推迟、有哪些坑记到维基", -63],
                            [:frank, "日志落盘做完", -63])
                  ]]
                ]),
        meeting("Sprint 1 回顾会", :sam, -66, "15:30", 60, TEAM, sections: [
                  ["做得好", [
                    item("做得好", 10, talk(
                      "Fiona：站会真的只有十五分钟，Sam 举手那次我印象很深。",
                      "Ben：大家的 PR 评审很快。",
                      "Ada：Frank 评审时讲得很清楚，我能听懂。"
                    ))
                  ]],
                  ["待改进", [
                    item("待改进", 20, talk(
                      "Ben：故事写得太粗，我开工才发现要问 Ada，来回一天。",
                      "Ada：这个怪我，进迭代前我把验收标准补上。",
                      "Frank：演示环境是临时拼的，上台前我还在改配置。",
                      "Fiona：能不能有个常驻的演示环境？",
                      "Bob：我可以，但谁维护？",
                      "Frank：谁演示谁负责，行不行？",
                      "Sam：这条先留着，下次再看。",
                      "Ben：还有缺陷清单，现在是各记各的。",
                      "Sam：这个……（沉默）"
                    ))
                  ]],
                  ["行动项", [
                    actions([:ada, "进迭代前每个故事都带上验收标准", -63],
                            [:frank, "搭一个常驻的演示环境", -59],
                            [nil, "缺陷清单没人看，需要有人每周梳理一次"])
                  ]]
                ])
      ]
    end

    def sprint_two
      [
        meeting("Sprint 2 计划会", :sam, -63, "09:30", 90, TEAM, sections: [
                  ["回顾", [
                    item("上次行动项", 10, talk(
                      "Ada：验收标准写完了，三个故事都有。（已完成）",
                      "Fiona：上传组件原型有了，链接在群里。（已完成）",
                      "Mia：解析库对比表在维基上，PDF 用一个，DOCX 用另一个。（已完成）",
                      "Frank：演示环境还差域名。（做了一半）",
                      "Frank：限流那篇……还没写。今天写。（没做）",
                      "Sam：缺陷清单我接了，每周五下午我过一遍。",
                      "Ben：样本文档集没人收，这条还空着。",
                      "Mia：我来吧，反正我对比解析库也要用。"
                    ))
                  ]],
                  ["议题", [
                    item("迭代目标：文档上传与解析", 10, talk(
                      "Ada：Sprint 2 就一件事——用户把 PDF、DOCX 丢进来，能读出正文和标题层级。",
                      "Mia：表格呢？",
                      "Ada：简单表格算，复杂的不算。"
                    ), by: :ada, out: [dec("Sprint 2 目标：文档上传与解析。")]),
                    wp_item(221, 25, talk(
                      "Ben：PDF 解析我估五点，十六个小时。",
                      "Mia：我估二十四个小时，因为要处理多栏和页眉页脚。",
                      "Ben：多栏是后面的事。",
                      "Mia：多栏不是后面的事。用户一上传论文就是双栏。",
                      "Ada：论文是我们的核心场景，Mia 说得对。",
                      "Ben：好吧，那……十八？",
                      "Mia：点数五点我不反对，但请把页眉页脚写进验收标准，工时你自己心里有数。",
                      "Sam：点数定五点，页眉页脚进验收。"
                    ), by: :ben, out: [dec("PDF 解析按 5 点估，多栏与页眉页脚进验收标准。")]),
                    wp_item(226, 10, talk(
                      "Ben：DOCX 和 Markdown 我一起做，五点。",
                      "Mia：DOCX 的标题层级靠样式，有的文档根本没设样式。",
                      "Ben：没设样式的按字号推断。",
                      "Mia：好，请写进验收。"
                    ), by: :ben),
                    wp_item(230, 5, talk(
                      "Fiona：上传进度和失败重试的交互，三点。",
                      "Ada：失败了能一键重试，这个很重要。"
                    ), by: :fiona),
                    item("扫描件要不要支持", 10, talk(
                      "Fiona：请问用户上传的是扫描件怎么办？",
                      "Ada：这版先不管扫描件，只做有文本层的。",
                      "Mia：那界面上得告诉用户，不然他会以为我们坏了。",
                      "Ada：好，先记成风险，等有人反馈了再说。"
                    ), out: [dec("Sprint 2 不支持扫描件，只处理有文本层的文档；风险记入风险登记。")]),
                    item("容量与承诺", 10, talk(
                      "Sam：Mia 这是第一个完整迭代，Bob 下周四半天不在。扣掉之后算二十四点。",
                      "Frank：上次十八，这次二十四，涨了三分之一。",
                      "Sam：上次有人是第一次，这次熟了。",
                      "Ada：那就二十四，看速度。"
                    ), by: :sam, out: [dec("Sprint 2 承诺 24 点。")])
                  ]],
                  ["行动项", [
                    actions([:ben, "文档上传接口的数据契约写出来，给 Fiona", -61],
                            [:fiona, "上传组件接上接口，先用假数据联调", -58],
                            [:sam, "CI 二十分钟太慢，找出原因", -60],
                            [:mia, "样本文档集收到三十份，PDF 和 DOCX 各一半", -55])
                  ]]
                ]),
        meeting("Sprint 2 待办梳理", :ada, -54, "15:00", 60, TEAM, absent: [:bob], sections: [
                  ["回顾", [
                    item("上次行动项", 10, talk(
                      "Ben：数据契约写好了，Fiona 已经在用。（已完成）",
                      "Fiona：假数据联调通了，真接口等 Ben。（已完成）",
                      "Mia：样本集收到十八份，目标三十份。（做了一半）",
                      "Sam：CI 慢是因为每次都重新装依赖，缓存还没配。我来盯。（还在查）"
                    ))
                  ]],
                  ["议题", [
                    item("解析失败怎么提示用户", 15, talk(
                      "Fiona：请问解析失败是红字还是弹窗？用户该怎么重试？",
                      "Ada：红字，写清楚是哪一页出问题，给一个“重新上传”的按钮。",
                      "Mia：有些文件是部分成功，前十页能读，后面读不出来。",
                      "Ada：那就告诉他“已读取前十页”，让他自己选继续还是重传。"
                    ), by: :fiona),
                    item("Sprint 3 候选：向量库与切片基线", 25, talk(
                      "Ada：下个迭代是向量库和切片基线。我想先要一个能跑的东西，别追求最优。",
                      "Ben：向量库选型两天。",
                      "Mia：两天是你一个人选、一个人部署的话。",
                      "Ben：对啊。",
                      "Mia：还没算评测。",
                      "Ben：评测集还没有，那……三天？",
                      "Frank：写四天。",
                      "Ben：四天我会闲着。",
                      "Frank：闲着就帮 Bob 看网关。",
                      "Ada：先本地单机部署，云服务以后再说。"
                    ), out: [dec("向量库先本地单机部署，云服务以后再评估。")]),
                    item("v1.0 发布排期", 10, talk(
                      "Ada：v1.0 发布日定在 Sprint 3 第一周的周五，范围按当前主干冻结，之后只修缺陷。",
                      "Sam：那 Sprint 3 的第一周会很挤。",
                      "Ada：所以 Sprint 3 的承诺别太满。"
                    ), by: :ada)
                  ]],
                  ["行动项", [
                    actions([:ben, "Qdrant 与 pgvector 的初步对比（部署、召回、运维成本）", -47],
                            [:mia, "整理切片策略的两种方案：按标题、按长度", -49],
                            [:ada, "v1.0 发布公告的大纲", -48])
                  ]]
                ]),
        meeting("Sprint 2 评审会", :sam, -52, "14:00", 60, TEAM, sections: [
                  ["评审", [
                    item("Sprint 2 完成情况", 10, talk(
                      "Sam：承诺二十四点，完成二十二点，结转两点。",
                      "Ada：结转的是什么？",
                      "Sam：DOCX 合并单元格。"
                    ), by: :sam, out: [info("Sprint 2 完成 22 点（承诺 24），结转 2 点。速度：22。")]),
                    wp_item(221, 15, talk(
                      "Ben：上传一篇双栏论文……正文读出来了，页眉页脚也过滤掉了。",
                      "Mia：上一版把页码混进了正文，这版没有。",
                      "Ada：我拿一篇自己的试一下。……好，标题层级也对。",
                      "Ben：我说过周五前一定。",
                      "Frank：你说的是上周五。"
                    ), by: :ben),
                    wp_item(226, 10, talk(
                      "Ben：DOCX 的标题层级能读出来。",
                      "Ada：合并单元格那个呢？",
                      "Ben：下个迭代。",
                      "Mia：它会在某一天咬我们。",
                      "Sam：记成已知问题，别丢。"
                    ), by: :ben, out: [dec("DOCX 合并单元格解析丢失列为已知问题，后续迭代处理。")]),
                    wp_item(230, 10, talk(
                      "Fiona：这是上传组件，失败时红字提示在文件名旁边，可以一键重试。",
                      "Ada：好看。大文件进度条呢？",
                      "Fiona：在这儿。我把二十兆做成配置了。",
                      "Bob：超过二十兆静默失败那个我修了，现在会提示。"
                    ), by: :fiona),
                    wp_item(235, 5, talk(
                      "Bob：#235 超过二十兆的文件上传之前是静默失败，用户看不到任何提示，现在会明确告诉他超限。",
                      "Ada：这条是用户最容易撞上的，谢谢。"
                    ), by: :bob)
                  ]],
                  ["行动项", [
                    actions([:ben, "把 DOCX 合并单元格记成一个缺陷", -49])
                  ]]
                ]),
        meeting("Sprint 2 回顾会", :sam, -52, "15:30", 60, TEAM, absent: [:frank], sections: [
                  ["做得好", [
                    item("做得好", 10, talk(
                      "Mia：样本文档集让每次改动都有对照，回归一目了然。",
                      "Ada：验收标准写完再开工，这次没有返工。",
                      "Fiona：上传组件和接口并行，没有互相等。"
                    ))
                  ]],
                  ["待改进", [
                    item("待改进", 20, talk(
                      "Mia：PDF 解析估了十六个小时，实际做了二十六个；我当时说二十四，Ben 说十六。差在对“多栏”的理解上。",
                      "Ben：我承认我估乐观了。DOCX 估十四，也做了二十三。",
                      "Mia：两个样本，我记下来了。",
                      "Bob：站会最近拖到二十分钟。",
                      "Sam：看着我？",
                      "Bob：我讲的都是有用的。",
                      "Sam：有用也要计时。",
                      "Fiona：CI 还是二十分钟，每次等得想睡觉。",
                      "Sam：这个我盯过，没盯出来。"
                    ))
                  ]],
                  ["行动项", [
                    actions([:sam, "站会用计时器，十五分钟到就停", -49],
                            [:ben, "估点前先翻一遍历史上同类任务的实际工时", -49],
                            [nil, "CI 提速：缓存依赖、拆掉不必要的步骤"])
                  ]]
                ])
      ]
    end

    def sprint_three
      [
        meeting("Sprint 3 计划会", :sam, -49, "09:30", 90, TEAM, sections: [
                  ["回顾", [
                    item("上次行动项", 10, talk(
                      "Sam：站会计时用了，上周四天都是十四分钟以内。（已完成）",
                      "Mia：切片两种方案的文档写了。（已完成）",
                      "Ada：公告大纲有了。（已完成）",
                      "Ben：DOCX 合并单元格的缺陷……还没建。（没做）",
                      "Ben：估点前翻历史，我翻了，PDF 那次是个例外。（算做了）",
                      "Sam：CI 还是慢，没人动。"
                    ))
                  ]],
                  ["议题", [
                    item("迭代目标：向量库与切片基线", 15, talk(
                      "Ada：目标是一个能跑的向量库，加一条固定长度的切片基线。检索结果能返回就行。",
                      "Mia：召回率要不要有数？",
                      "Ada：要一个基线数字，不要求好看，后面才知道好了多少。"
                    ), by: :ada, out: [dec("Sprint 3 目标：向量库与切片基线。")]),
                    wp_item(242, 8, talk(
                      "Mia：嵌入模型我对比三个，用我整理的样本集跑，周三出表。",
                      "Ada：中文长文的效果最重要。",
                      "Mia：对，我专门加了论文类样本。"
                    ), by: :mia),
                    wp_item(245, 8, talk(
                      "Ben：本地向量索引原型，先用 Faiss 把检索接口跑通，五点。",
                      "Frank：接口别和具体库绑死，后面要换。",
                      "Ben：我留了适配层。",
                      "Mia：并发读写要想一下。",
                      "Ben：先跑通，并发后面再说。"
                    ), by: :ben),
                    item("向量库怎么选：Qdrant 还是 pgvector", 15, talk(
                      "Ben：Qdrant 检索更快，要单独部署，要自己备份。",
                      "Bob：pgvector 和业务库同源，运维省事，但量大了会吃力。",
                      "Mia：小样本上两者召回差不多。",
                      "Ada：我们现在量不大，团队里熟悉运维的就两个人。",
                      "Frank：我周三出结论。",
                      "Ben：我可以两边都搭个原型对比。",
                      "Frank：别两边都搭，我来定。你先用 Faiss 把接口跑通。"
                    ), by: :frank, out: [info("向量库在 Qdrant 与 pgvector 之间二选一，Frank 本周三给出结论；Ben 先用 Faiss 把检索接口跑通。")]),
                    item("v1.0 发布周的容量", 15, talk(
                      "Frank：周五发布，我要值班，这周写代码的时间只有一半。",
                      "Sam：我把值班扣掉，Frank 按半个人算。",
                      "Ada：发布周不要排太满，二十六点够了。",
                      "Frank：二十六也满。"
                    ), by: :sam, out: [dec("Sprint 3 承诺 26 点；发布周 Frank 按半个人算。")])
                  ]],
                  ["行动项", [
                    actions([:frank, "向量库选型结论：Qdrant 还是 pgvector", -47],
                            [:mia, "嵌入模型对比表", -47],
                            [:sam, "v1.0 发布前检查：迁移、回滚、监控逐项核对", -46],
                            [:fiona, "v1.0 发布公告页文案", -46],
                            [:ben, "向量库原型部署与检索联调", -42])
                  ]]
                ]),
        meeting("Sprint 3 待办梳理", :ada, -40, "15:00", 60, TEAM, absent: [:fiona], sections: [
                  ["回顾", [
                    item("v1.0 发布后第一周", 15, talk(
                      "Sam：发布顺利，线上三个小问题，都已经修了。",
                      "Frank：值班夜里被叫醒一次，是告警阈值设太低了。",
                      "Ada：谢谢 Frank。阈值谁调？",
                      "Frank：……",
                      "Ben：我不会调。",
                      "Sam：这条先挂着。"
                    )),
                    item("上次行动项", 5, talk(
                      "Frank：pgvector。小团队运维简单优先，量到千万级再评估。（已完成）",
                      "Sam：发布检查和公告文案都有了。（已完成）",
                      "Ben：Faiss 原型接口跑通了，并发读写还有个冲突。（做了一半）"
                    ))
                  ]],
                  ["议题", [
                    item("切片策略：按标题还是按长度", 25, talk(
                      "Mia：我做了对比，有标题层级的文档按标题切，召回高八个点；没有标题的按长度。",
                      "Ben：两种都做，工作量翻倍。",
                      "Mia：不翻倍，共用一个入口，接口我写好了。",
                      "Frank：我想要评测集。不然“高八个点”谁都能说。",
                      "Mia：我在整理，但需要真实问题和标准答案，现在是我自己编的。",
                      "Ada：真实问题我去找客户要。"
                    ), by: :mia),
                    wp_item(256, 5, talk(
                      "Bob：账号体系和 API Key 管理这周要收尾，后面计费要用。",
                      "Ada：Key 能不能按项目发？",
                      "Bob：先按账号，项目级放后面。"
                    ), by: :bob),
                    wp_item(43, 10, talk(
                      "Frank：单轮生成主链路，我先把推理服务那段打通。",
                      "Bob：网关我拆小一点，之前一直是一个包。",
                      "Frank：同意，断流重连单独一个缺陷。"
                    ), by: :frank),
                    wp_item(59, 10, talk(
                      "Mia：切片入库我下个迭代做，需要 Ben 的向量库先稳定。",
                      "Ben：我这周五前把稳定版给你。",
                      "Mia：好，我把“稳定”写成：连续跑一百次入库不丢数据。"
                    ), by: :mia),
                    wp_item(61, 5, talk(
                      "Ben：向量库正式部署放下个迭代，这次只有原型。",
                      "Ada：可以，别让原型直接上线。",
                      "Ben：我保证。",
                      "Frank：他每次都保证。"
                    ), by: :ben)
                  ]],
                  ["行动项", [
                    actions([:mia, "评测集方案草稿，先收三十条真实问题", -38],
                            [:ada, "向客户要二十条真实问题", -38],
                            [:bob, "把网关拆成可以单独验收的小包", -38],
                            [nil, "线上告警阈值调整"])
                  ]]
                ]),
        meeting("Sprint 3 评审会", :sam, -38, "14:00", 60, TEAM, sections: [
                  ["评审", [
                    item("Sprint 3 完成情况", 10, talk(
                      "Sam：承诺二十六点，完成二十五点，结转一点：向量库的监控面板。",
                      "Ada：发布周还能做到二十五，辛苦了。"
                    ), by: :sam, out: [info("Sprint 3 完成 25 点（承诺 26），结转 1 点。速度：25。")]),
                    wp_item(245, 20, talk(
                      "Ben：我搜“续航”，它给我“电池”。",
                      "Ada：为什么？",
                      "Ben：语义相近。",
                      "Ada：如果我就想搜“续航”这两个字呢？",
                      "Mia：那是全文检索的事，这个以后单独说。",
                      "Frank：基线召回率是百分之六十一。",
                      "Ada：好，这是我们的起点。"
                    ), by: :ben),
                    wp_item(251, 10, talk(
                      "Mia：这是定长切片加重叠窗口，作为基线。按标题切的比它召回高八个点，我这里有表。",
                      "Ben：表我看了，没有问题。",
                      "Frank：评测集有了才能真正确认。"
                    ), by: :mia),
                    wp_item(242, 5, talk(
                      "Mia：嵌入模型选了第二个，中文长文表现最稳。",
                      "Ada：理由写在工作包里了吗？",
                      "Mia：写了。"
                    ), by: :mia),
                    wp_item(259, 5, talk(
                      "Ben：检索接口并发下索引读写冲突，我修了，加了读写锁。",
                      "Mia：之前说过会冲突。",
                      "Ben：对，你说得对。"
                    ), by: :ben),
                    item("下个迭代预告", 10, talk(
                      "Ada：Sprint 4 两条线：单轮生成主链路，和文档切片入库。",
                      "Bob：向量库正式部署也在里面。",
                      "Ada：对，原型不上线。"
                    ), by: :ada)
                  ]],
                  ["行动项", [
                    actions([:ben, "向量库监控面板做完", -35],
                            [:ben, "Faiss 原型换成 pgvector 的计划写进工作包", -35])
                  ]]
                ]),
        meeting("Sprint 3 回顾会", :sam, -38, "15:30", 60, TEAM, sections: [
                  ["做得好", [
                    item("做得好", 10, talk(
                      "Sam：v1.0 发布没出大事。",
                      "Bob：值班交接做得清楚。",
                      "Mia：向量库选型当天出了结论，没有拖。"
                    ))
                  ]],
                  ["待改进", [
                    item("待改进", 20, talk(
                      "Frank：发布周我值班又写代码，容量表要把值班扣掉。",
                      "Sam：这次扣了一半，刚好。下次写进表格。",
                      "Ben：向量库踩了几个坑，没人知道。",
                      "Frank：我来写。",
                      "Bob：告警阈值我这周顺手调了。"
                    ))
                  ]],
                  ["行动项", [
                    actions([:sam, "容量表里加上值班扣减", -35],
                            [:frank, "向量库踩坑笔记写到维基", -35],
                            [:bob, "线上告警阈值调整并通知大家", -35])
                  ]]
                ])
      ]
    end

    def sprint_four
      [
        meeting("Sprint 4 计划会", :sam, -35, "09:30", 90, TEAM, sections: [
                  ["回顾", [
                    item("上次行动项", 10, talk(
                      "Sam：容量表加了值班扣减。（已完成）",
                      "Bob：告警阈值调了，夜里没再响。（已完成）",
                      "Mia：评测集草稿有了，二十一条。（做了一半）",
                      "Ada：客户给了十二条真实问题，还差八条。（做了一半）",
                      "Frank：向量库踩坑笔记……（没做）"
                    ))
                  ]],
                  ["议题", [
                    wp_item(43, 15, talk(
                      "Frank：单轮生成主链路，从编辑器到推理服务再写回文档。",
                      "Ada：我要的是用户点一下按钮，文字出现在文档里。",
                      "Frank：我这周先把后端打通，前端 Fiona 接。"
                    ), by: :frank),
                    wp_item(45, 10, talk(
                      "Bob：推理服务和网关，周五前一定。",
                      "Sam：你上次也这么说。",
                      "Bob：这次我拆小了，真的不一样。",
                      "Frank：我记着。"
                    ), by: :bob),
                    wp_item(58, 10, talk(
                      "Ben：正文和标题层级上个迭代都有了，这次把表格提取做完整，三种格式收口。",
                      "Mia：合并单元格呢？",
                      "Ben：先不管。",
                      "Mia：我先把话放这儿。"
                    ), by: :ben),
                    wp_item(59, 10, talk(
                      "Mia：段落级切片入库，我估五点。",
                      "Ben：我觉得三点。",
                      "Mia：你每次都觉得少。",
                      "Ada：定五点。"
                    ), by: :mia),
                    wp_item(61, 10, talk(
                      "Ben：向量库正式部署，pgvector 已经定了，这次是部署和备份。",
                      "Bob：备份我来配。",
                      "Ben：谢谢，不然我又要估乐观了。"
                    ), by: :ben),
                    item("容量与承诺", 10, talk(
                      "Sam：上次二十五，这次承诺二十八。",
                      "Fiona：请问这个包括 on-call 吗？",
                      "Sam：这周没有发布，不需要。"
                    ), by: :sam, out: [dec("Sprint 4 承诺 28 点；目标：单轮生成主链路打通、文档切片入库。")])
                  ]],
                  ["行动项", [
                    actions([:bob, "推理服务与网关部署完成", -31],
                            [:fiona, "前端流式渲染原型", -32],
                            [:ben, "向量库部署与备份方案", -33],
                            [:mia, "切片入库联调", -28])
                  ]]
                ]),
        meeting("Sprint 4 待办梳理", :ada, -26, "15:00", 60, TEAM, sections: [
                  ["回顾", [
                    item("上次行动项", 10, talk(
                      "Bob：#45 周一才做完，说好的周五。（做了，晚了）",
                      "Fiona：流式渲染原型有了。（已完成）",
                      "Ben：向量库部署完了，备份 Bob 配好了。（已完成）"
                    ))
                  ]],
                  ["议题", [
                    wp_item(64, 15, talk(
                      "Frank：引用溯源，我想让每个论断都能点回原文。",
                      "Mia：粒度怎么定？句子级更准，但要重切。",
                      "Ada：段落级。用户要的是能回到原文，不是精确到句子。",
                      "Frank：那就这样。"
                    ), by: :frank),
                    wp_item(65, 10, talk(
                      "Mia：幻觉拦截，检索不到依据时直接告诉用户没找到。",
                      "Ada：阈值怎么定？",
                      "Mia：我先用评测集跑，定下来再说。"
                    ), by: :mia),
                    wp_item(49, 10, talk(
                      "Ada：首字延迟现在多少？",
                      "Mia：P95 一点五秒。",
                      "Ada：目标是八百毫秒以内。",
                      "Frank：可以，但要用缓存，Mia 来。"
                    ), by: :mia),
                    wp_item(102, 5, talk(
                      "Bob：金额取整的口径要和财务对，我先问。",
                      "Ada：好，下周三前拿到答案。"
                    ), by: :bob)
                  ]],
                  ["行动项", [
                    actions([:frank, "引用溯源的技术方案草稿", -24],
                            [:mia, "首字延迟的基线测量数据", -24],
                            [:bob, "和财务确认金额取整口径", -21])
                  ]]
                ]),
        meeting("Sprint 4 评审会", :sam, -24, "14:00", 60, TEAM, sections: [
                  ["评审", [
                    item("Sprint 4 完成情况", 10, talk(
                      "Sam：承诺二十八点，完成二十七点，结转一点：断流后的自动重连压测。",
                      "Ada：这个数不错，比上次又涨了。"
                    ), by: :sam, out: [info("Sprint 4 完成 27 点（承诺 28），结转 1 点。速度：27。")]),
                    wp_item(43, 15, talk(
                      "Frank：这是单轮生成。用户点一下，文字就写进文档。",
                      "Ada：我能自己试吗？……好。首字好像有点慢。",
                      "Frank：首字延迟是下个迭代的事。"
                    ), by: :frank),
                    wp_item(44, 10, talk(
                      "Fiona：这是流式渲染，字一个一个出来，光标不会跳。",
                      "Ada：断线了呢？",
                      "Frank：断线会自动重连。压测还没做完，所以结转了一点。"
                    ), by: :fiona),
                    wp_item(58, 10, talk(
                      "Ben：三种格式的表格提取。这里有一个表格，行列顺序是对的。",
                      "Mia：合并单元格的还是不对。",
                      "Ben：我们不是说好先不管吗？",
                      "Mia：我说的是先不管，不是不存在。"
                    ), by: :ben)
                  ]],
                  ["行动项", [
                    actions([:frank, "断线自动重连的压测做完", -21])
                  ]]
                ]),
        meeting("Sprint 4 回顾会", :sam, -24, "15:30", 60, TEAM, sections: [
                  ["做得好", [
                    item("做得好", 10, talk(
                      "Fiona：流式出字很适合演示，Ada 看了很开心。",
                      "Ben：向量库部署比我估的顺。",
                      "Mia：评测集开始有用了，改切片能立刻看到数。"
                    ))
                  ]],
                  ["待改进", [
                    item("待改进", 25, talk(
                      "Fiona：我这周有个 PR 等了两天，约定是二十四小时。",
                      "Sam：谁的？",
                      "Fiona：不说是谁。",
                      "Bob：我的。",
                      "Frank：演示环境又被人覆盖了，上台前我在重新部署。",
                      "Bob：我的。",
                      "Ben：向量库客户端又出新版本了，要不要升级？",
                      "Frank：升级要回归所有检索用例，这个迭代没空。",
                      "Sam：先记着，别忘了。"
                    ))
                  ]],
                  ["行动项", [
                    actions([:sam, "评审队列里挂二十四小时提醒", -21],
                            [:frank, "演示环境加锁，演示前不部署", -21],
                            [nil, "评估升级向量库客户端"])
                  ]]
                ])
      ]
    end

    def sprint_five
      [
        meeting("Sprint 5 计划会", :sam, -21, "09:30", 90, TEAM, sections: [
                  ["回顾", [
                    item("上次行动项", 10, talk(
                      "Sam：评审队列提醒挂上了，PR 等待时间下来了。（已完成）",
                      "Frank：演示环境加锁了。（已完成）",
                      "Ben：向量库客户端的评估，没人认领，我当没看见。（没做）",
                      "Frank：压测做完了，断线重连通过。（已完成）"
                    ))
                  ]],
                  ["议题", [
                    item("迭代目标：引用溯源、幻觉拦截，计费主链路起步", 10, talk(
                      "Ada：Sprint 5 是个大迭代。RAG 这条线要做到能引用、不胡编；商业化那边，计费主链路要起步。",
                      "Frank：两条线并行？",
                      "Ada：并行，人手够。"
                    ), by: :ada, out: [dec("Sprint 5 目标：引用溯源与幻觉拦截完成，计费主链路起步。")]),
                    wp_item(64, 10, talk(
                      "Frank：论断点回原文，段落级。",
                      "Fiona：请问高亮的交互谁定？",
                      "Ada：Fiona 先出方案。"
                    ), by: :frank),
                    wp_item(65, 10, talk(
                      "Mia：阈值我用评测集跑出来了，低于零点六就不生成。",
                      "Ada：用户看到的是什么？",
                      "Mia：“没有找到依据”。"
                    ), by: :mia),
                    wp_item(62, 10, talk(
                      "Ben：有用户反馈扫描版 PDF 解析出来是空的，界面也没提示。",
                      "Ada：这算缺陷。先让用户知道发生了什么。",
                      "Mia：OCR 另说。"
                    ), by: :ben),
                    wp_item(102, 10, talk(
                      "Bob：账单金额取整，财务还没回。",
                      "Frank：流水能不能改，我明天给结论。",
                      "Ada：先别写代码，等口径。"
                    ), by: :bob),
                    item("容量与承诺", 10, talk(
                      "Sam：上次二十七，这次承诺三十一。",
                      "Frank：涨得有点多。",
                      "Sam：Mia 的 KV 缓存算进去了，这块她估得很细。",
                      "Ada：那就三十一，周中看。"
                    ), by: :sam, out: [dec("Sprint 5 承诺 31 点。")])
                  ]],
                  ["行动项", [
                    actions([:fiona, "溯源高亮交互方案", -19],
                            [:ben, "扫描件的界面提示文案", -19],
                            [:bob, "和财务确认金额取整口径", -17])
                  ]]
                ]),
        meeting("Sprint 5 待办梳理", :ada, -12, "15:00", 60, TEAM, sections: [
                  ["回顾", [
                    item("上次行动项", 10, talk(
                      "Fiona：高亮方案出来了，Ada 看过。（已完成）",
                      "Ben：扫描件提示文案写了。（已完成）",
                      "Bob：财务回了，逐条折算后四舍五入。（已完成）"
                    ))
                  ]],
                  ["议题", [
                    item("容量风声：借调与请假", 15, talk(
                      "Sam：先说一个还没定的事——数据平台组想借 Frank 和 Mia 一阵子，Ada 周五前给准话。",
                      "Frank：借多久？",
                      "Sam：说是到年底前。",
                      "Mia：我手上的评测集呢？",
                      "Ada：评测集交接给新来的同事。",
                      "Fiona：请问新同事是谁？",
                      "Sam：Quinn，下周一到。另外 Ben 下周一到周五休假。"
                    ), by: :sam),
                    wp_item(73, 10, talk(
                      "Bob：用量统计，我估二十四小时。",
                      "Frank：昨天压测超扣的事，我定了预扣加结算，网关只预扣。",
                      "Bob：#100 起步就是 P0。",
                      "Ada：对账口径呢？",
                      "Bob：等财务。"
                    ), by: :bob),
                    wp_item(69, 10, talk(
                      "Ben：知识库权限，我估三十小时。",
                      "Frank：三十小时太大了。",
                      "Ben：我觉得没问题，周五前……",
                      "Sam：你先别说周五。",
                      "Ada：先放进下个迭代，范围到时再收。"
                    ), by: :ben),
                    wp_item(81, 10, talk(
                      "Fiona：多人同时编辑，我先把光标同步的部分做起来。",
                      "Frank：四十小时，拆不拆？",
                      "Fiona：光标、合并、离线三块缠在一起，拆开会多出接口工作。",
                      "Ada：先做光标，不拆，下个迭代再看。"
                    ), by: :fiona),
                    wp_item(75, 5, talk(
                      "Bob：计费事件流水，口径还在等财务。",
                      "Frank：流水只追加，改动用冲正，对账靠重算。",
                      "Bob：我同意。"
                    ), by: :bob)
                  ]],
                  ["行动项", [
                    actions([:sam, "确认借调名单和时间，周五前告诉所有人", -10],
                            [:ben, "休假前把 #69 的设计写下来放进工作包", -10],
                            [:frank, "借调前给 #68 的修复写交接说明", -10],
                            [:mia, "评测集笔记放进目录并写清楚", -10])
                  ]]
                ]),
        meeting("Sprint 6 站会（Quinn 第一周）", :sam, 1, "09:45", 15, AFTER_LOAN, sections: [
                  ["站会", [
                    item("每个人一句话", 8, talk(
                      "Sam：先欢迎 Quinn，昨天入项，今天是他第一次站会。",
                      "Quinn：大家好，昨天拿到五个包，我今天先读背景。",
                      "Fiona：光标同步的延迟修了一半，今天继续。没有阻塞。",
                      "Bob：#73 今天要提测，还差一个对账用例，下午应该能好。",
                      "Ben：休完假回来，#69 的接口今天开始接。",
                      "Sam：#116 发布检查清单我今天补三项。",
                      "Ada：我今天都在会上，有事发消息。"
                    ), by: :sam),
                    item("Quinn 的问题", 7, talk(
                      "Quinn：我确认一下，站会上说的“提测”，就是把状态改成“测试中”，对吗？",
                      "Sam：对，开发完成当天就提测。",
                      "Quinn：那“开发完成”和“测试中”差在哪？",
                      "Fiona：开发完成是自己觉得好了，测试中是真有人在测。",
                      "Bob：有时候没人测。",
                      "Sam：所以才要写进约定。Quinn，决定记录和术语表在维基上，先读这两页。",
                      "Quinn：好，我今天读完。昨天交接的五个，哪个最急？",
                      "Sam：#79 是紧急缺陷，先看它，其余不用慌。"
                    ), by: :quinn)
                  ]],
                  ["行动项", [
                    actions([:fiona, "带 Quinn 过一遍仓库和本地环境", 1],
                            [:quinn, "读完维基里的“决定记录”和“术语表”", 2],
                            [:sam, "每天站会后留五分钟给 Quinn 提问", 2])
                  ]]
                ]),
        meeting("Sprint 6 回顾会", :sam, 4, "15:30", 60, AFTER_LOAN, sections: [
                  ["回顾", [
                    item("上次行动项", 10, talk(
                      "Sam：评审队列的提醒还在，PR 平均等待十一个小时。（已完成）",
                      "Ben：估算时标出同类任务的历史倍数，休假前没来得及做。（没做）"
                    ))
                  ]],
                  ["做得好", [
                    item("做得好", 10, talk(
                      "Fiona：Quinn 一周接了五个包，节奏没乱。",
                      "Quinn：谢谢。其实 #79 是 Bob 写的说明太清楚了。",
                      "Bob：我就写了三行。",
                      "Sam：提测提前了，#79 这次是迭代中段就被测出来的，不是评审前一天。",
                      "Ada：这条约定要保持。"
                    ))
                  ]],
                  ["待改进", [
                    wp_item(121, 15, talk(
                      "Sam：#121 向量库客户端升级，这是第三次回顾提起了。",
                      "Ben：每次都是“下个迭代”。",
                      "Bob：升级要回归所有检索用例，哪个迭代都挤不出来。",
                      "Ada：不做的话技术债越滚越大，但我也不能拿 v1.1 换它。",
                      "Bob：行，我认。但我周三起不在，下周二以前我只能起个头，把回归用例清单列出来。",
                      "Sam：起个头也算。"
                    ), by: :bob),
                    item("估算偏差", 15, talk(
                      "Sam：Mia 之前统计过十二个样本，续写和 RAG 类的任务，实际工时是估算的一点六倍。",
                      "Ben：我认。",
                      "Ada：S7 里又有 #56 和 #92，都是你的。",
                      "Ben：我估的时候是真心觉得十六小时。",
                      "Sam：乘一点六是二十五六个小时。",
                      "Ben：……你别乘。",
                      "Fiona：这条是不是应该有个人记一下？",
                      "Ben：我自己记。我下周一计划会前把 #56 #92 重新估一遍。"
                    ), by: :ben),
                    item("评审会演示环境又被冲掉", 10, talk(
                      "Fiona：今天演示 #74 的时候，Bob 刚好部署了一版，页面空白了半分钟。",
                      "Bob：我不知道你们在演示。",
                      "Sam：评审会前一天应该有个独立的演示环境，别和开发共用。",
                      "Ada：谁来做？",
                      "Sam：我这周 v1.1 的事已经满了。",
                      "Ada：我也不行。",
                      "Fiona：我不会部署。",
                      "Bob：我周三就走了。",
                      "Quinn：……我刚来，不太了解环境。"
                    ))
                  ]],
                  ["改进承诺", [
                    actions([:bob, "#121 升级向量库客户端：先把需要回归的用例清单列出来", 8],
                            [:ben, "#56 #92 按同类乘一点六重新估算", 7],
                            [nil, "评审会用独立的演示环境，不和开发环境共用"])
                  ]]
                ])
      ]
    end

    def amendments
      [
        {
          title: "Sprint 5 评审会", host: :sam,
          items: {
            1 => { add: talk("Sam：承诺三十一点，完成三十一点，速度新高。",
                             "Ada：不要把这个数当成目标，下次 Bob 说“周五前一定”我也会数一数。",
                             "Bob：我没说过这次。",
                             "Frank：你说的是上上次。") },
            2 => { by: :frank, add: talk("Frank：每个论断可以点开，跳回原文那一段。",
                                          "Ada：我点一个……对，高亮了。",
                                          "Fiona：高亮有时会偏一两行，我记着了。",
                                          "Ben：同名章节会不会跳错？",
                                          "Frank：这个……跨文档同名章节，还没覆盖。") },
            3 => { by: :mia, add: talk("Mia：检索不到依据时，不生成，直接说“没有找到依据”。",
                                       "Ada：用户会觉得我们不如别的产品聪明吗？",
                                       "Mia：他们会觉得我们诚实。",
                                       "Ada：我喜欢这个说法。") }
          },
          append: [
            wp_item(62, 10, talk("Ben：扫描版 PDF 现在会提示“这是扫描件，暂不支持文字识别”。",
                                  "Mia：OCR 要选引擎、评估成本，v1.1 来不及。",
                                  "Ada：决定：OCR 放 v2.0，先把提示写明白。"), by: :ben,
                                   out: [dec("扫描件先在界面上提示，OCR 放到 v2.0。")]),
            item("Sprint 6 预告", 10, talk("Ada：下个迭代是商业化的收尾，v1.1 定在 Sprint 7 第一周的周五。",
                                           "Sam：那 Sprint 6 的节奏不能再松。"), by: :ada)
          ],
          sections: [["行动项", [actions([:ben, "跨文档同名章节的溯源跳转问题记成缺陷", -7],
                                         [:bob, "用量统计的对账口径，再催财务一次", -7])]]]
        },
        {
          title: "Sprint 5 回顾会", host: :sam,
          items: {
            1 => { add: talk("Fiona：引用溯源提前一天完成，评测集让回归更有底气。",
                             "Mia：评测集每次改动都能立刻出数。") },
            2 => { add: talk("Mia：我把过去的十二个样本拉了一下，Ben 的续写和 RAG 类任务，实际工时大约是估算的一点六倍。",
                             "Ben：我知道我知道，我乐观。",
                             "Sam：这不是批评，是数据。",
                             "Ben：那估点前我翻一翻历史。",
                             "Bob：他每次都说翻。") },
            3 => { add: talk("Ada：决定了：开发完成当天就提测。状态用“测试中”，不要直接关闭。") }
          },
          append: [
            wp_item(121, 10, talk("Bob：#121 我搁置了，升级要回归所有检索用例，这周没人有空。",
                                   "Frank：上次回顾也提过。",
                                   "Sam：这是第二次了。",
                                   "Mia：每次都是下次。"), by: :bob)
          ],
          sections: [["行动项", [actions([:ben, "估算时标出同类任务的历史倍数", -7],
                                         [:sam, "把“测试提前介入”写进迭代流程页", -7],
                                         [nil, "评测集的持续维护"])]]]
        },
        {
          title: "Sprint 6 计划会", host: :sam, attended: %i[sam ada fiona bob],
          items: {
            1 => { by: :ada, add: talk("Ada：Sprint 6 把商业化主链路收尾，v1.1 是 Sprint 7 第一周的周五，这是硬日期。",
                                       "Sam：这次承诺三十八点，前两次是二十七和三十一。",
                                       "Fiona：三十八是不是高了？",
                                       "Ada：有 Quinn 来。",
                                       "Sam：他下周一才到，头几天产不出东西。",
                                       "Ada：那就先放三十八，周中看。"),
                   out: [dec("Sprint 6 承诺 38 点。")] },
            2 => { by: :sam, add: talk("Ben 今天起休假一周，周五回；Frank、Mia 借调，已经不在。",
                                       "Fiona：Ben 的 #69 谁盯？",
                                       "Sam：他走之前在工作包里留了设计，Ada 看过。",
                                       "Bob：我下周也不太满。",
                                       "Ada：你满不满我心里有数。") },
            3 => { by: :bob, add: talk("Bob：用量统计我周四前一定做完。",
                                       "Sam：周四前，哪个周四？",
                                       "Bob：……这周四。",
                                       "Ada：对账口径别等财务了，先按我给你的口径做，财务回了再改。",
                                       "Bob：好。") },
            4 => { by: :ada, add: talk("Ada：权限的范围我觉得太大了。项目级、角色级、临时授权，都被提过。",
                                       "Fiona：前端要跟着改吗？",
                                       "Bob：我觉得两层就够：知识库级和文档级。",
                                       "Ada：周三同步会上把范围定下来。") }
          },
          append: [
            wp_item(81, 10, talk("Fiona：多人同时编辑，我估四十小时。",
                                  "Sam：这是十三点。",
                                  "Fiona：光标同步、内容合并、离线冲突互相依赖，拆开会多出接口工作。",
                                  "Ada：我的意见是先整体做，不拆。做不完的话周中再看。"), by: :fiona,
                                  out: [dec("多人同时编辑 #81 整体做完，不拆分。")])
          ],
          sections: [["行动项", [actions([:bob, "#73 用量统计先按 Ada 给的口径做完", -4],
                                         [:fiona, "#81 的光标同步先做出来，周中看进度", -3],
                                         [:sam, "把 Quinn 要接手的五个包列出来", -4])]]]
        },
        {
          title: "Sprint 6 周中同步会", host: :sam, attended: %i[sam ada fiona bob],
          items: {
            1 => { add: talk("Bob：对账口径还在等财务，我先按 Ada 说的做。",
                             "Sam：财务周五前会回吗？",
                             "Bob：他们说会。",
                             "Fiona：#81 光标同步延迟修了一半。") },
            2 => { by: :bob, add: talk("Bob：#73 周四交不了，我得改期，改到下周二。",
                                       "Ada：又改？",
                                       "Bob：口径一直没定，我做完也要重做。",
                                       "Sam：原定 Sprint 5 末，第一次改到这周四，这是第二次。",
                                       "Ada：好，下周二。") },
            3 => { by: :ada, add: talk("Ada：#69 范围收窄，只做两层：知识库级和文档级。",
                                       "Fiona：前端能少做一块，我同意。",
                                       "Ada：截止日顺延到本迭代末。那就这样。") }
          },
          append: [
            wp_item(55, 10, talk("Bob：模型路由，先按延迟还是先按成本？",
                                  "Ada：成本影响账单，延迟差在二百毫秒以内用户感觉不到。",
                                  "Bob：那就先成本，再延迟。",
                                  "Ada：对，降级时的提示文案是 #90。"), by: :bob,
                                  out: [dec("模型路由先按成本、再按延迟排序。")])
          ],
          sections: [["行动项", [actions([:ada, "把 #69 的范围收窄写进工作包说明", -4],
                                         [:bob, "#73 下周二提测", 1],
                                         [:sam, "找财务要对账口径的明确回复", -4])]]]
        },
        {
          title: "Sprint 6 中期计划会", host: :sam, attended: AFTER_LOAN,
          items: {
            1 => { by: :bob, add: talk("Bob：用量统计，第二次改期了。财务昨天终于回了口径，我做完要对一遍。",
                                       "Ada：v1.1 是 Sprint 7 第一周的周五，这是硬日期。",
                                       "Sam：我算了一下，#73 周二提测的话，#76 配额告警 UI 下周一才能开工，周四收。",
                                       "Fiona：#76 要等 #73 的接口。",
                                       "Ada：那就这样：#73 周二提测，不再改期。周二没提测，我们就要谈 v1.1 的范围了。"),
                   out: [dec("#73 周二提测，不再改期；若周二仍未提测，再谈 v1.1 的范围。")] },
            2 => { by: :fiona, add: talk("Fiona：@ 提及的通知，站内和邮件都要。",
                                         "Ada：邮件正文别太长，一行摘要加一个链接。",
                                         "Fiona：请问被提到的人不在项目里怎么办？",
                                         "Ada：不通知，评论里给提示。") },
            3 => { by: :sam, add: talk("Sam：今天开始 Quinn 正式接五个包：#68、#75、#79、#98、#99。",
                                       "Quinn：我确认一下，#68 是 Frank 之前的吗？",
                                       "Fiona：是，Frank 借调前留了交接说明，我代讲。",
                                       "Bob：#75 和 #79 我讲。#75 的口径还没定，你先别动数据结构。",
                                       "Ben：#99 是我原来的，扫描件的回归用例，Mia 和我对过样本。",
                                       "Quinn：#98 评测集呢？",
                                       "Fiona：Mia 笔记放在评测集目录里了。",
                                       "Quinn：好，我先读，有问题我再问。"),
                   out: [info("Quinn 接手 #68、#75、#79、#98、#99，各自的背景已由 Bob、Ben、Fiona 讲过。")] },
            4 => { by: :fiona, add: talk("Fiona：#81 已经逾期四天。估四十小时，光标同步延迟又冒出来一个，要重做一部分。",
                                         "Ada：剩多少？",
                                         "Fiona：我觉得十四小时。",
                                         "Sam：我当没听见“我觉得”。",
                                         "Fiona：好，我周三前重估一遍。") },
            5 => { by: :ben, add: talk("Ben：我走之前把权限的设计写好了，回来只剩接口。",
                                       "Sam：剩多少？",
                                       "Ben：十六小时。",
                                       "Sam：乘一点六是二十五六。",
                                       "Ben：……你别乘。",
                                       "Ada：#94 DOCX 合并单元格，这个缺陷一直放着，Ben 你先收。",
                                       "Ben：好，周三前。") }
          },
          sections: [["行动项", [actions([:fiona, "#81 剩余工作量重估", 2],
                                         [:ben, "#94 合并单元格缺陷收口", 2],
                                         [:bob, "#73 周二提测，不再改期", 1],
                                         [:quinn, "读完 #75 的评论和 Bob 的口径说明", 1])]]]
        },
        {
          title: "待办梳理（Backlog Refinement）", host: :ada, attended: AFTER_LOAN,
          items: {
            1 => { by: :ada, add: talk("Ada：导出 Word、PDF、Markdown 三种，样式尽量一致。",
                                       "Fiona：PDF 的封面算不算页？页码放哪？（#112）",
                                       "Ada：封面不算页，页码放底部居中。",
                                       "Sam：这条我记到工作包里。") },
            2 => { by: :ada, add: talk("Ada：多知识库隔离，范围太大，v2.0 再说。",
                                       "Bob：#95 权限变更后检索缓存失效，要不要先做？",
                                       "Ada：和 #69 一起收尾，别单独排。") },
            3 => { by: :sam, add: talk("Sam：#91 章节衔接断裂，Ben 来；#93 PDF 表格错乱，谁来？",
                                       "Bob：Mia 才懂 PDF 的表格，她借调了。",
                                       "Fiona：我不熟。",
                                       "Ben：我手上满了。",
                                       "Quinn：……我可以看一下，但可能需要有人带。",
                                       "Ada：不要让新人一个人啃。先放待办池，Mia 回来之前别排进迭代。") }
          },
          append: [
            wp_item(81, 20, talk("Sam：说一句不太好听的，四十小时一个包，评审会上我都不知道怎么演示它。",
                                  "Fiona：这个我拆不开，光标、合并、离线是缠在一起的。",
                                  "Quinn：请问“光标同步”和“冲突合并”，是不是可以分开验收？",
                                  "Bob：#109 离线合并本来就是独立的子包，#108 光标同步也是。",
                                  "Sam：所以可以拆成三个：光标同步、内容合并、离线冲突，每个不超过五点。",
                                  "Fiona：每个五点……我得重新估一遍。",
                                  "Ada：好问题，Quinn。我倾向于拆，周一计划会上确认。",
                                  "Fiona：我周五前把拆分草稿给你。"), by: :sam,
                                  out: [info("有人建议把 #81 拆成光标同步、内容合并、离线冲突三个故事（各不超过 5 点），由 Ada 在 Sprint 7 计划会上确认。")]),
            wp_item(73, 10, talk("Bob：#73 昨天没提测，对账有一个用例没过。",
                                  "Ada：说好周二的。",
                                  "Bob：我周五评审会前一定提测。",
                                  "Sam：我周五前把范围清单列出来，以防万一。",
                                  "Ada：先看周五。"), by: :bob),
            item("Sprint 7 候选与估点", 15, talk("Ada：S7 的主线是 v1.1 收尾，候选有 #56、#70、#77、#91、#93、#112，再加 #73 #100 的尾巴。",
                                                  "Sam：#76 要等 #73，#77 要等 #75，两个包都在 Bob 和 Quinn 手上。",
                                                  "Ben：#56 五点，我估十六小时。",
                                                  "Sam：我们周五回顾再说这个。"), by: :ada)
          ],
          sections: [["行动项", [actions([:fiona, "#81 拆分草稿", 4],
                                         [:ada, "在 Sprint 7 计划会上确认 #81 要不要拆", 7],
                                         [nil, "#93 PDF 表格错乱：找一个人认领"])]]]
        },
        {
          title: "Sprint 6 评审会", host: :sam, attended: AFTER_LOAN,
          items: {
            1 => { by: :fiona, add: talk("Fiona：套餐升级的流程，从选套餐到支付成功……（#74 周三 Ada 已经验收关闭，今天是给全组看一遍）",
                                         "（页面空白了半分钟）",
                                         "Bob：我刚部署了一版。",
                                         "Fiona：我正在演示。",
                                         "Bob：我不知道。",
                                         "Ada：没事，我看到了前半段。后半段重来一次。",
                                         "Fiona：支付成功后套餐立刻生效。配额告警 UI 在 #76，S7 做。",
                                         "Ada：配额告警的文案还要再改，放在 #76 里。") },
            2 => { by: :fiona, add: talk("Fiona：会话可以重命名、归档、搜索。",
                                         "Ada：回看三天前的会话，我试一下……可以。",
                                         "Ada：这个我周二已经验收了，今天是让大家都看到。") },
            3 => { by: :sam, add: talk("Sam：发布检查清单，十二项过了九项。迁移脚本还没演练，回滚方案还在写。",
                                       "Ada：迁移演练什么时候？",
                                       "Sam：我下周二排。") }
          },
          append: [
            item("Sprint 6 完成情况", 10, talk("Sam：承诺三十八点，完成二十九点，结转九点：#73 八点，#100 一点，都是 Bob 的。",
                                                "Ada：九点，压在 Bob 请假的那周。",
                                                "Sam：对，就是这个。"), by: :sam,
                                                 out: [info("Sprint 6 完成 29 点（承诺 38），结转 9 点。速度：29。")]),
            item("演示：试用到期不能再调用", 5, talk("Quinn：这是我第一次演示，请多包涵。",
                                                        "Quinn：试用到期以后，账号再发请求会提示“试用已结束”，不再调用。",
                                                        "Ada：很清楚。Bob 写的说明，你做的？",
                                                        "Quinn：我补了测试。",
                                                        "Bob：他补得比我细。"), by: :quinn),
            item("v1.1 的日期", 20, talk("Ada：我直接问：下周五，v1.1 还守得住吗？",
                                          "Sam：按现在的结转看，前提是 #73 周一前提测、#100 修完。Bob 周三起不在。",
                                          "Bob：我周三起休三天，之前我一定把 #73 和 #100 收掉。",
                                          "Ada：Bob，你上次也说“周五前一定”。",
                                          "Bob：这次我提前……周二吧。",
                                          "Fiona：请问 #76 要等 #73 的接口，周二才好就只剩三天了。",
                                          "Ada：所以我担心的不是 Bob，是整条链。",
                                          "Sam：我周日把能砍的范围列出来，周一计划会上一起定。",
                                          "Ada：那就这样，周一定。"), by: :ada,
                                           out: [info("v1.1（Sprint 7 第一周周五）的日期风险已提出；Sprint 7 计划会上决定守日期还是砍范围。")]),
            item("上次行动项", 5, talk("Fiona：#81 拆分草稿，说好今天给，我今晚发。（逾期）",
                                        "Ada：好，晚点也行。",
                                        "Bob：#73 上周的改期我已经认了。"))
          ],
          sections: [["行动项", [actions([:sam, "列出 v1.1 能砍的范围清单，写明各自代价", 6],
                                         [:bob, "#73、#100 周二前提测", 8],
                                         [:sam, "v1.1 迁移脚本演练", 8])]]]
        }
      ]
    end

    def build(spec)
      return if Meeting.exists?(project:, title: spec[:title])

      host = user(spec[:host])
      User.current = host
      start = ctx.at(spec[:day], spec[:hm])
      minutes = [spec[:minutes], planned_minutes(spec)].max
      meeting = Meeting.new(project:, author: host, title: spec[:title], start_time: start, duration: minutes / 60.0,
                            location: "线上会议")
      spec[:invited].each do |key|
        absent = spec[:absent].include?(key)
        status = absent ? :declined : (spec[:tentative].include?(key) ? :tentative : :accepted)
        meeting.participants.build(user: user(key), invited: true, attended: !absent && spec[:tentative].exclude?(key),
                                   participation_status: status)
      end
      meeting.save!
      spec[:sections].each.with_index(1) { |(title, items), index| add_section(meeting, host, title, items, index, start) }
      created = ctx.at(ctx.backward(start.to_date - 2), "10:00")
      settle(meeting, created, start + minutes.minutes + 25.minutes)
    end

    def planned_minutes(spec) = (spec[:sections].sum { |_, items| items.sum { it[:min] } } / 5.0).ceil * 5

    def amend(spec)
      meeting = Meeting.find_by!(project:, title: spec[:title])
      host = user(spec[:host])
      User.current = host
      start = meeting.start_time
      existing = meeting.agenda_items.reorder(:meeting_section_id, :position).to_a
      spec[:items].each { |index, patch| patch_item(existing.fetch(index - 1), patch, host) }
      section = meeting.sections.first
      Array(spec[:append]).each.with_index(existing.size + 1) { |data, position| add_item(meeting, section, host, data, position, start) }
      spec[:sections].each.with_index(meeting.sections.count + 1) { |(title, items), index| add_section(meeting, host, title, items, index, start) }
      update_participants(meeting, spec[:attended]) if spec[:attended]
      minutes = [(meeting.duration * 60).to_i, (meeting.agenda_items.sum(:duration_in_minutes) / 5.0).ceil * 5].max
      meeting.update_columns(duration: minutes / 60.0)
      settle(meeting, meeting.created_at, start + minutes.minutes + 25.minutes)
    end

    def update_participants(meeting, attended)
      meeting.participants.find_each do |participant|
        present = attended.include?(AssistantSeed::PEOPLE.key(participant.user_id))
        participant.update_columns(attended: present, participation_status: MeetingParticipant.participation_statuses.fetch(present ? "accepted" : "declined"))
      end
    end

    def patch_item(agenda_item, patch, host)
      notes = agenda_item.notes.to_s
      return if patch[:add] && notes.include?(patch[:add])

      agenda_item.update_columns(notes: [notes, patch[:add]].compact_blank.join("\n\n"),
                                 presenter_id: (patch[:by] ? user(patch[:by]).id : agenda_item.presenter_id))
      create_outcomes(agenda_item, patch[:out], host)
    end

    def add_section(meeting, host, title, items, position, start)
      section = MeetingSection.create!(meeting:, title:, position:)
      items.each.with_index(1) { |data, index| add_item(meeting, section, host, data, index, start) }
    end

    def add_item(meeting, section, host, data, position, start)
      work_package_id = linkable?(data[:wp], start) ? data[:wp] : nil
      title = data[:title] || (subject(data[:wp]) unless work_package_id)
      agenda_item = MeetingAgendaItem.create!(
        meeting:, meeting_section: section, author: host, presenter: (user(data[:by]) if data[:by]), title: (title unless work_package_id),
        notes: data[:notes], position:, duration_in_minutes: data[:min], work_package_id:,
        item_type: work_package_id ? :work_package : :simple
      )
      create_outcomes(agenda_item, data[:out], host)
    end

    def create_outcomes(agenda_item, outcomes, host)
      MeetingAgendaItem.no_touching do
        Array(outcomes).each { |kind, text| MeetingOutcome.create!(meeting_agenda_item: agenda_item, kind:, notes: text, author: host) }
      end
    end

    def linkable?(id, start)
      return false unless id

      created = WorkPackage.where(id:).pick(:created_at)
      created.present? && created <= start
    end

    def subject(id) = WorkPackage.where(id:).pick(:subject)

    def settle(meeting, created, closed)
      meeting.update_columns(created_at: created, updated_at: closed, state: Meeting.states.fetch("closed"))
      [meeting.sections, MeetingOutcome.where(meeting_agenda_item_id: meeting.agenda_items.select(:id)),
       meeting.participants].each { |scope| scope.unscope(:order).update_all(created_at: created, updated_at: closed) }
      meeting.agenda_items.unscope(:order).update_all(created_at: created, updated_at: closed, lock_version: 0)
      count = Journal.where(journable_type: "Meeting", journable_id: meeting.id).count
      step = count > 1 ? ((closed - created) / (count - 1)).to_i : 1
      ctx.retime(meeting, closed, step)
    end
  end
end
# rubocop:enable Layout/LineLength
