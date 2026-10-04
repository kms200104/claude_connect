#!/usr/bin/env bash
# 마을 경제(v0.8) 화면 캡처 (아트·연출 확인용). 서버를 띄우고 tools/capture_town.tscn 을 실제 렌더러로 돌린다.
# 사용: GODOT=/path/to/godot tools/capture_town.sh /tmp/town_shots
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/town_shots}"
mkdir -p "$OUT"
DIR="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; rm -rf "$DIR"' EXIT
NOW_MIN=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
OFFSET=$(( (900 - NOW_MIN + 1440) % 1440 ))
(cd "$ROOT/server" && exec env PORT=18211 SAVE_DIR="$DIR/saves" CLOCK_OFFSET_MIN="$OFFSET" MOVE_SLACK_M=300 DOOR_GRACE_MS=0 QUEST_CHANCE=0 \
  WEATHER_FORCE=clear EVENT_FORCE=none EVENT_SPAWN_SCALE=0.02 MARKET_TICK_MS=400 REST_SPAWN_SCALE=0.1 REST_START_HISTORY=5,5,4,5,4 \
  START_SOL=3000000000 START_ITEMS=crucian:3,carp:2,rice:4,laver:4,egg:4,soy_sauce:2,radish:2,chili:2,shiitake:3,flour:2,doenjang:1,scallion:2 \
  node src/index.js >"$DIR/server.log" 2>&1) &
sleep 1
xvfb-run -a -s "-screen 0 1080x1920x24" "$GODOT" --path "$ROOT" --rendering-driver vulkan --rendering-method mobile \
  res://tools/capture_town.tscn -- --server="ws://127.0.0.1:18211" --out="$OUT" 2>&1 | grep -E '^\[capture\]|SCRIPT ERROR'
