#!/usr/bin/env bash
# 아파트 집 안(v0.10) 화면 캡처: 평면도마다 집 안 · 위에서 본 꾸미기 화면. 서버를 띄우고 실제 렌더러로 돌린다.
# 사용: GODOT=/path/to/godot tools/capture_home.sh /tmp/home_shots [34]
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/home_shots}"
ONLY="${2:-}"
mkdir -p "$OUT"
DIR="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; rm -rf "$DIR"' EXIT
NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (900 - NOW_MIN + 1440) % 1440 ))
(cd "$ROOT/server" && exec env PORT=18213 SAVE_DIR="$DIR/saves" CLOCK_OFFSET_MIN="$OFFSET" MOVE_SLACK_M=400 DOOR_GRACE_MS=0 QUEST_CHANCE=0 \
  WEATHER_FORCE=clear EVENT_FORCE=none EVENT_SPAWN_SCALE=0.02 START_SOL=5000000000 \
  node src/index.js >"$DIR/server.log" 2>&1) &
sleep 1
xvfb-run -a -s "-screen 0 1080x1920x24" "$GODOT" --path "$ROOT" --rendering-driver vulkan --rendering-method mobile \
  res://tools/capture_home.tscn -- --srv="ws://127.0.0.1:18213" --out="$OUT" ${ONLY:+--only=$ONLY} 2>&1 | grep -E '^\[capture\]|SCRIPT ERROR|ERROR'
