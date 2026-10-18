#!/usr/bin/env bash
# v0.28 헌터 종단 검증 (서버 1개 + Godot 1개, 밤 23시 · 크리처가 제자리에 선다).
# 사용: GODOT=/path/to/godot tests/run_hunter_e2e.sh   (SHOTS=폴더 를 주면 화면을 찍는다)
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18104}"
DIR="$(mktemp -d)"
cleanup() { kill "${SERVER_PID:-0}" 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (1380 - NOW_MIN + 1440) % 1440 ))
(cd "$ROOT/server" && CLOCK_OFFSET_MIN="$OFFSET" PORT="$PORT" SAVE_DIR="$DIR/saves" MOVE_SLACK_M=1500 WORLD_TIME_SCALE=1 CREATURE_SPAWN_SCALE=0.05 CREATURE_FREEZE=1 SUPPLY_FIRST_MS=600000 WEATHER_FORCE=clear START_ITEMS=pipe_spear:1,mana_stone_e:3,mana_stone_d:1 \
  START_HUNTER_LV=10 START_MILEAGE=500 EVENT_FORCE=none QUEST_CHANCE=0 MESSENGER_CHECK_MS=600000 NPC_APPROACH_SCALE=0 exec node src/index.js >"$DIR/server.log" 2>&1) &
SERVER_PID=$!
sleep 1

if [ -n "${SHOTS:-}" ]; then
  mkdir -p "$SHOTS"
  xvfb-run -a -s "-screen 0 ${SCREEN:-1080x1920x24}" "$GODOT" --path "$ROOT" --rendering-driver vulkan --rendering-method mobile ${GODOT_ARGS:-} res://tests/hunter_e2e.tscn -- --server="ws://127.0.0.1:$PORT" --shots="$SHOTS" >"$DIR/client.log" 2>&1
else
  timeout "${CLIENT_TIMEOUT:-180}" "$GODOT" --headless --path "$ROOT" res://tests/hunter_e2e.tscn -- --server="ws://127.0.0.1:$PORT" >"$DIR/client.log" 2>&1
fi
RC=$?
grep -hE "^\[hunter\]|SCRIPT ERROR|ERROR:|at: " "$DIR/client.log" | grep -v VK_KHR | head -80
echo "--- client rc=$RC"
exit "$RC"
