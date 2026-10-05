#!/usr/bin/env bash
# 섬 생활 종단 검증 (v0.6): 브레이크 · 감정표현과 주민 반응 · 대화 주제 · 심기와 자라기 · 꽃 따기 · 박물관 기증 · 공항 기념품.
# 마을 시각은 한낮, 나무·꽃은 아주 빨리 자라게(GROWTH_SCALE), 시작 친밀도 30 · 도토리·알뿌리·물고기를 들고 시작한다.
# 사용: GODOT=/path/to/godot tests/run_island_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18087}"
DIR="$(mktemp -d)"
cleanup() { [ -n "${KEEP_LOGS:-}" ] && cp -r "$DIR" "$KEEP_LOGS" 2>/dev/null; kill "${PID:-0}" 2>/dev/null; wait 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (720 - NOW_MIN + 1440) % 1440 ))
(cd "$ROOT/server" && exec env CLOCK_OFFSET_MIN="$OFFSET" WEATHER_FORCE=clear MOVE_SLACK_M=200 CHOP_COOLDOWN_MS=0 DOOR_GRACE_MS=0 \
  QUEST_CHANCE=0 EVENT_FORCE=lumber_day GROWTH_SCALE=0.003 START_FRIENDSHIP=30 START_SOL=200000 \
  NPC_APPROACH_SCALE=0 START_ITEMS=acorn:2,seed_tulip:2,crucian:1,loach:1 PORT="$PORT" SAVE_DIR="$DIR/saves" node src/index.js >"$DIR/server.log" 2>&1) &
PID=$!
sleep 1

timeout "${CLIENT_TIMEOUT:-300}" "$GODOT" --headless --path "$ROOT" res://tests/island_e2e.tscn -- --server="ws://127.0.0.1:$PORT" --profile=1 >"$DIR/client.log" 2>&1
RC=$?
grep -hE '^\[island\]|SCRIPT ERROR' "$DIR/client.log"
echo "--- client rc=$RC"
exit "$RC"
