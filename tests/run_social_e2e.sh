#!/usr/bin/env bash
# 주민·마을톡 종단 검증 (v0.11): 주민이 돌아보기 · 먼저 다가와 말 걸기 · 마을톡 연락·답장 (서버 1개 + Godot 1개).
# 사용: GODOT=/path/to/godot tests/run_social_e2e.sh   (SHOTS=폴더 를 주면 화면을 찍는다 — 화면이 있는 렌더러가 필요)
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18091}"
DIR="$(mktemp -d)"
cleanup() { kill "${SERVER_PID:-0}" 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

(cd "$ROOT/server" && PORT="$PORT" SAVE_DIR="$DIR/saves" MOVE_SLACK_M=200 WEATHER_FORCE=clear EVENT_FORCE=none QUEST_CHANCE=0 \
  START_FRIENDSHIP=10 NPC_APPROACH_SCALE=40 MESSENGER_CHECK_MS=400 MESSENGER_REPLY_SCALE=0.2 exec node src/index.js >"$DIR/server.log" 2>&1) &
SERVER_PID=$!
sleep 1

if [ -n "${SHOTS:-}" ]; then
  xvfb-run -a -s "-screen 0 1080x1920x24" "$GODOT" --path "$ROOT" --rendering-driver vulkan --rendering-method mobile res://tests/social_e2e.tscn -- --server="ws://127.0.0.1:$PORT" --profile=1 --shots="$SHOTS" >"$DIR/client.log" 2>&1
else
  "$GODOT" --headless --path "$ROOT" res://tests/social_e2e.tscn -- --server="ws://127.0.0.1:$PORT" --profile=1 >"$DIR/client.log" 2>&1
fi
RC=$?
grep -hE '^\[social\]|SCRIPT ERROR' "$DIR/client.log"
echo "--- client rc=$RC"
exit "$RC"
