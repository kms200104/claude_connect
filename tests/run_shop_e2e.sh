#!/usr/bin/env bash
# 상점 종단 검증: 달리기 · 나무 베기 → 상점 들어가기 → 주인과 대화 → 팔기 → 상점 성장 → 사기(10개씩 · 식재료는 식당 창고) → 나가기
# → 옷 입기 → 가구 설치·줍기 → 식재료 배달(마을톡 · 배달 알바).
# 사용: GODOT=/path/to/godot tests/run_shop_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18083}"
DIR="$(mktemp -d)"
cleanup() { kill "${SERVER_PID:-0}" 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

(cd "$ROOT/server" && PORT="$PORT" SAVE_DIR="$DIR/saves" MOVE_SLACK_M=200 CHOP_COOLDOWN_MS=0 DOOR_GRACE_MS=0 \
  WEATHER_FORCE=rain SHOP_POINTS_SCALE=20 START_SOL=200000 DELIVERY_TIME_SCALE=0.05 exec node src/index.js >"$DIR/server.log" 2>&1) &
SERVER_PID=$!
sleep 1

"$GODOT" --headless --path "$ROOT" res://tests/shop_e2e.tscn -- --server="ws://127.0.0.1:$PORT" --profile=1 >"$DIR/client.log" 2>&1
RC=$?
grep -hE '^\[shop\]|SCRIPT ERROR|ERROR' "$DIR/client.log" | grep -v "is not a child of the calling process" | grep -v "_check_pid_is_running"
echo "--- client rc=$RC"
exit "$RC"
