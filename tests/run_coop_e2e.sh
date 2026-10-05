#!/usr/bin/env bash
# 같이 하기 종단 검증 (v0.9): 서버 1개 + 헤드리스 Godot 2개 (a = 방장, b = 손님).
# 동사무소 · 혼인신고 세대 지갑 · 햇살론유스 · 식당 같이 일하기 · 여울 그물 몰이 · 조개 같이 캐기 · 삽 구덩이/흙길.
# 둘 다 쌀·김 두 개씩, 뜰채·삽, 넉넉한 솔을 들고 시작한다.
# 사용: GODOT=/path/to/godot tests/run_coop_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18090}"
DIR="$(mktemp -d)"
cleanup() { [ -n "${KEEP_LOGS:-}" ] && cp -r "$DIR" "$KEEP_LOGS" 2>/dev/null; kill "${PID:-0}" "${A_PID:-0}" "${B_PID:-0}" 2>/dev/null; wait 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (720 - NOW_MIN + 1440) % 1440 ))
(cd "$ROOT/server" && exec env CLOCK_OFFSET_MIN="$OFFSET" WEATHER_FORCE=clear MOVE_SLACK_M=200 DOOR_GRACE_MS=0 QUEST_CHANCE=0 EVENT_FORCE=none \
  EVENT_SPAWN_SCALE=0.02 REST_SPAWN_SCALE=0.05 START_SOL=30000000 START_ITEMS=rice:2,laver:2,fishing_net:1,shovel:1 \
  PORT="$PORT" SAVE_DIR="$DIR/saves" node src/index.js >"$DIR/server.log" 2>&1) &
PID=$!
sleep 1

ARGS=(--headless --path "$ROOT" res://tests/coop_e2e.tscn --)
timeout "${CLIENT_TIMEOUT:-300}" "$GODOT" "${ARGS[@]}" --role=a --profile=1 --server="ws://127.0.0.1:$PORT" --dir="$DIR" >"$DIR/a.log" 2>&1 &
A_PID=$!
timeout "${CLIENT_TIMEOUT:-300}" "$GODOT" "${ARGS[@]}" --role=b --profile=2 --server="ws://127.0.0.1:$PORT" --dir="$DIR" >"$DIR/b.log" 2>&1 &
B_PID=$!
wait "$A_PID"; A_RC=$?
wait "$B_PID"; B_RC=$?
grep -hE '^\[(a|b)\]|SCRIPT ERROR' "$DIR/a.log" "$DIR/b.log"
echo "--- a rc=$A_RC b rc=$B_RC"
[ "$A_RC" -eq 0 ] && [ "$B_RC" -eq 0 ]
