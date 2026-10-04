#!/usr/bin/env bash
# 섬 생활(v0.6) 화면 캡처 (아트·연출 확인용). 모드마다 서버를 띄우고 tools/capture_island.tscn 을 실제 렌더러로 돌린다.
# 사용: GODOT=/path/to/godot tools/capture_island.sh /tmp/island_shots
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/island_shots}"
mkdir -p "$OUT"
DIR="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; rm -rf "$DIR"' EXIT

offset_for() {
  local now=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
  echo $(( ($1 * 60 - now + 1440) % 1440 ))
}

# MODES="places life" 처럼 일부만 찍을 수 있다.
want() { [[ " ${MODES:-places life fish mirror} " == *" $1 "* ]]; }

run_mode() { # mode port hour env...
  local mode=$1 port=$2 hour=$3; shift 3
  (cd "$ROOT/server" && exec env PORT="$port" SAVE_DIR="$DIR/$mode" CLOCK_OFFSET_MIN="$(offset_for "$hour")" MOVE_SLACK_M=300 CHOP_COOLDOWN_MS=0 DOOR_GRACE_MS=0 QUEST_CHANCE=0 "$@" node src/index.js >"$DIR/$mode.log" 2>&1) &
  local pid=$!
  sleep 1
  xvfb-run -a -s "-screen 0 2200x2200x24" "$GODOT" --path "$ROOT" --rendering-driver vulkan --rendering-method mobile ${RES:+--resolution $RES} \
    res://tools/capture_island.tscn -- --server="ws://127.0.0.1:$port" --mode="$mode" --out="$OUT" 2>&1 | grep -E '^\[capture\]|SCRIPT ERROR'
  kill "$pid" 2>/dev/null
}

want places && run_mode places 18201 15 WEATHER_FORCE=clear EVENT_FORCE=lumber_day START_ITEMS=crucian:1,goldfish:1,loach:1,carp:1,catfish:1
want life && run_mode life 18202 15 WEATHER_FORCE=clear EVENT_FORCE=lumber_day GROWTH_SCALE=0.02 START_FRIENDSHIP=30 \
  START_ITEMS=acorn:3,pinecone:2,seed_tulip:3,seed_cosmos:3,seed_sunflower:2,seed_hydrangea:2,crucian:1,loach:1,goldfish:1
want fish && run_mode fish 18203 15 WEATHER_FORCE=clear EVENT_FORCE=lumber_day FISH_TIME_SCALE=0.3
want mirror && run_mode mirror 18204 15 WEATHER_FORCE=clear
