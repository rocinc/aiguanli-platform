<div align="center">

# AiGuanli · 爱管理

**A project management platform where the AI assistant works as a member of the team**

[简体中文](README.md) · **English**

</div>

---

AiGuanli is a complete project management platform. Work packages, sprints and backlogs, Gantt charts with dependencies, boards, the team planner, meetings, wikis, documents, forums, time and cost tracking, budgets and reports all run under one permission model. The AI assistant takes part like any other member: it can be assigned work, @-mentioned, and it shows up in the activity history. Every change it makes is signed, traceable and undoable.

## Contents

- [The AI assistant](#the-ai-assistant)
- [Tech stack](#tech-stack)
- [Getting started](#getting-started)
- [Demo data](#demo-data)
- [Connecting a language model](#connecting-a-language-model)
- [Tests](#tests)
- [Layout](#layout)
- [License](#license)

## The AI assistant

The assistant is a separate module (`modules/assistant`). It plugs into the platform only through the platform's hooks, event subscriptions and service interfaces, and leaves the business core untouched. Its guiding rule: the language model understands and phrases, and code decides anything that becomes a project fact.

| Capability | What it does |
|---|---|
| Reading commitments | Reads who promised what by when from comments, meetings and forums. Every reading carries a quote, and code checks that the quote really is a passage of the source. Relative dates are resolved against the platform's working calendar, sprints and versions |
| Preview before write | Every change is first run as the person concerned, inside a transaction that is always rolled back, to show which work packages it touches and whom it notifies |
| Tiers set by code | The preview decides the tier: T0 read-only; T1 done directly; T2 needs the person's confirmation; T3 irreversible, confirmed item by item. The model cannot lower its own tier |
| Signature and undo | Each change records in the activity history on whose behalf the assistant acted and why, and can be undone in one click. Undoing an older change is previewed first |
| Proactive notices | 55 detectors watch for critical-path slips, stalled promises, budgets running ahead, cascading reschedules, review backlogs and more. Candidates pass a value gate and a per-person daily interruption budget, then go out as an immediate notice, an entry in the daily brief, or a record kept for reference |
| Duties | 9 kinds of standing duties that can be delegated: weekly status, meeting follow-up, decision log, sprint carry-over, timesheet drafts, release watch, onboarding, advancing merged pull requests, and a devil's advocate |
| External agents | 21 reasoning tools are exposed over MCP as `assistant_*`. Writes from an outside coding agent go through the same preview and tiering as writes from the web interface, and are stored in the name of the person who granted access |
| Replaceable model | Works with any OpenAI-compatible Chat Completions endpoint. Without a model the platform and the demo data still work; the assistant simply stays silent |

## Tech stack

- Backend: Ruby 4.0.6, Rails 8.1, PostgreSQL 16, background jobs run by GoodJob in a separate process
- Frontend: server-rendered Hotwire (Turbo + Stimulus) pages with Angular 22 components, built on the Primer design system
- Features are split into 30 fairly independent engine modules; the assistant is one of them

## Getting started

You need Ruby 4.0.6, Node 24 with npm 11, and Docker for the local database.

```bash
git clone https://github.com/rocinc/aiguanli-platform.git && cd aiguanli-platform

# 1. Start the local database container (port 5433) and write config/database.yml if missing
./start-dev.sh db

# 2. Install dependencies and set up the database
bundle install
bin/rails db:create
bin/setup_dev          # migrates, installs frontend packages, exports frontend locales
bin/rails db:seed      # base data and the admin account

# 3. Start backend, frontend, the job worker and the memory watchdog
./start-dev.sh start
```

Open <http://localhost:3000> and sign in as `admin` / `admin`. You will be asked to change the password on first login.

Other `start-dev.sh` subcommands: `stop`, `status`, `logs`, `logs-angular`, `logs-worker`.

## Demo data

The repository ships a demo world for a fictional team building an AI writing platform, from kickoff to Sprint 7. It has 9 members (the AI assistant included), 7 sprints, 3 versions, about 185 work packages, more than 600 time entries, 28 meetings, over 30 wiki pages, and the promises, notices, actions and undos the assistant left along the way.

```bash
bin/demo-rebuild
```

This empties your local development database, restores the baseline from `modules/assistant/db/baseline/quill.dump`, runs migrations, generates the demo data and restarts the stack. It takes about three minutes and needs no language model.

All demo accounts use the password `Quill-Dev-2026!`. They are meant for local use only.

| Login | Role |
|---|---|
| `admin` | System administrator |
| `sam.sm` | Scrum Master / project admin |
| `ada.po` | Product owner |
| `bob.be`, `ben.be` | Backend |
| `frank.fe`, `fiona.fe` | Frontend |
| `mia.ml` | ML |
| `quinn.qa` | QA |

To regenerate the data without restoring the baseline:

```bash
ASSISTANT_SEED_DEMO=1 bin/rails assistant:seed_acceptance
```

## Connecting a language model

Copy `.env.example` to `.env` and fill in:

```bash
ASSISTANT_LLM_BASE_URL=https://your-endpoint/v1
ASSISTANT_LLM_API_KEY=...
ASSISTANT_LLM_MODEL=...
```

Then tick the data-use consent under **Administration › AI assistant**. The endpoint and model can also be changed on that page. The key is read from the environment only and never stored in the database. `.env` is excluded by `.gitignore`.

## Tests

```bash
RAILS_ENV=test bin/rails db:create db:migrate
bundle exec rspec modules/assistant/spec     # assistant module, 116 spec files
cd frontend && npm test                      # frontend unit tests
```

## Layout

```text
app/ lib/ config/ db/        platform core
frontend/                    Angular components and Stimulus controllers
modules/                     30 feature modules
modules/assistant/
  app/services/assistant/
    understanding/           reading intents, promises and dates
    facts/                   project facts computed by code
    reasoning/               conversational reasoning and tools
    actions/                 preview, tiering, execution and undo
    proactive/               detectors, value gate and delivery
    duties/                  delegable standing duties
  db/baseline/               demo baseline database
  db/acceptance_seed/        acceptance data
  db/demo_seed/              demo world
  spec/                      tests
docs/api/apiv3/              API specification (read at runtime and by tests)
start-dev.sh                 local stack start/stop
bin/demo-rebuild             rebuild the demo data in one step
```

## License

Released under the GNU General Public License version 3 (GPL-3.0). See [LICENSE](LICENSE) and [COPYRIGHT](COPYRIGHT).
