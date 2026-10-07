#!/usr/bin/env bash
# 안드로이드 APK 만들기 (Android SDK 없이): Godot 내보내기 템플릿으로 서명 안 한 APK 를 만들고 uber-apk-signer 의 디버그 키로 서명한다.
# 앱과 서버는 같은 커밋에서 만들어야 프로토콜 버전이 맞는다 ("앱 버전이 서버와 달라요").
# 사용: GODOT=/path/to/godot tools/android/build_apk.sh            → build/solbaram.apk
# 필요한 것: Godot 버전과 같은 내보내기 템플릿(~/.local/share/godot/export_templates/<버전>/android_release.apk), java.
set -eu
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$ROOT/build/android"
mkdir -p "$WORK"
# Godot 은 서명하지 않을 때도 SDK 폴더 모양(adb · apksigner)만 확인한다 → 빈 스크립트로 채운 가짜 SDK.
SDK="$WORK/fake-sdk"
mkdir -p "$SDK/platform-tools" "$SDK/build-tools/35.0.0"
printf '#!/bin/sh\nexit 0\n' > "$SDK/platform-tools/adb"
cp "$SDK/platform-tools/adb" "$SDK/build-tools/35.0.0/apksigner"
chmod +x "$SDK/platform-tools/adb" "$SDK/build-tools/35.0.0/apksigner"
SETTINGS="$(ls "$HOME"/.config/godot/editor_settings-4*.tres 2>/dev/null | head -1 || true)"
if [ -z "$SETTINGS" ]; then "$GODOT" --headless --path "$ROOT" --quit >/dev/null 2>&1 || true; SETTINGS="$(ls "$HOME"/.config/godot/editor_settings-4*.tres | head -1)"; fi
if grep -q '^export/android/android_sdk_path' "$SETTINGS"; then
  sed -i "s|^export/android/android_sdk_path = .*|export/android/android_sdk_path = \"$SDK\"|" "$SETTINGS"
else
  echo "export/android/android_sdk_path = \"$SDK\"" >> "$SETTINGS"
fi
SIGNER="$WORK/uber-apk-signer.jar"
[ -f "$SIGNER" ] || curl -sSL -o "$SIGNER" https://github.com/patrickfav/uber-apk-signer/releases/download/v1.3.0/uber-apk-signer-1.3.0.jar
# 내보내기 설정은 tools/android 에 두고 잠깐만 꺼내 쓴다 (저장소 맨 위의 개인 export_presets.cfg 는 건드리지 않는다).
BACKUP=""
if [ -f "$ROOT/export_presets.cfg" ]; then BACKUP="$WORK/export_presets.cfg.mine"; cp "$ROOT/export_presets.cfg" "$BACKUP"; fi
cp "$ROOT/tools/android/export_presets.cfg" "$ROOT/export_presets.cfg"
trap 'if [ -n "$BACKUP" ]; then mv "$BACKUP" "$ROOT/export_presets.cfg"; else rm -f "$ROOT/export_presets.cfg"; fi' EXIT
"$GODOT" --headless --path "$ROOT" --import >/dev/null 2>&1 || true
"$GODOT" --headless --path "$ROOT" --export-release "Android" "$WORK/unsigned.apk" 2>&1 | grep -E "ERROR|error" || true
java -jar "$SIGNER" -a "$WORK/unsigned.apk" -o "$WORK/signed" >/dev/null
mkdir -p "$ROOT/build"
cp "$WORK"/signed/*.apk "$ROOT/build/solbaram.apk"
echo "[apk] $ROOT/build/solbaram.apk (프로토콜 $(grep -o 'VERSION: int = [0-9]*' "$ROOT/core/protocol/net_protocol.gd" | grep -o '[0-9]*$'))"
