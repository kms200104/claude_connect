#!/usr/bin/env bash
# v0.28 게이트 종단 검증 (서버 1개 + Godot 1개, 한낮 · 첫 게이트가 곧 열린다 · 크리처가 제자리에 선다).
# 사용: GODOT=/path/to/godot tests/run_gate_e2e.sh   (SHOTS=폴더 를 주면 화면을 찍는다)
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18105}"
DIR="$(mktemp -d)"
cleanup() { kill "${SERVER_PID:-0}" 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (720 - NOW_MIN + 1440) % 1440 ))
(cd "$ROOT/server" && CLOCK_OFFSET_MIN="$OFFSET" PORT="$PORT" SAVE_DIR="$DIR/saves" MOVE_SLACK_M=1500 WORLD_TIME_SCALE=1 CREATURE_FREEZE=1 GATE_FIRST_MS=1500 GATE_FORCE_RANK=E GATE_FORCE_SPOT=g01 WEATHER_FORCE=clear START_ITEMS=pipe_spear:1 \
  EVENT_FORCE=none QUEST_CHANCE=0 MESSENGER_CHECK_MS=600000 NPC_APPROACH_SCALE=0 exec node src/index.js >"$DIR/server.log" 2>&1) &
SERVER_PID=$!
sleep 1

if [ -n "${SHOTS:-}" ]; then
  mkdir -p "$SHOTS"
  xvfb-run -a -s "-screen 0 ${SCREEN:-1080x1920x24}" "$GODOT" --path "$ROOT" --rendering-driver vulkan --rendering-method mobile ${GODOT_ARGS:-} res://tests/gate_e2e.tscn -- --server="ws://127.0.0.1:$PORT" --shots="$SHOTS" >"$DIR/client.log" 2>&1
else
  timeout "${CLIENT_TIMEOUT:-180}" "$GODOT" --headless --path "$ROOT" res://tests/gate_e2e.tscn -- --server="ws://127.0.0.1:$PORT" >"$DIR/client.log" 2>&1
fi
RC=$?
grep -hE "^\[gate\]|SCRIPT ERROR|ERROR:|at: " "$DIR/client.log" | grep -v VK_KHR | head -80
echo "--- client rc=$RC"
exit "$RC"
