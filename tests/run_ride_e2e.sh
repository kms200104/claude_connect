#!/usr/bin/env bash
# 킥보드 종단 검증 (앱 안 테스트 서버): 꺼내 타기 · 차서 달리기 · 돌기 · 브레이크 · 접어 넣기.
# 사용: GODOT=/path/to/godot tests/run_ride_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$(mktemp)"
timeout "${CLIENT_TIMEOUT:-180}" "$GODOT" --headless --path "$ROOT" res://tests/ride_e2e.tscn -- --profile=7 >"$LOG" 2>&1
RC=$?
grep -hE '^\[ride\]|SCRIPT ERROR' "$LOG"
echo "--- client rc=$RC"
rm -f "$LOG"
exit "$RC"
