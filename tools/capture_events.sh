#!/usr/bin/env bash
# 이벤트 화면 캡처 (아트·연출 확인용). 모드마다 이벤트를 고정한 서버를 띄우고 tools/capture_events.tscn 을 실제 렌더러로 돌린다.
# 사용: GODOT=/path/to/godot tools/capture_events.sh /tmp/event_shots
set -u
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/event_shots}"
mkdir -p "$OUT"
DIR="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; rm -rf "$DIR"' EXIT

# 한국 시각 기준으로 마을 시각을 hour 시로 맞추는 분 단위 차이.
offset_for() {
  local now=$(( ( $(date -u +%-H) * 60 + $(date -u +%-M) + 540 ) % 1440 ))
  echo $(( ($1 * 60 - now + 1440) % 1440 ))
}

run_mode() { # mode port hour env...
  local mode=$1 port=$2 hour=$3; shift 3
  (cd "$ROOT/server" && exec env PORT="$port" SAVE_DIR="$DIR/$mode" CLOCK_OFFSET_MIN="$(offset_for "$hour")" MOVE_SLACK_M=200 CHOP_COOLDOWN_MS=0 DOOR_GRACE_MS=0 "$@" node src/index.js >"$DIR/$mode.log" 2>&1) &
  local pid=$!
  sleep 1
  xvfb-run -a -s "-screen 0 1080x1920x24" "$GODOT" --path "$ROOT" --rendering-driver vulkan --rendering-method mobile \
    res://tools/capture_events.tscn -- --server="ws://127.0.0.1:$port" --mode="$mode" --out="$OUT" 2>&1 | grep -E '^\[capture\]|SCRIPT ERROR'
  kill "$pid" 2>/dev/null
}

WANT=wood,hardwood,branch,acorn,wild_mushroom
run_mode merchant 18191 12 WEATHER_FORCE=clear EVENT_FORCE=merchant EVENT_WANTED=$WANT START_SOL=300000
run_mode bargain 18192 12 WEATHER_FORCE=clear EVENT_FORCE=bargain EVENT_WANTED=$WANT
run_mode gift 18193 12 WEATHER_FORCE=clear EVENT_FORCE=gift_day EVENT_SPAWN_SCALE=0.02 FISH_TIME_SCALE=4
run_mode meteor 18194 22 WEATHER_FORCE=clear EVENT_FORCE=meteor_shower EVENT_SPAWN_SCALE=0.02
