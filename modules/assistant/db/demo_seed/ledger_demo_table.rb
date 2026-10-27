# frozen_string_literal: true

# rubocop:disable Layout/LineLength
module DemoSeed
  # What the assistant understood from the comments (the ledger of Intents), written down once.
  #
  # Each row is a comment (work package, author, a phrase that appears in it) and what the reading made of it. The
  # phrase must be unique among that author's comments on that work package; a row whose comment cannot be found is
  # skipped and reported, never fatal.
  #
  # Rows with `model: true` go through the real reader (Assistant::Understanding::Extractor, a language model); the
  # result is kept when it agrees with the row (same kind and owner) and replaced by the row otherwise, so the demo
  # does not depend on how the model feels today. All other rows are the rule tier: the row is the reading.
  #
  # `misread: true` marks the readings the assistant gets wrong on purpose (the demo script corrects them):
  #   1. #73  Bob  conditional "如果财务周一前把最终口径发我，我周二前提测" recorded as a firm promise for Tuesday
  #   2. #88  Ben  retraction "周四前给出文档这件事我没做到。现在先不承诺周几" not understood: the Thursday promise stays open
  #   3. #116 Sam  relayed "Bob 说过周四给回滚方案" recorded as Sam's own promise
  # Read right on purpose (not recorded, or recorded as what they are), listed so the script can point at them:
  #   #73 Ada quoting Bob's "周五前一定"; #233 Fiona's conditional; #252 Sam relaying Mia; #259 Ben's overnight joke;
  #   #68 Ada/Fiona "不修" is a decision nobody wrote down (Quinn asks the assistant about it and stays unanswered).
  module LedgerTable
    module_function

    def wd(day, next_week: false) = { "kind" => "weekday", "value" => day, "next_week" => next_week || nil }.compact

    TODAY = { "kind" => "today" }.freeze
    TOMORROW = { "kind" => "tomorrow" }.freeze
    THIS_WEEK_END = { "kind" => "end_of_week" }.freeze

    # [kind, work package, author, phrase, title, options]
    def rows
      [*week_73, *week_100_104, *week_75_68_79, *week_69_88_81, *week_313_340, *week_misc, *history]
    end

    def c(wp, who, find, title, **) = [:commitment, wp, who, find, title, { **}]
    def d(wp, who, find, title, **) = [:decision, wp, who, find, title, { **}]
    def q(wp, who, find, title, **) = [:question, wp, who, find, title, { **}]
    def f(wp, who, find, title, **) = [:deferral, wp, who, find, title, { **}]
    def o(wp, who, find, title, **) = [:objection, wp, who, find, title, { **}]

    def week_73
      [
        c(73, :bob, "扣减接口周三前合进去", "扣减接口周三前合进去", to: :sam, due: wd(3), says: "周三前", status: "done", by: [73, :sam, "扣减接口已合并"], quote: "扣减接口周三前合进去，周四联调。"),
        d(73, :ada, "按这个口径收尾，周三提测，不再改期", "#73 按财务口径收尾，周三提测，不再改期", to: :bob, superseded_by: [73, :ada, "周二没提测，#76 就按砍范围走"], quote: "#73 按这个口径收尾，周三提测，不再改期。那就这样。"),
        c(73, :bob, "周三之前一定提测", "周三提测", to: :ada, due: wd(3), says: "周三之前", moves: 1, due_on: 4, model: true, quote: "周三之前一定提测。"),
        c(73, :bob, "如果财务周一前把最终口径发我", "周二前提测", to: :ada, due: wd(2), says: "周二前", misread: true, quote: "如果财务周一前把最终口径发我，我周二前提测"),
        c(73, :sam, "我今天把 #76 #77 对它的依赖列出来给 Ada", "把 #76 #77 对 #73 的依赖列给 Ada", to: :ada, due: TODAY, says: "今天", status: "done", by: [73, :ada, "那就这样：周二上午看结果"]),
        d(73, :ada, "周二没提测，#76 就按砍范围走", "周二没提测，#76 就按砍范围走", to: :sam, quote: "那就这样：周二上午看结果。周二没提测，#76 就按砍范围走。"),
        c(73, :fiona, "能不能请 Bob 周二前把 #73 的接口说明单独发给我", "周二前把 #73 的接口说明单独发给 Fiona", owner: :bob, to: :fiona, str: "requested", due: wd(2, next_week: true), says: "周二前"),
        c(119, :sam, "砍范围清单我开始写了", "砍范围清单周日晚上贴在 #119", to: :ada, due: wd(7), says: "周日晚上", quote: "周日晚上贴在这里。"),
        c(116, :sam, "迁移脚本演练是我的，排在下周二", "迁移脚本演练排在下周二", to: :ada, due: wd(2, next_week: true), says: "下周二", quote: "迁移脚本演练是我的，排在下周二。"),
        c(116, :sam, "Bob 说过周四给回滚方案", "周四给回滚方案", to: :bob, due: wd(4), says: "周四", misread: true, quote: "Bob 说过周四给回滚方案"),
        c(116, :bob, "回滚方案周四给你", "回滚方案周四给 Sam", to: :sam, due: wd(4), says: "周四", status: "done", by: [116, :bob, "回滚方案写完了"]),
        c(116, :sam, "检查清单先列出来，周三前补全", "检查清单周三前补全", due: wd(3), says: "周三前", status: "done", by: [116, :sam, "清单补全了"])
      ]
    end

    def week_100_104
      [
        c(100, :bob, "周二前合并", "行级锁周二前合并", to: :sam, due: wd(2), says: "周二前", status: "done", by: [100, :bob, "已合并。并发 200 压测"], model: true),
        c(100, :bob, "老账号脚本明天写", "老账号一次性脚本，周日凌晨跑", to: :sam, due: TOMORROW, says: "周日凌晨", moves: 2, due_on: 6, quote: "老账号脚本明天写。"),
        f(100, :bob, "我先不关，下周二跟 #73 一起关", "先不关 #100，下周二跟 #73 一起关", to: :ada, due: wd(2, next_week: true), says: "下周二", quote: "我先不关，下周二跟 #73 一起关。"),
        d(100, :ada, "既然修好了就关掉，脚本另开一条", "已经修好的缺陷就关掉，脚本另开一条", to: :bob),
        q(100, :sam, "现在没人在跑。#100 还开着是不是因为这个？", "#100 还开着是不是因为老账号脚本没人跑", to: :bob, by: [100, :bob, "对。超扣本身已经修好了"]),
        c(100, :sam, "周日凌晨跑脚本，周一早上我看结果", "周一早上看老账号脚本的结果", to: :bob, due: wd(1, next_week: true), says: "周一早上", quote: "收到：周日凌晨跑脚本，周一早上我看结果。"),
        q(104, :sam, "谁来测？", "幂等这条谁来测", by: [104, :bob, "我自己先测了十几组重复回调"]),
        q(104, :fiona, "请问重复回调的间隔多久算重复？", "多久间隔内的重复回调算重复", to: :bob, by: [104, :bob, "30 秒和 5 分钟的也补测了"]),
        c(104, :bob, "压测报告我周三前补到维基", "压测报告周三前补到维基“测试策略”页", to: :sam, due: wd(3), says: "周三前", model: true)
      ]
    end

    def week_75_68_79
      [
        q(75, :quinn, "这个我理解对吗？", "对账口径我的理解对不对", to: :bob, by: [75, :bob, "基本对。Frank 在 S5"]),
        d(75, :ben, "退款要冲回，用一条负数流水", "退款冲回用一条负数流水，金额与原流水对应", quote: "退款要冲回，用一条负数流水，金额和原流水对应。"),
        d(75, :sam, "财务回了口径", "财务口径：逐条折算四舍五入到分，退款用负数流水冲正，对账周期按自然月", quote: "财务回了口径："),
        c(75, :sam, "Ben 的答复我转给财务再确认一遍", "把 Ben 的答复转给财务再确认，答复后更新到 #75", quote: "Ben 的答复我转给财务再确认一遍，他们答复后我更新到这里。"),
        q(75, :quinn, "请问冲正流水要不要带原流水的编号？", "冲正流水要不要带原流水的编号", to: :bob, by: [75, :bob, "带，字段叫 reversal_of"]),
        d(75, :bob, "带，字段叫 reversal_of", "冲正流水带原流水编号，字段叫 reversal_of", quote: "带，字段叫 reversal_of。", model: true),
        c(75, :quinn, "我估计下周一前能做完", "对账报表下周一前做完", to: :sam, str: "tentative", due: wd(1, next_week: true), says: "下周一前", quote: "我估计下周一前能做完，但这是我第一次做对账，可能不准。"),
        q(75, :quinn, "请问对账报表的导出格式要和 #101 的按天聚合报表一致吗？", "对账报表导出格式要不要与 #101 一致", to: :sam, by: [75, :sam, "#101 还没开始，先不管一致"]),
        d(75, :sam, "先不管一致，等 #75 好了再合", "对账报表导出格式先不与 #101 保持一致", quote: "#101 还没开始，先不管一致，等 #75 好了再合。"),
        d(68, :ada, "跨文档先在当前页内跳转，新标签页做成设置项", "跨文档先在当前页内跳转，新标签页做成设置项放到 v2.0", quote: "跨文档先在当前页内跳转，新标签页做成设置项，放到 v2.0。那就这样。", model: true),
        q(68, :quinn, "请问 Ada 问的跨文档要不要新标签页打开，也一起测吗？", "跨文档新标签页要不要一起测", to: :fiona, by: [68, :fiona, "Ada 那个问题还没定"]),
        q(79, :quinn, "先确认我理解对不对", "#79 的根因和要验证的三个场景我理解对不对", to: :bob, by: [79, :bob, "对。测试账号我在 #75 里留了三个"], quote: "先确认我理解对不对：根因是结算任务重置了试用期的 quota 字段，Bob 的补丁已经合并，我要验证的是试用到期、续费、降级三个场景，对吗？"),
        c(79, :quinn, "降级场景明天", "降级场景明天测完", to: :sam, due: TOMORROW, says: "明天", status: "done", by: [79, :quinn, "降级场景也测完了"], quote: "降级场景明天。")
      ]
    end

    def week_69_88_81
      [
        d(69, :ben, "冲突时以知识库级为准", "两级权限冲突时以知识库级为准；知识库级关闭共享后，文档级再开也无效", to: :fiona, quote: "冲突时以知识库级为准，知识库级关闭共享时，文档级再开也无效。"),
        q(69, :fiona, "请问接口周三前能联调吗？", "接口周三前能不能联调", to: :ben, by: [69, :ben, "应该能。还剩 16 小时"]),
        d(69, :sam, "周中同步会上定了：权限只做知识库级和文档级两层", "权限只做知识库级和文档级两层，截止日顺延到本迭代末", quote: "周中同步会上定了：权限只做知识库级和文档级两层，范围收窄，截止日顺延到本迭代末。"),
        d(69, :ada, "Sprint 7 里只排接口联调，范围不再扩", "Sprint 7 里 #69 只排接口联调，范围不再扩", quote: "同意。Sprint 7 里只排接口联调，范围不再扩。那就这样。"),
        c(88, :ben, "我周一上午十点前给出日期", "周一上午十点前给出接口文档的日期", to: :sam, due: wd(1, next_week: true), says: "周一上午十点前", model: true, quote: "好，我周一上午十点前给出日期。"),
        q(88, :fiona, "分页参数这一节有草稿吗？", "分页参数那一节有没有草稿", to: :ben, by: [88, :ben, "还没有，周四给完整版"]),
        q(88, :fiona, "请问今天能给吗？周四到了", "接口文档今天能不能给", to: :ben, by: [88, :ben, "今天给不了"]),
        o(81, :sam, "待办梳理会的建议是拆成三个故事", "待办梳理会建议把 #81 拆成三个故事，各不超过 5 点", to: :ada, parent: [:title, "多人同时编辑 #81 整体做完，不拆分"], quote: "待办梳理会的建议是拆成三个故事，各不超过 5 点"),
        c(81, :fiona, "好的，我周五前把拆分草稿给 Ada", "周五前把 #81 拆分草稿给 Ada", to: :ada, due: wd(5), says: "周五前", moves: 1, due_on: 4, quote: "好的，我周五前把拆分草稿给 Ada。"),
        c(81, :fiona, "这周内补完", "这周内补完离线合并", due: THIS_WEEK_END, says: "这周内", status: "superseded", by: [81, :sam, "待办梳理会的建议是拆成三个故事"], quote: "离线合并还没做完，周五来不及了，这周内补完。"),
        c(94, :ben, "回归我自己补了 3 个合并单元格的样本，周三转测试中", "周三转测试中", to: :sam, due: wd(3), says: "周三", status: "done", by: [94, :ben, "已转“测试中”"], quote: "回归我自己补了 3 个合并单元格的样本，周三转测试中。")
      ]
    end

    def week_313_340
      [
        d(313, :ada, "没有异议，那就这样，改全文检索，我来负责", "文档库搜索由向量初筛改为全文检索，负责人 Ada", model: true, quote: "没有异议，那就这样，改全文检索，我来负责。"),
        o(313, :bob, "要不要把全文检索的决定撤掉", "要不要撤掉全文检索的决定，仍以向量召回为基础", to: :ada, parent: [313, :ada, "没有异议，那就这样"], model: true),
        q(313, :fiona, "如果撤销，短查询怎么办？", "撤销全文检索后短查询怎么办", to: :ada),
        q(313, :sam, "你对 Bob 的问题怎么看？", "Ada 对 Bob 提出的撤销问题怎么看", to: :ada),
        q(313, :quinn, "请问这个结论出来了吗？", "ADR-005 里中文分词扩展的结论出来了没有", to: :ada, by: [313, :sam, "没有。Ada，这个待办还挂着"], model: true),
        q(340, :quinn, "决定记录是不是该更新？", "决定记录里的对话历史保留期是不是该更新", to: :ada, by: [340, :ada, "对，说明是 10月6日改的"], model: true),
        c(340, :ada, "决定记录是 Sam 记的，Sam 看一下", "更新决定记录里的对话历史保留期", owner: :sam, to: :ada, str: "requested", quote: "决定记录是 Sam 记的，Sam 看一下。")
      ]
    end

    def week_misc
      [
        c(70, :bob, "我周二前画一张流程图给你", "周二前画 indexer diff 模块的流程图给 Quinn", to: :quinn, due: wd(2, next_week: true), says: "周二前", model: true),
        c(70, :quinn, "我可以看一下 #97", "看一下 #97", to: :sam, str: "tentative", quote: "我可以看一下 #97。"),
        c(333, :fiona, "我周一带他过一遍", "周一带 Quinn 过一遍 #333", to: :sam, due: wd(1, next_week: true), says: "周一", model: true),
        c(333, :quinn, "好的，我周一开始看", "周一开始看 #333", to: :sam, due: wd(1, next_week: true), says: "周一", quote: "好的，我周一开始看。"),
        c(56, :ada, "#56 和 #92 按回顾会说的重新估一遍", "#56 #92 按回顾会说的重新估算，周一计划会要用", owner: :ben, to: :ada, str: "requested", due: wd(1, next_week: true), says: "周一", model: true),
        c(98, :ada, "我周五前给你十篇", "周五前给 Quinn 十篇会议纪要", to: :quinn, due: wd(5), says: "周五前", status: "done", by: [98, :ada, "十篇纪要放在共享目录"], quote: "我周五前给你十篇。"),
        c(98, :quinn, "这周能补 10 篇吗，我不确定", "这周补 10 篇会议纪要", to: :sam, str: "tentative", due: THIS_WEEK_END, says: "这周", quote: "我先补会议纪要，这周能补 10 篇吗，我不确定。"),
        c(55, :bob, "周五前一定能关", "#55 周五前关掉", to: :ada, due: wd(5), says: "周五前", status: "done", by: [55, :ada, "这条周五前关了，Bob 这次兑现了"], quote: "降级只剩两处。周五前一定能关。"),
        c(110, :fiona, "邮件通知今天接上", "邮件通知今天接上", due: TODAY, says: "今天", status: "done", by: [110, :fiona, "邮件通知也做完了"], quote: "邮件通知今天接上。"),
        d(54, :ada, "隐藏，加一个“显示已归档”的开关", "归档后的会话在默认列表里隐藏，加“显示已归档”的开关，放 Sprint 7", model: true, quote: "隐藏，加一个“显示已归档”的开关。放 Sprint 7。"),
        q(54, :fiona, "请问归档后的会话要不要在默认列表里隐藏？", "归档后的会话要不要在默认列表里隐藏", to: :ada, by: [54, :ada, "隐藏，加一个“显示已归档”的开关"]),
        d(87, :ada, "不用，先截断，模型总结以后再说", "会话标题先截断，不让模型总结", quote: "不用，先截断，模型总结以后再说。"),
        q(87, :fiona, "请问要不要让模型总结一个标题？", "要不要让模型总结会话标题", to: :ada, by: [87, :ada, "不用，先截断"]),
        d(89, :bob, "阈值定了：免费版每分钟 20 次", "限流阈值：免费版每分钟 20 次，专业版 120 次，团队版 600 次", model: true, quote: "阈值定了：免费版每分钟 20 次，专业版 120 次，团队版 600 次。"),
        d(90, :ada, "先放占位", "降级提示先放占位文案，正式文案 Sprint 7 再定", to: :fiona, quote: "先放占位：“当前模型繁忙，已切换到备用模型”，正式文案 Sprint 7 再定。"),
        q(90, :fiona, "请问 #55 提测前要不要先放一句占位文案？", "#55 提测前要不要先放占位文案", to: :ada, by: [90, :ada, "先放占位"]),
        d(112, :ada, "封面不算页，目录算第 1 页，页码放页脚居中", "PDF 页码：封面不算页，目录算第 1 页，页码放页脚居中", model: true, quote: "封面不算页，目录算第 1 页，页码放页脚居中。"),
        f(85, :ada, "这条先不排，放着，有第三个客户提再评估", "写作模板市场先不排，有第三个客户提再评估", quote: "这条先不排，放着，有第三个客户提再评估。"),
        f(323, :fiona, "Sprint 7 以后再看", "导出 Word 保留批注，Sprint 7 以后再看", quote: "我把它挂在 #83 下面，Sprint 7 以后再看。")
      ]
    end

    def history
      [
        d(206, :frank, "改成 2 秒，连续 2 次失败摘除", "探测间隔 2 秒，连续 2 次失败摘除", to: :bob),
        c(205, :bob, "两个错误码，周五前一定合进去", "两个错误码周五前合进去", to: :frank, due: wd(5), says: "周五前", status: "done"),
        c(205, :bob, "周二前定完", "日志字段周二前定完", to: :sam, due: wd(2), says: "周二前", status: "done"),
        c(208, :bob, "脚本周三前出", "压测脚本周三前出", due: wd(3), says: "周三前", status: "done"),
        c(219, :sam, "加，明天给你", "明天给上限的数值", due: TOMORROW, says: "明天", status: "done"),
        c(227, :ben, "标题层级我周五前合进去", "标题层级周五前合进去", due: wd(5), says: "周五前", status: "withdrawn", by: [227, :ben, "上面那个“周五前”我撤回"]),
        c(227, :ben, "还要半天，中午前合进去", "中午前合进去", due: TODAY, says: "中午前", status: "done"),
        d(233, :ben, "字段今天定死了", "状态字段加一种“部分成功”，今天定死", to: :fiona, quote: "那就加一种“部分成功”，字段今天定死了。"),
        c(235, :fiona, "我周二前把 413 的提示加上", "周二前把 413 的提示加上", to: :bob, due: wd(2), says: "周二前", status: "done"),
        c(240, :bob, "尽量吧", "上传限流，尽量给", str: "tentative", quote: "我看看，应该没问题，尽量吧。"),
        d(242, :ada, "先用 A，C 作为将来的升级选项记进决定记录", "先用方案 A，C 作为将来的升级选项", quote: "同意。先用 A，C 作为将来的升级选项记进决定记录。"),
        d(254, :frank, "片段预算改成 35%", "片段预算改成 35%", quote: "用 top 3 重跑，质量没掉，片段预算改成 35%。"),
        c(259, :ben, "明天中午前给你修复", "明天中午前给出修复", due: TOMORROW, says: "明天中午前", status: "done", quote: "开玩笑的，明天中午前给你修复。"),
        d(65, :ada, "宁可多拦", "拦截阈值保持现状，宁可多拦", quote: "宁可多拦。写作助手瞎编比拒答更糟。那就这样，阈值用现在的。"),
        d(49, :frank, "前缀缓存可以复用，和 KV 缓存那条", "前缀缓存与 KV 缓存一起做", quote: "前缀缓存可以复用，和 KV 缓存那条（#50）一起做。"),
        f(260, :sam, "向量库客户端、前端依赖，先记在这里，以后排", "向量库客户端和前端依赖升级先记着，以后排", quote: "另外还有几笔小债没动：向量库客户端、前端依赖，先记在这里，以后排。"),
        f(66, :fiona, "依赖升级的事我记进技术债", "前端依赖升级记进技术债", quote: "前端构建又涨到 6 分钟了，依赖升级的事我记进技术债。"),
        c(118, :sam, "账号和仓库权限今天开好", "Quinn 的账号和仓库权限今天开好", due: TODAY, says: "今天", status: "done"),
        c(98, :frank, "整理到 32 篇，还差 18 篇，下周继续", "下周继续整理评测集", str: "tentative", status: "superseded", by: [98, :sam, "Frank 借调到数据平台组，这条交给 Quinn"], quote: "整理到 32 篇，还差 18 篇，下周继续。")
      ]
    end
  end
end
# rubocop:enable Layout/LineLength
