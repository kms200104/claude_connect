#!/usr/bin/env bash
# v16 휴대폰 앱 · 설정 · 놀거리 종단 검증 (서버 1개 + Godot 1개, 친구는 테스트 안의 봇).
# 사용: GODOT=/path/to/godot tests/run_phone_apps_e2e.sh   (SHOTS=폴더 를 주면 화면을 찍는다 — 화면이 있는 렌더러가 필요)
# 가로 화면으로 찍기: SCREEN=1920x1080x24 GODOT_ARGS="--resolution 1280x576"
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18093}"
DIR="$(mktemp -d)"
cleanup() { kill "${SERVER_PID:-0}" 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

# 마을 시계를 정오로 (밤 곡 · 밤 조명이 섞이지 않게).
NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (720 - NOW_MIN + 1440) % 1440 ))
ITEMS="log_stool:1,flower_pot:1,wood_chair:1,round_table:1,bench:1,standing_mirror:1,vanity_mirror:1,floor_lamp:1,bookshelf:1,rocking_chair:1"
(cd "$ROOT/server" && CLOCK_OFFSET_MIN="$OFFSET" PORT="$PORT" SAVE_DIR="$DIR/saves" MOVE_SLACK_M=200 WEATHER_FORCE=clear EVENT_FORCE=none QUEST_CHANCE=0 \
  START_FRIENDSHIP=10 START_SOL=900000000 START_ITEMS="$ITEMS" MESSENGER_CHECK_MS=600000 NPC_APPROACH_SCALE=0 exec node src/index.js >"$DIR/server.log" 2>&1) &
SERVER_PID=$!
sleep 1

if [ -n "${SHOTS:-}" ]; then
  mkdir -p "$SHOTS"
  xvfb-run -a -s "-screen 0 ${SCREEN:-1080x1920x24}" "$GODOT" --path "$ROOT" --rendering-driver vulkan --rendering-method mobile ${GODOT_ARGS:-} res://tests/phone_apps_e2e.tscn -- --server="ws://127.0.0.1:$PORT" --shots="$SHOTS" >"$DIR/client.log" 2>&1
else
  "$GODOT" --headless --path "$ROOT" res://tests/phone_apps_e2e.tscn -- --server="ws://127.0.0.1:$PORT" >"$DIR/client.log" 2>&1
fi
RC=$?
grep -hE "^\[apps\]|SCRIPT ERROR|ERROR:|at: " "$DIR/client.log" | grep -v VK_KHR | head -120; [ -n "${KEEP_LOG:-}" ] && cp "$DIR/client.log" "$KEEP_LOG"
echo "--- client rc=$RC"
exit "$RC"
