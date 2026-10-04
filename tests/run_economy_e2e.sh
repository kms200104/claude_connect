#!/usr/bin/env bash
# 마을 경제 종단 검증 (v0.8): 증권 · 은행 · 부동산 · 식당(주문 → 요리 미니게임 → 별점) · 채집 · 성성호수.
# 시세는 1초마다(MARKET_TICK_MS), 손님은 금방 오고(REST_SPAWN_SCALE), 쌀·김 두 개씩과 넉넉한 솔을 들고 시작한다.
# 사용: GODOT=/path/to/godot tests/run_economy_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18089}"
DIR="$(mktemp -d)"
cleanup() { [ -n "${KEEP_LOGS:-}" ] && cp -r "$DIR" "$KEEP_LOGS" 2>/dev/null; kill "${PID:-0}" 2>/dev/null; wait 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (720 - NOW_MIN + 1440) % 1440 ))
(cd "$ROOT/server" && exec env CLOCK_OFFSET_MIN="$OFFSET" WEATHER_FORCE=clear MOVE_SLACK_M=200 DOOR_GRACE_MS=0 QUEST_CHANCE=0 EVENT_FORCE=none \
  EVENT_SPAWN_SCALE=0.02 MARKET_TICK_MS=1000 REST_SPAWN_SCALE=0.05 START_SOL=1000000000 START_ITEMS=rice:2,laver:2 \
  PORT="$PORT" SAVE_DIR="$DIR/saves" node src/index.js >"$DIR/server.log" 2>&1) &
PID=$!
sleep 1

timeout "${CLIENT_TIMEOUT:-300}" "$GODOT" --headless --path "$ROOT" res://tests/economy_e2e.tscn -- --server="ws://127.0.0.1:$PORT" --profile=1 >"$DIR/client.log" 2>&1
RC=$?
grep -hE '^\[economy\]|SCRIPT ERROR' "$DIR/client.log"
echo "--- client rc=$RC"
exit "$RC"
