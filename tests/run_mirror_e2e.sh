#!/usr/bin/env bash
# 거울 종단 검증 (v0.7): 광장 거울 · 얼굴 꾸미기 창 · 저장 · 거울 가구 · 닉네임 (v14: 이름 탭 · 설정 창).
# 마을 시각은 한낮, 전신 거울 하나를 들고 시작한다.
# 사용: GODOT=/path/to/godot tests/run_mirror_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18088}"
DIR="$(mktemp -d)"
cleanup() { [ -n "${KEEP_LOGS:-}" ] && cp -r "$DIR" "$KEEP_LOGS" 2>/dev/null; kill "${PID:-0}" 2>/dev/null; wait 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (720 - NOW_MIN + 1440) % 1440 ))
(cd "$ROOT/server" && exec env CLOCK_OFFSET_MIN="$OFFSET" WEATHER_FORCE=clear MOVE_SLACK_M=200 CHOP_COOLDOWN_MS=0 DOOR_GRACE_MS=0 \
  QUEST_CHANCE=0 START_ITEMS=standing_mirror:1 PORT="$PORT" SAVE_DIR="$DIR/saves" node src/index.js >"$DIR/server.log" 2>&1) &
PID=$!
sleep 1

timeout "${CLIENT_TIMEOUT:-300}" "$GODOT" --headless --path "$ROOT" res://tests/mirror_e2e.tscn -- --server="ws://127.0.0.1:$PORT" --profile=1 >"$DIR/client.log" 2>&1
RC=$?
grep -hE '^\[mirror\]|SCRIPT ERROR' "$DIR/client.log"
echo "--- client rc=$RC"
exit "$RC"
