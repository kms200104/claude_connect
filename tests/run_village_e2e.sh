#!/usr/bin/env bash
# 마을 종단 검증: 비 · 도끼 들기 · 나무 베기 → 인벤토리 · 가방 창 시선 · 주민 대화 → 부탁 → 완료 (서버 1개 + 헤드리스 Godot 1개).
# 사용: GODOT=/path/to/godot tests/run_village_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18082}"
DIR="$(mktemp -d)"
cleanup() { kill "${SERVER_PID:-0}" 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

(cd "$ROOT/server" && PORT="$PORT" SAVE_DIR="$DIR/saves" MOVE_SLACK_M=200 CHOP_COOLDOWN_MS=0 \
  WEATHER_FORCE=rain QUEST_CHANCE=1 QUEST_TEMPLATE=wood exec node src/index.js >"$DIR/server.log" 2>&1) &
SERVER_PID=$!
sleep 1

"$GODOT" --headless --path "$ROOT" res://tests/village_e2e.tscn -- --server="ws://127.0.0.1:$PORT" --profile=1 >"$DIR/client.log" 2>&1
RC=$?
grep -hE '^\[village\]|SCRIPT ERROR|ERROR' "$DIR/client.log" | grep -v "is not a child of the calling process" | grep -v "_check_pid_is_running"
echo "--- client rc=$RC"
exit "$RC"
