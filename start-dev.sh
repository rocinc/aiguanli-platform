#!/usr/bin/env bash
# 爱管理 开发环境启停脚本（重启后可直接恢复）
# 用法: ./start-dev.sh [start|stop|status|db|logs|logs-angular|logs-worker]
#
# 组成:
#   - PostgreSQL : Docker 容器 op-postgres (本机 5433 端口, 数据卷 op_pgdata)
#   - Rails/Puma : 0.0.0.0:3000  (后端 API + 页面)
#   - Angular    : 127.0.0.1:4200 (前端资源, Rails 页面引用它)
#   - GoodJob    : bundle exec good_job start (后台作业)
#                  config/application.rb 里 execution_mode = :external, 所以它必须独立进程,
#                  不随 Puma 起。缺了它: 通知/日志/附件全文索引全部静默积压。
#
# Ruby 4.0.6 优先取 ~/.rubies/4.0.6，否则用 PATH 中的 ruby；Node 24 有 nvm 时由 nvm 切换。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$(basename "$ROOT")"  # Puma 进程标题里带的目录名，用来认出本项目的进程
export PATH="$HOME/.rubies/4.0.6/bin:$PATH"
# 录屏与演示时不要顶部“development”水印
export OPENPROJECT_DEVELOPMENT_HIGHLIGHT_ENABLED="${OPENPROJECT_DEVELOPMENT_HIGHLIGHT_ENABLED:-false}"
NVM_DIR="$HOME/.nvm"

wait_port() {  # wait_port <port> <秒> <名称>
  local port=$1 timeout=$2 name=$3 i=0
  while [ $i -lt "$timeout" ]; do
    if curl -sI --max-time 2 "http://127.0.0.1:${port}/" >/dev/null 2>&1; then
      echo "✓ ${name} 就绪 (${port})"; return 0
    fi
    sleep 2; i=$((i+2))
  done
  echo "⚠ ${name} 在 ${timeout}s 内未就绪，请看日志"; return 1
}

# 本地 config/database.yml 不入库；缺失时按上面的数据库容器写一份，已有则不动。
ensure_database_yml() {
  local f="$ROOT/config/database.yml"
  [ -f "$f" ] && return 0
  cat > "$f" <<'YML'
default: &default
  adapter: postgresql
  encoding: unicode
  host: 127.0.0.1
  port: 5433
  username: openproject
  password: openproject
  pool: 100

development:
  <<: *default
  database: openproject_development

test:
  <<: *default
  database: openproject_test<%= ENV['TEST_ENV_NUMBER'] %>
YML
  echo "✓ 已生成 config/database.yml（指向 5433 端口的本地数据库容器）"
}

start_db() {
  local state
  state=$(docker ps -a --filter name=^op-postgres$ --format '{{.State}}' 2>/dev/null)
  case "$state" in
    running) echo "✓ PostgreSQL 已在运行 (5433)"; return 0 ;;
    exited|created|paused)
      echo "→ 启动已存在的 PostgreSQL 容器..."
      docker start op-postgres >/dev/null && echo "✓ PostgreSQL 已启动 (5433)"
      docker update --restart unless-stopped op-postgres >/dev/null 2>&1 ;;
    "")
      # 优先用带 pgvector 的钉死镜像（语义检索需要）；本地没有则优雅回退到官方镜像。
      # 镜像 tag 钉死到「pgvector 版本 + PG 大版本 + Debian 代号」三段，避免浮动标签漂移。
      local img="${OPENPROJECT_DEV_PG_IMAGE:-pgvector/pgvector:0.8.6-pg16-trixie}"
      if ! docker image inspect "$img" >/dev/null 2>&1; then
        echo "⚠ 本地缺少 $img —— 回退到 postgres:16（语义检索将不可用）"
        echo "  需要时执行: docker pull $img"
        img="postgres:16"
      fi
      echo "→ 容器不存在，按原配置重建（复用数据卷 op_pgdata，镜像 $img）..."
      docker run -d --name op-postgres \
        -e POSTGRES_USER=openproject -e POSTGRES_PASSWORD=openproject -e POSTGRES_DB=openproject \
        -p 5433:5432 -v op_pgdata:/var/lib/postgresql/data \
        --restart unless-stopped "$img" >/dev/null && echo "✓ PostgreSQL 已重建并启动 ($img)"
      sleep 10 ;;
    *) echo "⚠ 未知容器状态: $state" ;;
  esac
}

# 开发模式每次代码重载都会留下约 60–80 MB 无法回收的内存，而智能体高频改文件会不断触发重载。
# 所以 GoodJob 线程数降到 5、用 jemalloc，并由看门狗按内存上限回收进程。
JEMALLOC=$(ls /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 2>/dev/null)
GOOD_JOB_MAX_MB=${GOOD_JOB_MAX_MB:-2000}
PUMA_WORKER_MAX_MB=${PUMA_WORKER_MAX_MB:-2000}

start_good_job() {
  if pgrep -f '[b]in/good_job start' >/dev/null; then
    echo "✓ GoodJob 已在运行"
  else
    echo "→ 启动 GoodJob worker..."
    ( cd "$ROOT" && LD_PRELOAD="$JEMALLOC" OPENPROJECT_GOOD__JOB__MAX__THREADS=5 \
        nohup bundle exec good_job start >> /tmp/good_job.log 2>&1 & )
  fi
}

