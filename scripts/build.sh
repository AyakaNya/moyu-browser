#!/bin/zsh
# 編譯並打包成 build/MoyuBrowser.app；加上 --run 會順便重新啟動。
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/MoyuBrowser.app
swift build -c release
BIN="$(swift build -c release --show-bin-path)/MoyuBrowser"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MoyuBrowser"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null
echo "已打包：$APP"

if [[ "${1:-}" == "--run" ]]; then
    pkill -x MoyuBrowser 2>/dev/null || true
    open "$APP"
fi
