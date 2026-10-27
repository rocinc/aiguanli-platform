# frozen_string_literal: true

module DemoSeed
  module DocsNews
    private

    def news
      news_items.each do |item|
        stamp = t(*item[:at])
        as(item[:by]) do
          record = News.create!(project:, author: user(item[:by]), title: item[:title], summary: item[:summary],
                                description: fmt(item[:body]), created_at: stamp, updated_at: stamp)
          record.update_columns(created_at: stamp, updated_at: stamp)
          ctx.retime(record, stamp, 1.minute)
        end
      end
      say("news=#{news_items.size}")
    end

    def news_items
      [
        {
          title: "Sprint 3 评审摘要：向量库与切片基线就位", by: :sam, at: [-38, "17:30"],
          summary: "pgvector 部署完成，切片基线跑通；本迭代完成 25 点。",
          body: <<~'MD'
            Sprint 3 评审会已开完，摘要如下。

            ## 完成了什么

            - 向量库选型与部署完成，选型理由见[[决定记录：详述]]里的 {adr:pgvector}（#61）
            - 段落级切片与向量化入库跑通（#59）
            - 文档上传与解析支持 PDF、DOCX、Markdown（#58）

            ## 数字

            本迭代完成 25 点，前两个迭代分别是 18 点和 22 点。

            ## 下个迭代

            Sprint 4 的目标是引用溯源与幻觉拦截：每个论断都能点回原文。计划会在下周一上午。
          MD
        },
        {
          title: "v1.0.3 已发布：扫描件上传的提示更清楚了", by: :sam, at: [-18, "17:00"],
          summary: "上传扫描版 PDF 时，现在会明确提示\"这是扫描件，暂不支持文字识别\"。",
          body: <<~'MD'
            v1.0.3 已经发布到生产环境。

            ## 变化

            - 上传扫描版 PDF 时，不再静默失败，会提示"这是扫描件，暂不支持文字识别"（#62）

            ## 说明

            扫描件的文字识别目前不在计划内，会在后续版本里评估。已经上传过的文件不受影响。

            如果灰度期间发现异常，回滚到 v1.0.2，流程见[[部署与发布]]。
          MD
        },
        {
          title: "欢迎 Quinn 加入", by: :sam, at: [-4, "09:30"],
          summary: "Quinn Adeyemi 今天入项，首周先从五个工作包开始。",
          body: <<~'MD'
            Quinn Adeyemi 今天正式入项，欢迎。

            首周的第一批工作包是 #68 #75 #79 #98 #99，每个都有人带，Ben、Bob、Fiona 会把背景讲给 Quinn。

            新人可以先读这几页：

            1. [[术语表]]：团队的说法和统一用词
            2. [[决定记录]]：我们做过哪些决定，为什么
            3. [[评审与合并规范]]：PR 24 小时内给出第一次评审

            有不清楚的当天问，不用攒着。
          MD
        },
        {
          title: "v1.1 倒计时：发布日期是硬日期", by: :ada, at: [0, "10:20"],
          summary: "v1.1 的发布日期是硬日期，下面是必须落地的几件事。",
          body: <<~'MD'
            v1.1 商业化版计划在 {d:11} 发布，这个日期不会因为我们没准备好而移动。

            目前我认为必须落地的是：

            1. 用量统计与配额扣减（#73）
            2. 配额扣减并发超扣的修复（#100）
            3. 支付回调幂等（#104）
            4. 发布前检查清单逐项确认（#116）

            [[风险登记]]里写了每一项的现状和负责人。Sprint 7 计划会在 {d:7} 上午 10:00，届时需要把范围和人员排清楚。

            发布说明的草稿在[[v1.1 发布说明（草稿）]]，请大家看一下自己负责的条目是不是写对了。
          MD
        },
        {
          title: "Sprint 6 评审摘要：承诺 38 点，完成 29 点", by: :sam, at: [4, "17:30"],
          summary: "9 点带入 Sprint 7；计划会安排见会议页。",
          body: <<~'MD'
            Sprint 6 评审会和回顾会已经开完，摘要如下。

            ## 数字

            承诺 38 点，实际完成 29 点，缺口 9 点会带入 Sprint 7。最近三个迭代（Sprint 4 到 6）平均速度 29 点，详见[[速度与估算基线]]。

            ## 评审会

            演示了套餐升级与配额告警（#74）、会话管理（#54），并过了一遍 v1.1 发布准备（#116）。完整纪要见[[会议纪要归档]]。

            ## 回顾会

            三条改进，细节见[[迭代回顾汇总]]：两条已经有人认领，一条还没有。

            ## 接下来

            Sprint 7 计划会在 {d:7} 上午 10:00。v1.1 的发布日期仍然是 {d:11}，计划会上要把范围和人员排清楚。
          MD
        }
      ]
    end
  end
end
