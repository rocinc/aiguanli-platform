<div align="center">

# 爱管理

**一个让 AI 助理以团队成员身份工作的项目管理平台**

**简体中文** · [English](README.en.md)

</div>

---

爱管理是一个完整的项目管理平台。工作包、迭代与待办、甘特图与依赖、看板、团队计划器、会议、维基、文档、论坛、工时与成本、预算和报表都在同一套权限模型下运行。平台中的 AI 助理和其他成员一样，可以被指派任务、被 @ 到，也会出现在活动记录里。它所做的每一处改动都署名，可以追溯，也可以撤销。

## 目录

- [AI 助理](#ai-助理)
- [技术栈](#技术栈)
- [快速开始](#快速开始)
- [演示数据](#演示数据)
- [接入语言模型](#接入语言模型)
- [测试](#测试)
- [目录结构](#目录结构)
- [许可证](#许可证)

## AI 助理

助理作为独立模块（`modules/assistant`）接入平台，只通过平台提供的钩子、事件订阅和服务接口工作，不改动业务内核。它的设计原则是：语言模型负责理解和措辞，凡是要写成项目事实的内容一律由代码裁定。

| 能力 | 说明 |
|---|---|
| 读出承诺 | 从评论、会议和论坛里读出谁答应了什么、什么时候完成。每条读出都附原文引用，并由代码核对它确实是原文中的一段。相对日期按平台的工作日历、迭代和版本换算 |
| 写入前预演 | 任何改动都先以当事人的身份放进一个最终会回滚的事务里试运行，列出会牵动哪些工作包、会通知到哪些人 |
| 分级由代码判定 | 预演结果决定改动的等级：T0 只读；T1 直接执行；T2 须当事人确认；T3 不可逆，须逐项确认。模型不能给自己降级 |
| 署名与撤销 | 每次改动都在活动记录中注明由助理代谁执行、依据是什么，支持一键撤销；超过时限的撤销先预演再执行 |
| 主动提示 | 55 个探测器持续检查关键路径滑移、承诺停滞、预算超前、改期连锁、评审积压等信号。候选提示先过价值筛选，再按每人每日的打断上限分流：立即提醒、进入每日简报，或留存备查 |
| 职责 | 9 类可委派的常驻职责，包括周报、会议跟进、决策记录、迭代结转、工时草稿、发布观察、新人引导、合并后推进和反方意见 |
| 外部智能体 | 21 个推理工具以 `assistant_*` 的名义通过 MCP 对外开放。外部代码助手的写入和页面上的写入走同一条预演与分级路径，并以授权者本人的名义落库 |
| 模型可替换 | 可接任何兼容 OpenAI Chat Completions 的端点。不配置模型时，平台和演示数据照常可用，助理只是不开口 |

## 技术栈

- 后端：Ruby 4.0.6、Rails 8.1、PostgreSQL 16，后台作业由 GoodJob 在独立进程中执行
- 前端：服务端渲染的 Hotwire（Turbo + Stimulus）页面配合 Angular 22 组件，界面基于 Primer 设计体系
- 功能划分为 30 个相对独立的引擎模块，助理是其中之一

## 快速开始

需要先装好 Ruby 4.0.6、Node 24 与 npm 11，以及 Docker（用于本地数据库）。

```bash
git clone https://github.com/rocinc/aiguanli-platform.git && cd aiguanli-platform

# 1. 启动本地数据库容器（本机 5433 端口），并按需生成 config/database.yml
./start-dev.sh db

# 2. 安装依赖并初始化数据库
bundle install
bin/rails db:create
bin/setup_dev          # 迁移数据库、安装前端依赖、导出前端语言包
bin/rails db:seed      # 写入基础数据和管理员账号

# 3. 启动后端、前端、后台作业与内存看门狗
./start-dev.sh start
```

打开 <http://localhost:3000>，用 `admin` / `admin` 登录，首次登录需要修改密码。

`start-dev.sh` 的其他子命令：`stop`、`status`、`logs`、`logs-angular`、`logs-worker`。

## 演示数据

仓库带有一套虚构团队的演示世界。场景是一个智能写作平台项目，从立项到第 7 个 Sprint：9 名成员（含 AI 助理）、7 个 Sprint、3 个版本、约 185 个工作包、600 余条工时、28 场会议、30 余页维基，以及助理在其中留下的承诺、提示、动作和撤销记录。

```bash
bin/demo-rebuild
```

这条命令会清空本地的开发库，从 `modules/assistant/db/baseline/quill.dump` 还原基线，执行迁移，生成演示数据，然后重启开发栈，全程约三分钟。生成过程不需要语言模型。

演示账号的密码统一为 `Quill-Dev-2026!`，仅限本地使用：

| 账号 | 角色 |
|---|---|
| `admin` | 系统管理员 |
| `sam.sm` | Scrum Master / 项目管理员 |
| `ada.po` | 产品负责人 |
| `bob.be`、`ben.be` | 后端 |
| `frank.fe`、`fiona.fe` | 前端 |
| `mia.ml` | 算法 |
| `quinn.qa` | 测试 |

只想重跑数据、不还原基线时，可以直接执行：

```bash
ASSISTANT_SEED_DEMO=1 bin/rails assistant:seed_acceptance
```

## 接入语言模型

把 `.env.example` 复制为 `.env`，填写以下三项：

```bash
ASSISTANT_LLM_BASE_URL=https://your-endpoint/v1
ASSISTANT_LLM_API_KEY=...
ASSISTANT_LLM_MODEL=...
```

然后在 **管理 › AI 助理** 中勾选数据使用同意。端点地址和模型名也可以在这个页面修改；密钥只从环境变量读取，不会写入数据库。`.env` 已被 `.gitignore` 排除。

## 测试

```bash
RAILS_ENV=test bin/rails db:create db:migrate
bundle exec rspec modules/assistant/spec     # 助理模块，116 个规格文件
cd frontend && npm test                      # 前端单元测试
```

## 目录结构

```text
app/ lib/ config/ db/        平台核心
frontend/                    Angular 组件与 Stimulus 控制器
modules/                     30 个功能模块
modules/assistant/
  app/services/assistant/
    understanding/           读出意图、承诺与日期
    facts/                   由代码计算的项目事实
    reasoning/               对话推理与工具
    actions/                 预演、分级、执行与撤销
    proactive/               探测器、价值筛选与投递
    duties/                  可委派的常驻职责
  db/baseline/               演示基线库
  db/acceptance_seed/        验收数据
  db/demo_seed/              演示世界
  spec/                      测试
docs/api/apiv3/              接口规范（运行期与测试会读取）
start-dev.sh                 本地开发栈启停
bin/demo-rebuild             一键重建演示数据
```

## 许可证

本项目以 GNU 通用公共许可证第 3 版（GPL-3.0）发布，详见 [LICENSE](LICENSE) 与 [COPYRIGHT](COPYRIGHT)。
