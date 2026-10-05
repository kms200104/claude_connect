#!/usr/bin/env bash
# 앱 안 테스트 서버 종단 검증 (Node 서버 없이): 대화 · 나무 베기 · 낚시 · 채집 · 거울 · 다시 접속.
# 사용: GODOT=/path/to/godot tests/run_test_server_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$(mktemp)"
timeout "${CLIENT_TIMEOUT:-180}" "$GODOT" --headless --path "$ROOT" res://tests/test_server_e2e.tscn -- --profile=6 >"$LOG" 2>&1
RC=$?
grep -hE '^\[testserver\]|SCRIPT ERROR' "$LOG"
echo "--- client rc=$RC"
rm -f "$LOG"
exit "$RC"
