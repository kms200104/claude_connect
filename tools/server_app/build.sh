#!/usr/bin/env bash
# PC 용 테스트 서버 묶음 (Windows): node.exe + 서버 코드 + 데이터 + START_SERVER.bat → build/solbaram-server-win64.zip
# 받는 사람은 git · Node.js 없이 압축을 풀고 START_SERVER.bat 만 두 번 누르면 된다 (테스트 도구 DEV_TOOLS=1 로 켬).
# 사용: tools/server_app/build.sh   (필요한 것: node · npm · curl · unzip · zip)
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NODE_VERSION="${NODE_VERSION:-v22.22.0}"
WORK="$ROOT/build/server_app"
PKG="$WORK/solbaram-server"
rm -rf "$PKG" && mkdir -p "$PKG/node" "$PKG/server" "$WORK/cache"
ZIP="$WORK/cache/node-$NODE_VERSION-win-x64.zip"
[ -f "$ZIP" ] || curl -sSL -o "$ZIP" "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-win-x64.zip"
unzip -q -j -o "$ZIP" "node-$NODE_VERSION-win-x64/node.exe" -d "$PKG/node"
cp -r "$ROOT/server/src" "$ROOT/server/package.json" "$ROOT/server/package-lock.json" "$PKG/server/"
(cd "$PKG/server" && npm ci --omit=dev --no-audit --no-fund --silent)
cp -r "$ROOT/data" "$PKG/data"
# 배치 파일 · 안내는 Windows 줄바꿈으로.
sed 's/\r$//; s/$/\r/' "$ROOT/tools/server_app/START_SERVER.bat" > "$PKG/START_SERVER.bat"
{ printf '\xef\xbb\xbf'; sed 's/\r$//; s/$/\r/' "$ROOT/tools/server_app/README.txt"; } > "$PKG/README.txt"
PROTO="$(grep -o 'PROTOCOL_VERSION = [0-9]*' "$ROOT/server/src/protocol.js" | grep -o '[0-9]*$')"
echo "protocol $PROTO · $(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)" > "$PKG/VERSION.txt"
mkdir -p "$ROOT/build"
rm -f "$ROOT/build/solbaram-server-win64.zip"
(cd "$WORK" && zip -q -r "$ROOT/build/solbaram-server-win64.zip" solbaram-server)
echo "[server_app] $ROOT/build/solbaram-server-win64.zip (프로토콜 $PROTO, $(du -h "$ROOT/build/solbaram-server-win64.zip" | cut -f1))"
