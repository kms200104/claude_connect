#!/data/data/com.termux/files/usr/bin/bash
# Termux(안드로이드)에서 솔바람 서버를 켜 두고, 저장소에 새 커밋이 올라오면 저절로 받아서 다시 켠다.
# 사용: bash ~/claude_connect/tools/termux/serve.sh        (끄기: Ctrl+C)
# 바꿀 수 있는 값 (앞에 붙여서): PORT=8080 CHECK_EVERY=20 DEV_TOOLS=1 BRANCH=<브랜치>
#  - CHECK_EVERY 초마다 git fetch → 새 커밋이 있으면 git pull(빨리감기만) → 패키지가 바뀌었으면 npm ci → 서버를 끄고(저장) 다시 켠다.
#  - 서버가 저절로 죽으면 3초 뒤 다시 켠다. 프로토콜 버전이 바뀌면 "앱(APK)도 새로 받아야" 한다고 알려 준다.
#  - 이 폴더에서 직접 고친 파일이 있으면 pull 이 안 되므로 알려만 주고 그대로 둔다 (git stash 또는 git checkout . 로 정리).
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1
BRANCH="${BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
export PORT="${PORT:-8080}"
export DEV_TOOLS="${DEV_TOOLS:-1}"
CHECK_EVERY="${CHECK_EVERY:-20}"
SERVER_PID=""

say() { printf '\033[1;36m[serve]\033[0m %s\n' "$*"; }
proto() { grep -o 'PROTOCOL_VERSION = [0-9]*' "$ROOT/server/src/protocol.js" | grep -o '[0-9]*$'; }

start_server() {
  (cd "$ROOT/server" && exec node src/index.js) &
  SERVER_PID=$!
  say "서버 켬 (PID $SERVER_PID, 커밋 $(git rev-parse --short HEAD), 프로토콜 $(proto), 테스트 도구 DEV_TOOLS=$DEV_TOOLS)"
}

stop_server() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill -TERM "$SERVER_PID" 2>/dev/null   # SIGTERM: 서버가 방을 저장하고 끝난다
    for _ in $(seq 1 50); do kill -0 "$SERVER_PID" 2>/dev/null || break; sleep 0.1; done
    kill -9 "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
  fi
  SERVER_PID=""
}

install_packages() {
  say "패키지 설치 (npm ci)..."
  (cd "$ROOT/server" && npm ci --omit=dev --no-audit --no-fund --silent) || say "npm ci 실패 — 위 메시지를 보세요"
}

show_address() {
  local ips
  ips="$(ip -4 addr show 2>/dev/null | grep -o 'inet [0-9.]*' | grep -o '[0-9.]*$' | grep -v '^127\.' || true)"
  say "앱의 서버 주소: 이 폰에서는 ws://127.0.0.1:$PORT"
  if [ -n "$ips" ]; then
    for ip in $ips; do say "              다른 폰에서는 ws://$ip:$PORT"; done
  else
    say "              다른 폰에서는 ws://<이 폰 IP>:$PORT (설정 → Wi-Fi → 연결된 네트워크 → IP 주소)"
  fi
}

cleanup() { echo; say "끄는 중..."; stop_server; command -v termux-wake-unlock >/dev/null && termux-wake-unlock; exit 0; }
trap cleanup INT TERM

command -v termux-wake-lock >/dev/null && termux-wake-lock
say "브랜치 $BRANCH 를 ${CHECK_EVERY}초마다 확인합니다. 끄려면 Ctrl+C."
git pull -q --ff-only origin "$BRANCH" 2>/dev/null || say "처음 git pull 을 못 했어요 (인터넷 · 직접 고친 파일 확인) — 있는 코드로 켭니다."
[ -d "$ROOT/server/node_modules" ] || install_packages
show_address
start_server

last_check=0
while true; do
  sleep 1
  # 서버가 죽었으면 다시 켠다 (포트를 다른 서버가 잡고 있으면 그 서버를 먼저 꺼야 한다).
  if [ -n "$SERVER_PID" ] && ! kill -0 "$SERVER_PID" 2>/dev/null; then
    wait "$SERVER_PID" 2>/dev/null; code=$?
    if [ "$code" = "2" ]; then
      say "포트 $PORT 를 다른 서버가 쓰고 있어요. 그 Termux 창의 서버를 끄거나 PORT=8081 로 켜세요. 10초 뒤 다시 해 봅니다."
      SERVER_PID=""; sleep 10
    else
      say "서버가 멈췄어요 (종료 코드 $code). 3초 뒤 다시 켭니다."
      SERVER_PID=""; sleep 3
    fi
    start_server
  fi
  now=$(date +%s)
  [ $((now - last_check)) -lt "$CHECK_EVERY" ] && continue
  last_check=$now
  git fetch -q origin "$BRANCH" 2>/dev/null || continue
  local_head="$(git rev-parse HEAD)"
  remote_head="$(git rev-parse "origin/$BRANCH")"
  [ "$local_head" = "$remote_head" ] && continue
  # 이미 받은 것보다 앞선 새 커밋만 (로컬이 앞서 있으면 그대로).
  git merge-base --is-ancestor "$local_head" "$remote_head" || continue
  old_proto="$(proto)"
  say "새 커밋: $(git log --format='%h %s' -1 "$remote_head")"
  if ! git merge -q --ff-only "origin/$BRANCH"; then
    say "받지 못했어요: 이 폴더에서 고친 파일이 있어요 (git status 로 확인). 서버는 그대로 둡니다."
    continue
  fi
  if ! git diff --quiet "$local_head" HEAD -- server/package.json server/package-lock.json; then
    install_packages
  fi
  stop_server
  start_server
  new_proto="$(proto)"
  [ "$old_proto" != "$new_proto" ] && say "⚠ 프로토콜 $old_proto → $new_proto: 앱(APK)도 같은 커밋으로 새로 받아야 접속돼요."
done
