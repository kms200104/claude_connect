#!/usr/bin/env bash
# 이벤트 종단 검증: 떠돌이 상인의 날(서버 A) · 선물 풍선의 날(서버 B), 마을 시각은 한낮으로 맞춘다.
# 사용: GODOT=/path/to/godot tests/run_events_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT_A="${PORT_A:-18085}"
PORT_B="${PORT_B:-18086}"
DIR="$(mktemp -d)"
cleanup() { [ -n "${KEEP_LOGS:-}" ] && cp -r "$DIR" "$KEEP_LOGS" 2>/dev/null; kill "${PID_A:-0}" "${PID_B:-0}" 2>/dev/null; wait 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

# 마을 시각(한국 시간)을 12시로: 지금 한국 시각과의 차이(분)만큼 옮긴다.
NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (720 - NOW_MIN + 1440) % 1440 ))
COMMON="CLOCK_OFFSET_MIN=$OFFSET WEATHER_FORCE=clear MOVE_SLACK_M=200 CHOP_COOLDOWN_MS=0 DOOR_GRACE_MS=0"

(cd "$ROOT/server" && exec env $COMMON PORT="$PORT_A" SAVE_DIR="$DIR/a" EVENT_FORCE=merchant EVENT_WANTED=wood,hardwood,branch,acorn,wild_mushroom START_SOL=200000 node src/index.js >"$DIR/server_a.log" 2>&1) &
PID_A=$!
(cd "$ROOT/server" && exec env $COMMON PORT="$PORT_B" SAVE_DIR="$DIR/b" EVENT_FORCE=gift_day EVENT_SPAWN_SCALE=0.02 node src/index.js >"$DIR/server_b.log" 2>&1) &
PID_B=$!
sleep 1

timeout "${CLIENT_TIMEOUT:-240}" "$GODOT" --headless --path "$ROOT" res://tests/events_e2e.tscn -- --server-a="ws://127.0.0.1:$PORT_A" --server-b="ws://127.0.0.1:$PORT_B" --profile=1 >"$DIR/client.log" 2>&1
RC=$?
grep -hE '^\[events\]|SCRIPT ERROR' "$DIR/client.log"
echo "--- client rc=$RC"
exit "$RC"
