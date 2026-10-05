#!/usr/bin/env bash
# 집 안 · 테스트 서버 종단 검증 (v0.10): 서버가 없을 때 앱 안 테스트 서버로 → 집 구경 · 꾸미기, 진짜 서버에서 집 사기 → 집 안 → 꾸미기.
# 사용: GODOT=/path/to/godot tests/run_home_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18091}"
DIR="$(mktemp -d)"
cleanup() { kill "${PID:-0}" 2>/dev/null; wait 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT
(cd "$ROOT/server" && exec env WEATHER_FORCE=clear MOVE_SLACK_M=400 DOOR_GRACE_MS=0 QUEST_CHANCE=0 EVENT_FORCE=none START_SOL=2000000000 \
  PORT="$PORT" SAVE_DIR="$DIR/saves" node src/index.js >"$DIR/server.log" 2>&1) &
PID=$!
sleep 1
timeout "${CLIENT_TIMEOUT:-240}" "$GODOT" --headless --path "$ROOT" res://tests/home_e2e.tscn -- --real="ws://127.0.0.1:$PORT" --profile=7 >"$DIR/client.log" 2>&1
RC=$?
grep -hE '^\[home\]|SCRIPT ERROR' "$DIR/client.log"
echo "--- client rc=$RC"
exit "$RC"
