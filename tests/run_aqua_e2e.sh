#!/usr/bin/env bash
# 물놀이 체험 종단 검증 (앱 안 테스트 서버): 바나나 보트 · 유람선 타기 · 꽉 잡기 · 내리기.
# 사용: GODOT=/path/to/godot tests/run_aqua_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$(mktemp)"
timeout "${CLIENT_TIMEOUT:-180}" "$GODOT" --headless --path "$ROOT" res://tests/aqua_e2e.tscn -- --profile=7 >"$LOG" 2>&1
RC=$?
grep -hE '^\[aqua\]|SCRIPT ERROR' "$LOG"
echo "--- client rc=$RC"
rm -f "$LOG"
exit "$RC"
