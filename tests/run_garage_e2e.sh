#!/usr/bin/env bash
# 차고 탈것 종단 검증 (앱 안 테스트 서버): 휴대폰 탈것 앱 사기 · 꾸미기 · 자전거 · 전기오토바이 타기 · 팔기.
# 사용: GODOT=/path/to/godot tests/run_garage_e2e.sh
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$(mktemp)"
timeout "${CLIENT_TIMEOUT:-180}" "$GODOT" --headless --path "$ROOT" res://tests/garage_e2e.tscn -- --profile=7 >"$LOG" 2>&1
RC=$?
grep -hE '^\[garage\]|SCRIPT ERROR' "$LOG"
echo "--- client rc=$RC"
rm -f "$LOG"
exit "$RC"
