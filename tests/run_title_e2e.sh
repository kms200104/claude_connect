#!/usr/bin/env bash
# 첫 화면 종단 검증: 새 마을 만들기 → 나가기 → 첫 화면을 다시 띄우면 서버 주소·마지막 방이 채워져 있고 "시작하기"로 같은 방에 들어감.
# 사용: GODOT=/path/to/godot tests/run_title_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-18084}"
DIR="$(mktemp -d)"
cleanup() { kill "${SERVER_PID:-0}" 2>/dev/null; rm -rf "$DIR"; }
trap cleanup EXIT

(cd "$ROOT/server" && PORT="$PORT" SAVE_DIR="$DIR/saves" exec node src/index.js >"$DIR/server.log" 2>&1) &
SERVER_PID=$!
sleep 1

"$GODOT" --headless --path "$ROOT" res://tests/title_e2e.tscn -- --title-server="ws://127.0.0.1:$PORT" --profile=9 >"$DIR/client.log" 2>&1
RC=$?
grep -hE '^\[title\]|SCRIPT ERROR' "$DIR/client.log"
echo "--- client rc=$RC"
exit "$RC"
