#!/usr/bin/env bash
# 낚시 → 인벤토리 → 서버 재시작 후 복구까지 종단 검증 (서버 1개 + 헤드리스 Godot 1개).
# 사용: GODOT=/path/to/godot tests/run_fishing_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18081}"
DIR="$(mktemp -d)"
mkdir -p "$DIR/saves"
cleanup() { [ -n "${KEEP_LOGS:-}" ] && cp -r "$DIR" "$KEEP_LOGS" 2>/dev/null; kill "${SERVER_PID:-0}" "${GODOT_PID:-0}" 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

start_server() {
  # 마을 시계를 정오로 맞춘다 (밤에는 주민이 집 앞에 머물러 다가오지 않고, 물고기도 시간대마다 다르다).
NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (720 - NOW_MIN + 1440) % 1440 ))
(cd "$ROOT/server" && CLOCK_OFFSET_MIN="$OFFSET" PORT="$PORT" SAVE_DIR="$DIR/saves" FISH_TIME_SCALE=0.25 MOVE_SLACK_M=100 RECONNECT_GRACE_MS=5000 exec node src/index.js >>"$DIR/server.log" 2>&1) &
  SERVER_PID=$!
}

start_server
sleep 1
"$GODOT" --headless --path "$ROOT" res://tests/fishing_e2e.tscn -- --server="ws://127.0.0.1:$PORT" --dir="$DIR" --profile=1 >"$DIR/client.log" 2>&1 &
GODOT_PID=$!

# 클라이언트가 물고기를 잡을 때까지 기다린 뒤 서버를 정상 종료(저장) → 같은 저장소로 재시작
for _ in $(seq 1 900); do [ -f "$DIR/caught" ] && break; sleep 0.1; done
read -r CODE FISH < "$DIR/caught" 2>/dev/null || true
kill -TERM "$SERVER_PID"; wait "$SERVER_PID" 2>/dev/null
echo "[runner] saved file: $(ls "$DIR/saves")"
node -e "const d=JSON.parse(require('fs').readFileSync('$DIR/saves/$CODE.json','utf8'));const p=Object.values(d.profiles)[0];console.log('[runner] saved inventory:',JSON.stringify(p.slots.filter(Boolean)),'catches:',p.catches,'world catches:',d.world.totalCatches)"
sleep 1
start_server
sleep 1
touch "$DIR/restarted"

wait "$GODOT_PID"; RC=$?
grep -hE '^\[fishing\]' "$DIR/client.log"
echo "--- client rc=$RC"
exit "$RC"
