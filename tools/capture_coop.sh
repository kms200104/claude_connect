#!/usr/bin/env bash
# v0.9 화면 캡처 (아트·연출 확인용): 첫 화면 항공뷰 · 동사무소 · 여울 · 조개 · 삽. 서버를 띄우고 실제 렌더러로 돌린다.
# 사용: GODOT=/path/to/godot tools/capture_coop.sh /tmp/coop_shots
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/coop_shots}"
mkdir -p "$OUT"
DIR="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; rm -rf "$DIR"' EXIT
NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (900 - NOW_MIN + 1440) % 1440 ))
(cd "$ROOT/server" && exec env PORT=18212 SAVE_DIR="$DIR/saves" CLOCK_OFFSET_MIN="$OFFSET" MOVE_SLACK_M=300 DOOR_GRACE_MS=0 QUEST_CHANCE=0 \
  WEATHER_FORCE=clear EVENT_FORCE=none EVENT_SPAWN_SCALE=0.02 START_SOL=30000000 START_ITEMS=fishing_net:1,shovel:1 \
  node src/index.js >"$DIR/server.log" 2>&1) &
sleep 1
xvfb-run -a -s "-screen 0 1080x1920x24" "$GODOT" --path "$ROOT" --rendering-driver vulkan --rendering-method mobile \
  res://tools/capture_coop.tscn -- --srv="ws://127.0.0.1:18212" --out="$OUT" 2>&1 | grep -E '^\[capture\]|SCRIPT ERROR'
