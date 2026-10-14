#!/usr/bin/env bash
# v0.24 쓰러짐 · 일으키기 종단 검증: 서버 1개 + 헤드리스 Godot 2개 (a = 쓰러지는 사람, b = 일으키는 사람). 밤 23시 · 체력 2로 시작.
# 사용: GODOT=/path/to/godot tests/run_revive_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18100}"
DIR="$(mktemp -d)"
cleanup() { kill "${PID:-0}" "${A_PID:-0}" "${B_PID:-0}" 2>/dev/null; wait 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (1380 - NOW_MIN + 1440) % 1440 ))
(cd "$ROOT/server" && exec env CLOCK_OFFSET_MIN="$OFFSET" WEATHER_FORCE=clear MOVE_SLACK_M=1500 WORLD_TIME_SCALE=1 CREATURE_SPAWN_SCALE=0.05 START_HP=2 START_SOL=1000000 START_ITEMS=first_aid_kit:1 \
  EVENT_FORCE=none QUEST_CHANCE=0 MESSENGER_CHECK_MS=600000 NPC_APPROACH_SCALE=0 PORT="$PORT" SAVE_DIR="$DIR/saves" node src/index.js >"$DIR/server.log" 2>&1) &
PID=$!
sleep 1

ARGS=(--headless --path "$ROOT" res://tests/revive_e2e.tscn --)
timeout "${CLIENT_TIMEOUT:-200}" "$GODOT" "${ARGS[@]}" --role=a --profile=1 --server="ws://127.0.0.1:$PORT" --dir="$DIR" >"$DIR/a.log" 2>&1 &
A_PID=$!
timeout "${CLIENT_TIMEOUT:-200}" "$GODOT" "${ARGS[@]}" --role=b --profile=2 --server="ws://127.0.0.1:$PORT" --dir="$DIR" >"$DIR/b.log" 2>&1 &
B_PID=$!
wait "$A_PID"; A_RC=$?
wait "$B_PID"; B_RC=$?
grep -hE '^\[(a|b)\]|SCRIPT ERROR' "$DIR/a.log" "$DIR/b.log"
echo "--- a rc=$A_RC b rc=$B_RC"
[ "$A_RC" -eq 0 ] && [ "$B_RC" -eq 0 ]
