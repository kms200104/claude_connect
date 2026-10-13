#!/usr/bin/env bash
# v0.20 폰다운 기능 종단 검증 (서버 1개 + Godot 1개): 앱 스토어 · 솔걸음 · 재난문자 · 민방위 훈련.
# 사용: GODOT=/path/to/godot tests/run_phone_safety_e2e.sh   (SHOTS=폴더 를 주면 화면을 찍는다)
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18095}"
DIR="$(mktemp -d)"
cleanup() { kill "${SERVER_PID:-0}" 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (720 - NOW_MIN + 1440) % 1440 ))
(cd "$ROOT/server" && CLOCK_OFFSET_MIN="$OFFSET" PORT="$PORT" SAVE_DIR="$DIR/saves" MOVE_SLACK_M=1500 WEATHER_FORCE=thunder DRILL_FORCE=1 \
  LIGHTNING_MIN_MS=600000 LIGHTNING_MAX_MS=600000 EVENT_FORCE=none QUEST_CHANCE=0 MESSENGER_CHECK_MS=600000 NPC_APPROACH_SCALE=0 exec node src/index.js >"$DIR/server.log" 2>&1) &
SERVER_PID=$!
sleep 1

if [ -n "${SHOTS:-}" ]; then
  mkdir -p "$SHOTS"
  xvfb-run -a -s "-screen 0 ${SCREEN:-1080x1920x24}" "$GODOT" --path "$ROOT" --rendering-driver vulkan --rendering-method mobile ${GODOT_ARGS:-} res://tests/phone_safety_e2e.tscn -- --server="ws://127.0.0.1:$PORT" --shots="$SHOTS" >"$DIR/client.log" 2>&1
else
  timeout "${CLIENT_TIMEOUT:-180}" "$GODOT" --headless --path "$ROOT" res://tests/phone_safety_e2e.tscn -- --server="ws://127.0.0.1:$PORT" >"$DIR/client.log" 2>&1
fi
RC=$?
grep -hE "^\[safety\]|SCRIPT ERROR|ERROR:|at: " "$DIR/client.log" | grep -v VK_KHR | head -80
echo "--- client rc=$RC"
exit "$RC"
