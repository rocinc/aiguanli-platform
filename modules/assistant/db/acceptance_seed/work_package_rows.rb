# frozen_string_literal: true

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

# rubocop:disable-next Layout/LineLength
module AssistantSeed
  # Offsets are calendar days from the Monday of the seeded week.
  # st: new clarifying clear confirmed backlog planned doing devdone testing closed onhold
  WORK_PACKAGE_ROWS = [
    { id: 42, t: "对话引擎", ty: :epic, st: :doing, who: :ada, born: -80, desc: "让用户在编辑器里和模型多轮对话、流式生成、按风格改写。" },
    { id: 43, t: "单轮生成主链路打通", ty: :story, st: :closed, who: :frank, par: 42, sp: 4, s: -35, d: -31, est: 24, desc: "从编辑器发起请求，经网关到推理服务，把结果写回文档。" },
    { id: 44, t: "流式输出（SSE）接入", ty: :story, st: :closed, who: :frank, par: 42, sp: 4, s: -33, d: -28, est: 20, desc: "生成结果按增量推送到前端，首字出现后不再等整段完成。" },
    { id: 45, t: "搭建推理服务与模型网关", ty: :task, st: :closed, who: :bob, par: 43, sp: 4, s: -35, d: -32, est: 16, desc: "部署推理服务，网关统一鉴权、限流和日志。" },
    { id: 46, t: "前端编辑器接入流式渲染", ty: :task, st: :closed, who: :fiona, par: 43, sp: 4, s: -33, d: -31, est: 12, desc: "编辑器按增量片段渲染，保持光标和撤销栈不乱。" },
    { id: 47, t: "长文本生成中途断流且无重连", ty: :bug, st: :closed, who: :bob, par: 43, sp: 4, s: -28, d: -27, est: 6, prio: :high, desc: "生成超过两分钟时连接被网关切断，前端没有任何提示也不会重连。" },
    { id: 48, t: "多轮上下文压缩", ty: :story, st: :closed, who: :mia, par: 42, sp: 5, s: -21, d: -15, est: 16, desc: "对话变长后，把早期内容压缩成摘要，保证上下文不超限。" },
    { id: 49, t: "首字延迟优化至 800ms 内", ty: :story, st: :closed, who: :mia, par: 42, sp: 5, s: -17, d: -12, est: 12, desc: "把首字延迟的 P95 压到 800 毫秒以内。" },
    { id: 50, t: "引入 KV 缓存与前缀复用", ty: :task, st: :closed, who: :mia, par: 48, sp: 5, s: -19, d: -15, est: 10, desc: "相同前缀的请求复用缓存，减少重复计算。" },
    { id: 51, t: "上下文窗口动态裁剪策略", ty: :task, st: :closed, who: :bob, par: 48, sp: 5, s: -18, d: -14, est: 8, desc: "按重要性裁剪上下文，而不是简单截断开头。" },
    { id: 52, t: "语气与风格指令（改写/扩写/精简）", ty: :story, st: :closed, who: :fiona, par: 42, sp: 5, s: -21, d: -14, est: 14, desc: "用户选中文字后，可以按指定语气改写、扩写或精简。" },
    { id: 53, t: "风格指令模板与预设管理", ty: :task, st: :closed, who: :fiona, par: 52, sp: 5, s: -17, d: -13, est: 8, desc: "团队可以保存常用的风格指令，成员一键套用。" },
    { id: 54, t: "对话历史与会话管理", ty: :story, st: :testing, who: :fiona, par: 42, sp: 6, s: -7, d: 1, est: 18, rem: 4, desc: "对话按会话保存，可以重命名、归档和回看。" },
    { id: 55, t: "模型路由与降级策略", ty: :story, st: :doing, who: :bob, par: 42, sp: 6, s: -7, d: 4, est: 20, rem: 12, prio: :high, desc: "按成本和延迟选择模型，主模型不可用时自动降级到备用模型。" },
    { id: 56, t: "长文分段续写", ty: :story, st: :planned, who: :ben, par: 42, sp: 7, s: 7, d: 11, est: 16, rem: 16, desc: "超长文档分段续写，段与段之间保持语气和人称一致。" },
    { id: 86, t: "对话历史按项目归档与搜索", ty: :task, st: :testing, who: :fiona, par: 54, sp: 6, s: -5, d: 0, est: 8, rem: 2, desc: "会话按项目归档，支持按关键字搜索历史对话。" },
    { id: 87, t: "会话标题自动生成", ty: :task, st: :planned, who: :fiona, par: 54, sp: 6, s: 1, d: 3, est: 6, rem: 6, desc: "新会话根据第一轮内容自动生成标题，可手动修改。" },
    { id: 89, t: "模型网关限流策略", ty: :task, st: :doing, who: :bob, par: 42, sp: 6, s: -5, d: 2, est: 10, rem: 6, prio: :high, desc: "按套餐等级限制每分钟请求数，超限时返回明确的错误码。" },
    { id: 90, t: "降级到备用模型时的提示文案", ty: :task, st: :planned, who: :fiona, par: 42, sp: 7, s: 7, d: 8, est: 4, rem: 4, desc: "自动降级后，在编辑器里用一句话告诉用户发生了什么。" },
    { id: 91, t: "长文续写的章节衔接断裂", ty: :bug, st: :confirmed, par: 56, sp: 7, est: 8, prio: :high, desc: "续写到第三段之后，章节之间的过渡会突然换了人称。" },
    { id: 92, t: "续写时保留作者语气", ty: :task, st: :backlog, who: :ben, par: 56, est: 12, desc: "续写前先读取作者已有段落的语气特征，续写时沿用。" },

    { id: 57, t: "RAG 知识库", ty: :epic, st: :doing, who: :ada, born: -80, desc: "让用户上传自己的资料，生成时能引用、能溯源、不胡编。" },
    { id: 58, t: "文档上传与解析（PDF/DOCX/MD）", ty: :story, st: :closed, who: :ben, par: 57, sp: 4, s: -35, d: -31, est: 24, desc: "支持上传三种常见格式并解析出正文、标题层级和表格。" },
    { id: 59, t: "段落级切片与向量化入库", ty: :story, st: :closed, who: :mia, par: 57, sp: 4, s: -33, d: -28, est: 20, desc: "解析后的正文按段落切片，向量化后写入向量库。" },
    { id: 60, t: "切片策略调优（按标题/长度双策略）", ty: :task, st: :closed, who: :mia, par: 59, sp: 5, s: -21, d: -17, est: 10, desc: "有标题层级时按标题切，否则按长度切，对比两种策略的召回。" },
    { id: 61, t: "向量库选型与部署", ty: :task, st: :closed, who: :ben, par: 59, sp: 4, s: -35, d: -33, est: 12, desc: "比较几种向量库的运维成本和检索性能，选定并部署。" },
    { id: 62, t: "扫描版 PDF 解析为空", ty: :bug, st: :closed, who: :ben, par: 57, sp: 5, s: -21, d: -19, est: 6, prio: :high, desc: "没有文本层的扫描件解析结果为空，界面也没有任何提示。" },
    { id: 63, t: "召回质量评估集与离线评测", ty: :story, st: :closed, who: :frank, par: 57, sp: 5, s: -21, d: -15, est: 14, desc: "整理一批真实问题和标准答案，用来离线评测召回质量。" },
    { id: 64, t: "引用溯源：论断可点击回原文", ty: :story, st: :closed, who: :frank, par: 57, sp: 5, s: -18, d: -12, est: 18, desc: "生成内容里的每个论断都能点开，跳回原文位置。" },
    { id: 65, t: "幻觉拦截：无依据内容降级提示", ty: :story, st: :closed, who: :mia, par: 57, sp: 5, s: -17, d: -11, est: 16, desc: "检索不到依据时不硬编，直接告诉用户没有找到依据。" },
    { id: 66, t: "溯源高亮与原文定位交互", ty: :task, st: :closed, who: :fiona, par: 64, sp: 5, s: -14, d: -11, est: 8, desc: "点击引用后在原文里高亮对应段落并滚动到位置。" },
    { id: 67, t: "基于检索分数的置信度阈值", ty: :task, st: :closed, who: :mia, par: 65, sp: 5, s: -14, d: -12, est: 6, desc: "检索分数低于阈值时，不生成内容，改为提示没有依据。" },
    { id: 68, t: "跨文档同名章节溯源跳错位置", ty: :bug, st: :testing, who: :quinn, par: 57, sp: 6, s: -8, d: 1, est: 6, rem: 2, prio: :high, desc: "两篇文档有同名章节时，点击引用会跳到另一篇文档的同名章节。" },
    { id: 69, t: "知识库权限与共享范围", ty: :story, st: :doing, who: :ben, par: 57, ver: 22, sp: 6, s: -10, d: 4, d0: -3, est: 30, rem: 16, prio: :high, desc: "知识库和文档两级权限，团队内可以按成员或角色共享。" },
    { id: 70, t: "增量更新：文档改动自动重建索引", ty: :story, st: :planned, who: :bob, par: 57, ver: 22, sp: 7, s: 7, d: 11, est: 20, rem: 20, desc: "文档被修改后，只重建改动部分的索引，不再整库重建。" },
    { id: 71, t: "多知识库与项目级隔离", ty: :story, st: :clear, who: :ada, par: 57, ver: 22, est: 24, desc: "一个团队可以有多个知识库，不同项目之间互相看不到。" },
    { id: 93, t: "PDF 表格内容提取错乱", ty: :bug, st: :confirmed, par: 57, sp: 7, est: 8, prio: :high, desc: "带跨页表格的 PDF 提取后，行列顺序被打乱。" },
    { id: 94, t: "DOCX 合并单元格解析丢失", ty: :bug, st: :doing, who: :ben, par: 57, sp: 6, s: -10, d: 2, est: 6, rem: 4, prio: :high, desc: "DOCX 里的合并单元格解析后内容丢失，只剩第一格。" },
    { id: 95, t: "权限变更后检索缓存失效", ty: :task, st: :backlog, par: 57, sp: 7, ver: 22, est: 8, desc: "成员权限变化后，要立刻让该成员的检索缓存失效。" },
    { id: 96, t: "知识库共享链接过期策略", ty: :task, st: :new, who: :fiona, par: 57, ver: 22, desc: "共享链接要支持设置有效期，到期后自动失效。" },
    { id: 97, t: "增量索引任务失败重试", ty: :task, st: :planned, who: :bob, par: 70, ver: 22, sp: 7, s: 9, d: 11, est: 8, rem: 8, desc: "增量索引失败时按退避策略重试，超过次数后通知负责人。" },
    { id: 98, t: "召回评测集补充中文长文样本", ty: :task, st: :planned, who: :quinn, par: 57, sp: 7, s: 7, d: 11, est: 12, rem: 12, desc: "评测集里的中文长文样本太少，需要补充论文、产品文档和会议纪要三类。" },
    { id: 99, t: "扫描件解析回归用例", ty: :task, st: :planned, who: :quinn, par: 57, sp: 6, s: 1, d: 3, est: 8, rem: 8, desc: "给扫描件解析补一组回归用例，覆盖无文本层、倾斜和混合页。" },
    { id: 88, t: "对外接口文档（OpenAPI）", ty: :task, st: :doing, who: :ben, par: 57, sp: 6, s: -10, d: 3, d0: 4, est: 10, rem: 8, desc: "整理对外开放的接口，用 OpenAPI 描述请求、响应和错误码。" },
    { id: 121, t: "技术债：升级向量库客户端", ty: :task, st: :onhold, who: :bob, par: 57, est: 6, desc: "向量库客户端有新版本，升级需要回归所有检索用例，先搁置。" },

    { id: 72, t: "商业化", ty: :epic, st: :doing, who: :ada, born: -80, desc: "用量计费、套餐升级和配额告警，形成完整的商业化闭环。" },
    { id: 73, t: "用量统计与配额扣减", ty: :story, st: :doing, who: :bob, par: 72, ver: 21, sp: 6, s: -12, d: 2, d0: -10, est: 24, rem: 10, prio: :high, desc: "统计每个账号的调用量，并按套餐配额实时扣减。" },
    { id: 74, t: "套餐与升级流程", ty: :story, st: :testing, who: :fiona, par: 72, ver: 21, sp: 6, s: -7, d: 1, est: 20, rem: 4, desc: "用户可以查看套餐差异，并在线完成升级。" },
    { id: 75, t: "计费事件流水与对账口径", ty: :task, st: :doing, who: :quinn, par: 72, ver: 21, sp: 6, s: 2, d: 4, est: 16, rem: 12, prio: :high, desc: "把每次扣减记成计费事件流水，并和财务确认对账口径。" },
    { id: 76, t: "配额告警与降级提示 UI", ty: :task, st: :planned, who: :fiona, par: 72, ver: 21, sp: 7, s: 7, d: 10, est: 10, rem: 10, desc: "配额用到 80% 和 100% 时在界面上提示，并说明降级后的限制。" },
    { id: 77, t: "发票与账单历史", ty: :story, st: :planned, who: :bob, par: 72, ver: 21, sp: 7, s: 7, d: 11, est: 16, rem: 16, desc: "用户可以查看历史账单并下载发票。" },
    { id: 78, t: "团队席位与成员管理", ty: :story, st: :clear, who: :ada, par: 72, ver: 22, est: 24, desc: "团队管理员可以购买席位、邀请成员并管理角色。" },
    { id: 79, t: "试用到期后仍可无限调用", ty: :bug, st: :testing, who: :quinn, par: 72, ver: 21, sp: 6, s: -7, d: 1, est: 6, rem: 2, prio: :urgent, desc: "试用期结束后账号仍然可以继续调用，配额检查没有生效。" },
    { id: 100, t: "配额扣减并发超扣", ty: :bug, st: :doing, who: :bob, par: 73, ver: 21, sp: 6, s: -3, d: 1, est: 6, rem: 4, prio: :urgent, desc: "压测时并发请求会让同一个账号被超额扣减。" },
    { id: 101, t: "用量数据按天聚合报表", ty: :task, st: :backlog, par: 73, sp: 7, ver: 21, est: 8, desc: "财务需要按天汇总用量，导出成表格。" },
    { id: 102, t: "账单金额四舍五入口径", ty: :task, st: :closed, who: :bob, par: 72, ver: 21, sp: 5, s: -17, d: -15, est: 6, desc: "和财务确认金额的取整方式，实现并补充用例。" },
    { id: 103, t: "套餐降级后的权益回收", ty: :task, st: :planned, who: :fiona, par: 74, ver: 21, sp: 6, s: 1, d: 3, est: 8, rem: 8, desc: "用户降级套餐后，超出新套餐的权益在周期结束时回收。" },
    { id: 104, t: "支付回调幂等处理", ty: :task, st: :devdone, who: :bob, par: 74, ver: 21, sp: 6, s: -6, d: -1, est: 8, rem: 0, desc: "支付平台重复回调时，订单状态只变更一次。" },
    { id: 105, t: "发票抬头与税号校验", ty: :task, st: :backlog, par: 77, sp: 7, ver: 21, est: 6, desc: "填写发票抬头和税号时做格式校验，减少退票。" },
    { id: 106, t: "席位邀请邮件", ty: :task, st: :new, par: 78, ver: 22, desc: "管理员邀请成员后，成员会收到带加入链接的邮件。" },
    { id: 107, t: "角色与席位上限校验", ty: :task, st: :new, par: 78, ver: 22, desc: "邀请人数超过购买的席位时，给出明确提示。" },

    { id: 80, t: "协作与分享", ty: :epic, st: :confirmed, who: :ada, born: -60, desc: "多人协作编辑、评论和对外分享。" },
    { id: 81, t: "多人同时编辑同一文档", ty: :story, st: :doing, who: :fiona, par: 80, ver: 22, sp: 6, s: -12, d: -4, est: 40, rem: 14, prio: :high, desc: "多人同时编辑一篇文档时，光标可见、内容不丢、离线后能合并。" },
    { id: 82, t: "评论与提及", ty: :story, st: :doing, who: :fiona, par: 80, ver: 22, sp: 6, s: -7, d: 4, est: 20, rem: 14, desc: "在文档里选中文字发评论，用 @ 提及同事并通知对方。" },
    { id: 83, t: "导出 Word / PDF / Markdown", ty: :story, st: :clear, who: :ada, par: 80, ver: 22, est: 30, desc: "文档可以导出成三种常见格式，样式尽量保持一致。" },
    { id: 84, t: "公开分享链接与只读访问", ty: :story, st: :backlog, who: :ada, par: 80, ver: 22, est: 20, desc: "生成一条只读的分享链接，可以设置有效期和密码。" },
    { id: 85, t: "写作模板市场", ty: :story, st: :new, who: :ada, par: 80, prio: :low, desc: "团队可以发布和订阅写作模板。" },
    { id: 108, t: "协同编辑光标同步延迟", ty: :bug, st: :doing, who: :fiona, par: 81, ver: 22, sp: 6, s: -8, d: -3, est: 8, rem: 6, desc: "三人以上同时编辑时，别人的光标要隔一两秒才更新。" },
    { id: 109, t: "离线编辑后的冲突合并", ty: :task, st: :planned, who: :fiona, par: 81, ver: 22, sp: 7, s: 7, d: 11, est: 16, rem: 16, desc: "离线编辑的内容重新联网后，和线上版本自动合并，冲突时让用户选择。" },
    { id: 110, t: "评论中 @ 提及的通知", ty: :task, st: :doing, who: :fiona, par: 82, ver: 22, sp: 6, s: -4, d: 2, est: 8, rem: 6, desc: "被 @ 的人要在站内和邮件里收到通知，并能直接跳到评论位置。" },
    { id: 111, t: "评论线程折叠", ty: :task, st: :planned, par: 82, ver: 22, sp: 7, est: 4, desc: "评论回复较多时默认折叠，展开后保持阅读位置。" },
    { id: 112, t: "导出 PDF 的页码与封面", ty: :story, st: :clarifying, who: :ada, par: 80, ver: 22, sp: 6, s: 0, d: 4, est: 12, rem: 12, desc: "导出 PDF 时加页码；封面是否算页、页码放哪里，还需要产品确认。" },
    { id: 113, t: "导出 Markdown 保留表格", ty: :task, st: :new, who: :fiona, par: 83, ver: 22, desc: "导出 Markdown 时，表格要保留成标准的管道表格。" },
    { id: 114, t: "分享链接访问日志", ty: :task, st: :backlog, par: 84, ver: 22, est: 6, desc: "记录分享链接被谁在什么时候打开过。" },
    { id: 115, t: "模板市场的内容审核流程", ty: :task, st: :new, who: :ada, par: 85, prio: :low, s: 7, d: 9, est: 8, desc: "对外发布的模板需要先经过审核。" },

    { id: 116, t: "v1.1 发布前检查清单", ty: :task, st: :doing, who: :sam, ver: 21, sp: 6, s: -3, d: 9, est: 6, rem: 4, prio: :high, desc: "发布前要逐项确认的事：迁移脚本、配额开关、回滚方案和对外公告。" },
    { id: 117, t: "整理上月用户反馈", ty: :task, st: :closed, who: :sam, s: -11, d: -7, est: 4, desc: "把上月收到的反馈按主题归类，供迭代计划参考。" },
    { id: 118, t: "Quinn 入项准备（账号、仓库、文档）", ty: :task, st: :closed, who: :sam, s: -4, d: 0, est: 3, desc: "为新成员开通账号、仓库权限，并准备入职要读的文档。" },
    { id: 119, t: "里程碑：v1.1 发布", ty: :milestone, st: :planned, who: :sam, ver: 21, s: 11, d: 11, desc: "商业化版本对外发布。" },
    { id: 120, t: "里程碑：v2.0 Beta", ty: :milestone, st: :new, who: :sam, ver: 22, s: 39, d: 39, desc: "团队版进入内测。" }
  ].freeze

  RELATIONS = [
    [75, 73], [77, 75], [76, 74], [119, 77], [56, 55], [70, 69], [99, 62], [109, 108], [120, 109]
  ].freeze
end
