#!/bin/zsh
# 編譯並打包成 build/MoyuBrowser.app
#   --run        打包後順便重新啟動
#   --universal  同時編譯 Apple Silicon 與 Intel（需要完整的 Xcode）
set -euo pipefail
cd "$(dirname "$0")/.."

RUN=false
UNIVERSAL=false
for arg in "$@"; do
    case "$arg" in
        --run) RUN=true ;;
        --universal) UNIVERSAL=true ;;
        *) echo "不認得的參數：$arg" >&2; exit 1 ;;
    esac
done

BUILD_ARGS=(-c release)
if $UNIVERSAL; then
    # 多架構編譯要用 Xcode 的工具鏈，Command Line Tools 不行
    if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
        export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
fi

APP=build/MoyuBrowser.app
swift build "${BUILD_ARGS[@]}"
BIN="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)/MoyuBrowser"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MoyuBrowser"
cp Support/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "已打包：$APP（$(lipo -archs "$APP/Contents/MacOS/MoyuBrowser")）"

if $RUN; then
    pkill -x MoyuBrowser 2>/dev/null || true
    open "$APP"
fi
