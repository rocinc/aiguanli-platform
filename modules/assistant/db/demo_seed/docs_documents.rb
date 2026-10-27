# frozen_string_literal: true

require "tempfile"

module DemoSeed
  module DocsDocuments
    private

    def documents
      prd
      billing_design
      test_report
      release_checklist
      interview_notes
      permission_design
      say("documents=#{Document.where(project:).count}")
    end

    # versions: [[day, "HH:MM", author, text, note], ...]
    def write_document(title, type_name, versions)
      document = nil
      stamps = []
      versions.each do |day, hm, key, text, _note|
        as(key) do
          if document
            document.description = fmt(text)
          else
            document = Document.new(project:, title:, type: DocumentType.find_by!(name: type_name), kind: "classic", description: fmt(text))
          end
          document.save!
        end
        stamps << t(day, hm)
      end
      restamp(document, stamps)
      document
    end

    def attach(document, filename, content, key, description)
      Tempfile.create(["demo", File.extname(filename)]) do |file|
        file.write(content)
        file.flush
        attachment = Attachment.new(container: document, author: user(key), description:)
        attachment.file = File.open(file.path)
        attachment.filename = filename
        attachment.save!
        attachment.update_columns(created_at: document.updated_at, updated_at: document.updated_at)
      end
    end

    def prd
      history = [
        ["v0.1", -35, "{ada}", "初稿：背景、目标、范围"],
        ["v0.2", -21, "{ada}", "加入用户故事和验收标准；Sprint 5 评审后补充计费口径"],
        ["v0.3", -5, "{ada}", "权限收窄为两层；扫描件 OCR 移出范围；开放问题更新"]
      ]
      versions = history.each_with_index.map do |(_, day, _, note), index|
        [day, "10:00", :ada, prd_text(history.first(index + 1), index), note]
      end
      write_document("v1.1 商业化版 产品需求文档（PRD）", "规格说明", versions)
    end

    def prd_text(history, index)
      rows = history.map { |version, day, who, note| "| #{version} | {d:#{day}} | #{who} | #{note} |" }
      scope_row = index >= 2 ? "| 知识库权限 | 两层：知识库和文档（{adr:permissions}） | 项目级、角色级、临时授权 |" : "| 知识库权限 | 知识库和文档两级，团队内按成员或角色共享 | |"
      open_questions = index >= 2 ? "1. 升级套餐当月的配额口径：以套餐页为准，口径还没定稿。\n2. 用量统计是否整体随 v1.1 发布。" : "1. 升级套餐当月的配额怎么算。"
      <<~MD
        # v1.1 商业化版 产品需求文档（PRD）

        ## 版本说明

        | 版本 | 日期 | 作者 | 变化 |
        |---|---|---|---|
        #{rows.join("\n")}

        ## 背景

        v1.0 解决了\"基于资料写作\"。v1.1 要让它能收费：按用量计费、按套餐升级、配额用尽时有体面的提示。发布日期是硬日期：{d:11}。

        ## 目标

        1. 用户可以看到自己的用量，并在配额内使用。
        2. 用户可以在应用内升级套餐，升级立即生效。
        3. 计费准确：金额按 {adr:rounding} 的口径，并发不会多扣，支付回调不会重复入账。

        ## 范围

        | 能力 | 说明 | 不做 |
        |---|---|---|
        | 用量统计与配额扣减（#73） | 统计每个账号的调用量，按套餐实时扣减 | 实时仪表盘 |
        | 套餐与升级（#74） | 应用内升级，立即生效 | 年付折扣 |
        | 配额告警（#76） | 接近配额时提醒，用尽时降级提示 | 邮件告警 |
        #{scope_row}
        | 扫描件 | 提示用户暂不支持 | OCR（放到 v2.0，{adr:ocr}） |

        ## 验收标准

        1. 同一账号 32 并发请求，扣减总量与请求数一致（#100）。
        2. 支付回调重复发送三次，只入账一次（#104）。
        3. 试用期满后的调用被拒绝，并提示升级（#79）。
        4. 月度账单总额等于明细之和（#102）。

        ## 开放问题

        #{open_questions}

        相关讨论见论坛\"用户反馈\"，技术方案见 {doc:计费与配额技术方案}。
      MD
    end

    def billing_design
      versions = [
        [-20, "14:00", :frank, billing_text(false), "初稿"],
        [-13, "16:00", :frank, billing_text(true), "加入预扣加结算（{adr:reserve}）"]
      ]
      write_document("计费与配额技术方案", "规格说明", versions)
    end

    def billing_text(with_reservation)
      flow = if with_reservation
               <<~'MD'
                 ## 扣减流程（v1.1）

                 1. 网关收到请求，向计费服务**预扣**一个估计值（按请求长度估算）。
                 2. 预扣成功才放行；余额不足直接拒绝，并带上降级提示。
                 3. 请求结束后，计费服务按实际 token 数**结算**：多退少补。
                 4. 结算写一条流水；流水只追加，更正用冲正记录。

                 网关不直接减余额。并发时预扣在计费服务内串行，避免读写余额不在一个事务里（#100）。
               MD
             else
               <<~'MD'
                 ## 扣减流程

                 请求结束后，网关按实际 token 数直接扣减账号余额。
               MD
             end
      <<~MD
        # 计费与配额技术方案

        ## 数据

        - 计费事件流水：只追加，不改（{adr:ledger}）。更正用冲正记录，对账时按口径重算。
        - 金额：每条流水按 token 折算后四舍五入到分，月度总额等于明细之和（{adr:rounding}）。

        #{flow}
        ## 支付回调

        回调带唯一回调号，按回调号去重，重复回调直接返回成功但不入账（#104）。

        ## 对账

        每月 1 日跑对账脚本，对比流水汇总与支付渠道账单。口径由财务确认，确认之前按现有口径跑（#75）。

        ## 风险

        1. 预扣估计偏小会造成结算时余额为负，需要上限保护。
        2. 对账口径变化要重算历史，流水的设计保证这一点。
      MD
    end

    def test_report
      versions = [
        [-3, "17:00", :sam, test_report_text(:early), "第一轮提测结果"],
        [4, "18:00", :sam, test_report_text(:late), "Sprint 6 评审之后更新"]
      ]
      document = write_document("v1.1 测试报告（进行中）", "报告", versions)
      attach(document, "v1.1-failing-cases.csv", failing_cases_csv, :sam, "未通过用例清单")
    end

    def test_report_text(stage)
      early = stage == :early
      billing = early ? [52, 41, 11, "78.8%"] : [52, 44, 8, "84.6%"]
      totals = early ? [259, 245, 14, "94.6%"] : [259, 248, 11, "95.8%"]
      conclusion = if early
                     "第一轮结果。计费类缺陷还很多，不建议发布。"
                   else
                     "**当前不建议发布。** 计费和配额类还有 8 个用例未通过，按[[缺陷分级标准]]这类缺陷从 P0 起评级，必须清零。"
                   end
      <<~MD
        # v1.1 测试报告（进行中）

        ## 版本说明

        | 版本 | 日期 | 作者 | 变化 |
        |---|---|---|---|
        | v0.1 | {d:-3} | {sam} | 第一轮提测结果 |
        #{early ? '' : '| v0.2 | {d:4} | {sam} | Sprint 6 评审之后更新 |'}

        ## 范围

        对话引擎、知识库、引用溯源、计费与配额。回归范围以[[v1.1 发布说明（草稿）]]为准，策略见[[测试策略]]。

        ## 结果

        | 模块 | 用例数 | 通过 | 失败 | 通过率 |
        |---|---:|---:|---:|---:|
        | 对话引擎 | 90 | 90 | 0 | 100% |
        | 知识库 | 71 | 69 | 2 | 97.2% |
        | 引用溯源 | 46 | 45 | 1 | 97.8% |
        | 计费与配额 | #{billing[0]} | #{billing[1]} | #{billing[2]} | #{billing[3]} |
        | 合计 | #{totals[0]} | #{totals[1]} | #{totals[2]} | #{totals[3]} |

        ## 未通过的主要原因

        - 并发超扣（#100）：32 并发下仍会多扣。
        - 支付回调幂等（#104）：重复回调的一条路径没有去重。
        - 用量统计汇总（#73）：按天汇总与流水合计对不上。
        - 试用期满（#79）：还有一条边界没有拒绝。
        - 知识库：DOCX 合并单元格（#94）、PDF 表格（#93）。
        - 引用溯源：跨文档同名章节（#68）。

        ## 结论

        #{conclusion}

        未通过的用例见附件。
      MD
    end

    def failing_cases_csv
      <<~CSV
        case,module,work_package,status
        concurrent-deduct-32,billing,100,fail
        concurrent-deduct-64,billing,100,fail
        concurrent-deduct-refund,billing,100,fail
        callback-duplicate-3x,billing,104,fail
        callback-out-of-order,billing,104,fail
        usage-daily-aggregate,billing,73,fail
        usage-month-boundary,billing,73,fail
        trial-expired-boundary,billing,79,fail
        docx-merged-cell,knowledge,94,fail
        pdf-table-extract,knowledge,93,fail
        cross-doc-same-heading,citation,68,fail
      CSV
    end

    def release_checklist
      history = [["v0.1", -3, "{sam}", "列出检查项"], ["v0.2", 2, "{sam}", "补负责人和日期"], ["v0.3", 4, "{sam}", "Sprint 6 评审后更新状态"]]
      versions = history.each_with_index.map do |(_, day, _, note), index|
        [day, "11:00", :sam, checklist_text(history.first(index + 1), index), note]
      end
      document = write_document("v1.1 发布检查清单", "文档", versions)
      attach(document, "v1.1-release-checklist.csv", checklist_csv, :sam, "检查清单的表格版")
    end

    CHECKLIST = [
      ["迁移脚本", "Bob", 8, "未开始", "套餐、配额、流水三张表的迁移，先在 staging 演练"],
      ["配额开关", "Bob", 9, "未开始", "按账号灰度打开，出问题可以一键关闭"],
      ["回滚方案", "Sam", 9, "进行中", "回滚到 v1.0.3，迁移要可逆"],
      ["对外公告", "Ada", 10, "进行中", "依据发布说明草稿，等范围定下来后定稿"],
      ["对账脚本回归", "Bob", 9, "未开始", "发布前后各跑一次，金额总额对得上"],
      ["监控阈值", "Bob", 10, "未开始", "配额误判任意一次都是 P1，见监控与告警"],
      ["客服口径", "Sam", 10, "未开始", "升级当月配额的口径定稿后补"],
      ["文档更新", "Ada", 10, "进行中", "发布说明、套餐页文案"]
    ].freeze

    def checklist_text(history, index)
      rows = history.map { |version, day, who, note| "| #{version} | {d:#{day}} | #{who} | #{note} |" }
      items = CHECKLIST.map do |item, owner, day, state, note|
        done = index >= 2 && item == "回滚方案" ? "进行中" : state
        "| #{item} | #{owner} | {d:#{day}} | #{done} | #{note} |"
      end
      table = index.zero? ? CHECKLIST.map { |item, _, _, _, note| "| #{item} | | | 未开始 | #{note} |" } : items
      <<~MD
        # v1.1 发布检查清单

        对应工作包 #116，负责人 {sam}。发布日期 {d:11}。

        ## 版本说明

        | 版本 | 日期 | 作者 | 变化 |
        |---|---|---|---|
        #{rows.join("\n")}

        ## 检查项

        | 检查项 | 负责人 | 完成日期 | 状态 | 说明 |
        |---|---|---|---|---|
        #{table.join("\n")}

        每一项完成后改状态并在 #116 的评论里写一句。发布当天由 Sam 按这张表逐项确认。
      MD
    end

    def checklist_csv
      rows = CHECKLIST.map { |item, owner, _day, state, _| "#{item},#{owner},#{state}" }
      "item,owner,status\n#{rows.join("\n")}\n"
    end

    def interview_notes
      write_document("内测用户访谈纪要（8 月）", "笔记", [[-56, "17:30", :ada, <<~'MD', "整理 5 次访谈"]])
        # 内测用户访谈纪要（8 月）

        访谈对象 5 位，都是写长文的人（自由撰稿 2、内容运营 2、研究生 1），每位约 30 分钟。访谈人：{ada}，{fiona} 旁听。

        ## 他们最在意的

        1. **能回到原文。** 研究生的原话："我不怕它写得不好，怕它写得好但我不知道是哪来的。"
        2. **语气一致。** 自由撰稿人说续写之后像换了一个人。
        3. **导出。** 内容运营两位都提到要导出 Word，并保留格式。

        ## 没想到的

        - 两位用户不知道可以上传资料，直接把资料粘进对话框。
        - 没有人主动提价格。

        ## 后续

        问题已经转成了待办，汇总见论坛"用户反馈"。
      MD
    end

    def permission_design
      versions = [
        [-19, "15:00", :ben, permission_text(false), "初稿"],
        [-5, "17:30", :ben, permission_text(true), "收窄为两层（{adr:permissions}）"]
      ]
      write_document("知识库权限设计说明", "规格说明", versions)
    end

    def permission_text(narrowed)
      model = if narrowed
                "知识库级和文档级两层。每一层都可以按成员或角色授权。项目级、临时授权放到后面（{adr:permissions}）。"
              else
                "项目级、知识库级、文档级三层，外加临时授权。"
              end
      <<~MD
        # 知识库权限设计说明

        对应工作包 #69。

        ## 权限模型

        #{model}

        | 角色 | 知识库 | 文档 |
        |---|---|---|
        | 所有者 | 管理成员、删除 | 全部 |
        | 编辑 | 上传、修改 | 编辑 |
        | 只读 | 查询、引用 | 查看 |

        ## 继承

        文档默认继承知识库的权限，也可以单独收紧，不能比知识库放得更宽。

        ## 检索缓存

        权限变化后，检索缓存要失效，否则用户会搜到刚被收回权限的内容（#95）。

        ## 迁移

        现有知识库默认所有成员只读，所有者保持不变。
      MD
    end
  end
end
