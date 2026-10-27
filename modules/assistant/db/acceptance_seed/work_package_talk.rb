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

module AssistantSeed
  # [day offset, "HH:MM", who, text, attribute changes made in the same journal]
  REASSIGNED_TODAY = { 75 => :ben, 79 => :bob, 68 => :fiona, 98 => :frank, 99 => :ben }.freeze

  WORK_PACKAGE_TALK = {
    43 => [[-35, "16:30", :frank, "主链路已经打通，从编辑器到推理服务一次请求能返回完整结果。"]],
    47 => [[-27, "11:20", :bob, "原因是网关的空闲超时设成了 120 秒，已调大并加了心跳。前端重连另开一条处理。"]],
    49 => [[-13, "15:40", :mia, "P95 降到 760 毫秒，主要收益来自前缀缓存。"]],
    55 => [[-6, "14:10", :bob, "路由先按成本、再按延迟排序，压测里成本差 3 倍而延迟只差 80 毫秒；备用模型只在主模型连续两次超时后才启用。@Ada Nakamura 你确认一下这个顺序。"],
           [-5, "10:05", :ada, "同意，成本优先。降级时要让用户知道，文案找 Fiona 对一下。"]],
    62 => [[-19, "17:15", :ben, "没有文本层的 PDF 先在界面上提示“未识别到文字”，OCR 放到 v2.0 再做。"]],
    64 => [[-12, "16:20", :frank, "引用现在可以点回原文，同名章节的情况还有问题，单独提了缺陷。"]],
    54 => [[-5, "11:30", :fiona, "会话重命名和归档都已提测，请重点看归档后的搜索。"]],
    68 => [[-7, "15:00", :fiona, "两篇文档有同名章节时会跳错，已经复现。"],
           [-6, "11:00", :fiona, "我改成用段落指纹来定位，不再依赖标题是否唯一；测试里 12 组同名章节都能定位对。"],
           [-5, "10:00", :ada, "跨文档的跳转要不要在新标签页打开？现在是当前页内跳转。"],
           [-3, "17:00", :fiona, "已修复并提测，同名章节和跨文档两种情况都覆盖了。"],
           [0, "08:42", :sam, "转给 Quinn 做回归测试，背景在上面几条里。", { who: :quinn }]],
    69 => [[-12, "10:00", :ben, "权限分两层：知识库级和文档级，上个迭代 12 个共享场景里这两层覆盖了 11 个。"],
           [-10, "17:00", :ben, "休假回来后，周三前我把权限接口联调好，Fiona 你那边就可以接了。"],
           [-6, "10:20", :fiona, "@Ben Iversen 文档级权限和知识库级权限冲突时，以哪一级为准？我这边的界面要按这个来。"],
           [-5, "15:10", :sam, "周中同步会上定了：权限只做知识库级和文档级两层，范围收窄，截止日顺延到本迭代末。", { due: 4 }]],
    75 => [[-12, "10:10", :ben, "对账口径我先按 token 折算来做，财务给的 3 笔样本都对得上，周内给结论。"],
           [-6, "10:15", :sam, "@Ben Iversen 退款发生时，对账流水要不要冲回？财务周三要对口径，这条等你回来确认。"],
           [-5, "09:50", :bob, "我这边的扣减事件已经按 token 折算落库，格式见 #73。"],
           [0, "08:40", :sam, "Ben 刚休假回来，这条先交给 Quinn 接手；Ben 有空时把背景讲一下。", { who: :quinn }]],
    73 => [[-11, "11:30", :sam, "这条是 v1.1 的主线，计费后面三件事都排在它后面，有风险请早点说。"],
           [-10, "15:00", :bob, "对账口径还没跟财务确认完，联调推到下周四。", { due: -4 }],
           [-4, "17:10", :bob, "并发超扣占了两天，先修 #100，这条顺延到下周三。", { due: 2 }],
           [-3, "10:20", :sam, "收到。#77 和 v1.1 的发布都排在它后面，这周三之前请务必合进去。"]],
    74 => [[-5, "16:00", :fiona, "升级流程已经提测，请重点测降级之后的权益变化。"]],
    79 => [[-10, "14:00", :sam, "试用到期后账号仍然能无限调用，星河教育今天反馈了。"],
           [-7, "10:30", :bob, "原因是结算任务重置了试用期的 quota 字段，今天修。"],
           [-7, "16:40", :bob, "补丁已合并，等测试确认。"],
           [-5, "11:00", :sam, "补丁要不要回灌到已经过期的老账号？"],
           [-5, "11:30", :bob, "不用，老账号走一次性脚本修正，我在 #100 里一起处理。"],
           [0, "08:41", :sam, "Quinn 接手验证：试用到期、续费、降级三个场景各测一遍。", { who: :quinn }]],
    88 => [[-10, "16:40", :ben, "休假回来后，周四前我能给出接口文档。", { due: 3 }],
           [-5, "10:00", :fiona, "接口文档里请补上限流返回码和分页参数。"]],
    89 => [[-4, "14:30", :bob, "限流阈值先按套餐分级，在网关侧实现。"]],
    94 => [[-11, "15:30", :ben, "已经定位到合并单元格丢失的位置，修复在 PR #412。"],
           [-4, "17:20", :bob, "PR #412 已经合并。Ben 回来后记得更新这条的状态。"]],
    98 => [[-12, "10:00", :frank, "评测集里的中文长文样本太少，我先整理 50 篇。"],
           [-10, "17:30", :frank, "整理到 32 篇，还差 18 篇，下周继续。"],
           [-7, "09:30", :ada, "长文样本请覆盖论文、产品文档和会议纪要三类。"],
           [0, "08:43", :sam, "Frank 借调到数据平台组，这条交给 Quinn；已整理的 32 篇放在共享目录里。", { who: :quinn }]],
    99 => [[-10, "11:00", :ada, "扫描件先加界面提示，OCR 放到 v2.0 再做。"],
           [-10, "15:20", :ben, "回归用例先写了 6 条，覆盖无文本层、倾斜和混合页。"],
           [-6, "10:00", :fiona, "界面提示的文案我写在 #62 的评论里了，测试时一并看一下。"],
           [0, "08:44", :sam, "Ben 这周才回来，先交给 Quinn；用例在上面，不够的再补。", { who: :quinn }]],
    100 => [[-3, "15:20", :bob, "压测发现并发扣减会超扣，加行级锁修复，先按紧急处理。"]],
    102 => [[-17, "11:10", :bob, "金额按 token 折算后四舍五入到分，已经和财务核对过 20 笔样本。"]],
    104 => [[-3, "17:40", :bob, "回调幂等已经实现，等测试排期。"]],
    81 => [[-10, "10:00", :fiona, "光标同步和离线合并要一起做，原来的估算偏少。"],
           [-4, "17:30", :fiona, "离线合并还没做完，周五来不及了，这周内补完。"]],
    108 => [[-6, "14:00", :fiona, "三人同时编辑时光标延迟明显，先查是不是广播太频繁。"]],
    110 => [[-4, "11:20", :fiona, "@Sam Okafor 评论通知的文案和交互，周三前能帮我确认一下吗？前端周三要开始接。"],
            [-3, "09:40", :ada, "文案我这边没意见，交互请 Sam 定。"],
            [-3, "16:10", :fiona, "站内通知已经做完，邮件通知明天接上。"]],
    112 => [[-6, "15:30", :ada, "页码放页脚居中，封面不算页。@Fiona Walsh 你觉得呢？"]],
    116 => [[-3, "16:00", :sam, "检查清单先列出来，周三前补全。"]],
    118 => [[-4, "10:00", :sam, "Quinn 周一入项，账号和仓库权限今天开好。"],
            [0, "08:20", :sam, "账号、仓库权限和入职文档都已开好。"]],
    121 => [[-10, "11:00", :bob, "向量库客户端升级要回归所有检索用例，先搁置，v2.0 之后再看。"]]
  }.freeze
end
