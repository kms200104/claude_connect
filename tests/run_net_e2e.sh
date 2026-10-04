#!/usr/bin/env bash
# 서버 + 헤드리스 Godot 2개로 방 코드 접속 / 위치 동기화·보간 / 재접속을 검증한다.
# 사용: GODOT=/path/to/godot tests/run_net_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18080}"
DIR="$(mktemp -d)"
cleanup() { kill "${SERVER_PID:-0}" "${HOST_PID:-0}" "${GUEST_PID:-0}" 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

(cd "$ROOT/server" && PORT="$PORT" SAVE_DIR="$DIR/saves" exec node src/index.js >"$DIR/server.log" 2>&1) &
SERVER_PID=$!
sleep 1

ARGS=(--headless --path "$ROOT" res://tests/net_e2e.tscn --)
"$GODOT" "${ARGS[@]}" --role=host --profile=1 --server="ws://127.0.0.1:$PORT" --dir="$DIR" >"$DIR/host.log" 2>&1 &
HOST_PID=$!
"$GODOT" "${ARGS[@]}" --role=guest --profile=2 --server="ws://127.0.0.1:$PORT" --dir="$DIR" >"$DIR/guest.log" 2>&1 &
GUEST_PID=$!

wait "$GUEST_PID"; GUEST_RC=$?
wait "$HOST_PID"; HOST_RC=$?
grep -hE '^\[(host|guest)\]' "$DIR/host.log" "$DIR/guest.log"
echo "--- host rc=$HOST_RC guest rc=$GUEST_RC"
[ "$HOST_RC" -eq 0 ] && [ "$GUEST_RC" -eq 0 ]