# 每 60 秒检查一次：GoodJob 超限就停掉重启（作业由数据库锁保证不丢）；
# Puma worker 超限就发 TERM，由 cluster master 重新拉起。
watchdog() {
  while sleep 60; do
    local pid rss
    pid=$(pgrep -f '[b]in/good_job start' | head -1)
    if [ -n "$pid" ]; then
      rss=$(( $(ps -o rss= -p "$pid" 2>/dev/null || echo 0) / 1024 ))
      if [ "$rss" -gt "$GOOD_JOB_MAX_MB" ]; then
        echo "$(date '+%F %T') GoodJob ${rss}MB > ${GOOD_JOB_MAX_MB}MB，重启"
        kill -TERM "$pid"; sleep 20; kill -KILL "$pid" 2>/dev/null
        start_good_job
      fi
    fi
    for pid in $(pgrep -f "puma: cluster worker.*${APP}"); do
      rss=$(( $(ps -o rss= -p "$pid" 2>/dev/null || echo 0) / 1024 ))
      if [ "$rss" -gt "$PUMA_WORKER_MAX_MB" ]; then
        echo "$(date '+%F %T') Puma worker $pid ${rss}MB > ${PUMA_WORKER_MAX_MB}MB，回收"
        kill -TERM "$pid"
      fi
    done
  done
}

start_watchdog() {
  if pgrep -f '[s]tart-dev.sh watchdog' >/dev/null; then
    echo "✓ 内存看门狗已在运行"
  else
    ( setsid nohup "$ROOT/start-dev.sh" watchdog >> /tmp/dev_watchdog.log 2>&1 & )
    echo "✓ 内存看门狗已启动 (GoodJob ≤ ${GOOD_JOB_MAX_MB}MB, Puma worker ≤ ${PUMA_WORKER_MAX_MB}MB)"
  fi
}

start() {
  ensure_database_yml
  start_db

  if pgrep -f "puma.*${APP}" >/dev/null; then
    echo "✓ Rails 已在运行 (3000)"
  else
    echo "→ 启动 Rails..."
    ( cd "$ROOT" && nohup bundle exec rails server -b 0.0.0.0 -p 3000 > /tmp/rails_server.log 2>&1 & )
  fi

  start_good_job
  start_watchdog

  if pgrep -f 'ng serve' >/dev/null; then
    echo "✓ Angular 已在运行 (4200)"
  else
    echo "→ 启动 Angular (首次编译约 1-2 分钟)..."
    ( cd "$ROOT/frontend" \
      && { [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" && nvm use 24 >/dev/null 2>&1; true; } \
      && nohup npm run serve > /tmp/angular.log 2>&1 & )
  fi

  echo
  wait_port 3000 120 "Rails"
  wait_port 4200 240 "Angular"
  echo
  echo "════════════════════════════════════════"
  echo "  打开:  http://localhost:3000"
  echo "  账号:  admin / admin（全新库，首次登录需改密码）；演示库账号见 README"
  echo "════════════════════════════════════════"
}

stop() {
  pkill -f '[s]tart-dev.sh watchdog' 2>/dev/null && echo "✓ 看门狗已停"
  pkill -f "puma.*${APP}" 2>/dev/null && echo "✓ Rails 已停" || echo "· Rails 未运行"
  pkill -f 'ng serve' 2>/dev/null && echo "✓ Angular 已停" || echo "· Angular 未运行"
  pkill -f '[b]in/good_job start' 2>/dev/null && echo "✓ GoodJob 已停" || echo "· GoodJob 未运行"
  # pkill only signals; start() checks pgrep, so wait until the processes are really gone
  local i=0
  while pgrep -f "[b]in/good_job start|puma.*${APP}" >/dev/null && [ $i -lt 30 ]; do sleep 1; i=$((i+1)); done
  echo "  (数据库容器保持运行；如需停止: docker stop op-postgres)"
}

status() {
  echo "=== PostgreSQL ==="
  docker ps -a --filter name=^op-postgres$ --format '{{.Names}} | {{.Status}}' || echo "未找到容器"
  echo "=== Rails (3000) ==="
  pgrep -f "puma.*${APP}" >/dev/null && echo "进程: 运行中" || echo "进程: 未运行"
  curl -sI --max-time 5 http://127.0.0.1:3000/login 2>/dev/null | head -1 || echo "端口无响应"
  echo "=== Angular (4200) ==="
  pgrep -f 'ng serve' >/dev/null && echo "进程: 运行中" || echo "进程: 未运行"
  curl -sI --max-time 5 http://localhost:4200/assets/frontend/main.js 2>/dev/null | head -1 || echo "端口无响应"
  echo "=== 内存 (MB) ==="
  ps -eo rss=,args= | awk '/good_job start|puma/ && !/awk/ {printf "%6d  %s\n", $1/1024, substr($0, index($0,$2), 60)}'
  tail -2 /tmp/dev_watchdog.log 2>/dev/null
  echo "=== GoodJob worker ==="
  pgrep -f '[b]in/good_job start' >/dev/null && echo "进程: 运行中" || echo "进程: 未运行 ⚠ 后台作业不会被执行"
  docker exec op-postgres psql -U openproject -d openproject_development -tAc \
    "select '未结束作业: ' || count(*) from good_jobs where finished_at is null" 2>/dev/null || true
}

case "${1:-start}" in
  start)         start ;;
  stop)          stop ;;
  status)        status ;;
  db)            ensure_database_yml; start_db ;;
  logs)          tail -f /tmp/rails_server.log ;;
  logs-angular)  tail -f /tmp/angular.log ;;
  logs-worker)   tail -f /tmp/good_job.log ;;
  watchdog)      watchdog ;;
  *)             echo "用法: $0 [start|stop|status|db|logs|logs-angular|logs-worker]"; exit 1 ;;
esac
