#!/bin/zsh
# 產出可以發佈的安裝包：universal 的 .app，再包成 .zip 和 .dmg，放在 dist/
# dmg 打開會是拖拉安裝的畫面：背景圖、App 在左、「應用程式」在右
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh --universal

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
NAME="MoyuBrowser-$VERSION"
VOLUME="摸魚瀏覽器 $VERSION"
DIST=dist
rm -rf "$DIST"
mkdir -p "$DIST"

# zip：用 ditto 才會保留簽名與延伸屬性
ditto -c -k --keepParent build/MoyuBrowser.app "$DIST/$NAME.zip"

# dmg：先做可寫入的版本，讓 Finder 記住視窗排版，再壓縮成唯讀
TMP=$(mktemp -d)
trap 'hdiutil detach -quiet "/Volumes/$VOLUME" 2>/dev/null || true; rm -rf "$TMP"' EXIT
STAGE="$TMP/stage"
mkdir -p "$STAGE/.background"
cp -R build/MoyuBrowser.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Support/DMGBackground.tiff "$STAGE/.background/background.tiff"
cp Support/AppIcon.icns "$STAGE/.VolumeIcon.icns"

hdiutil detach -quiet "/Volumes/$VOLUME" 2>/dev/null || true
hdiutil create -quiet -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$TMP/rw.dmg"
hdiutil attach -quiet -nobrowse -noautoopen "$TMP/rw.dmg"
SetFile -a C "/Volumes/$VOLUME"   # 用 .VolumeIcon.icns 當磁碟圖示

# 座標要跟 Support/Art/DMGBackground.svg 裡的箭頭對齊
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set options to icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 128
        set text size of options to 13
        set background picture of options to file ".background:background.tiff"
        set position of item "MoyuBrowser.app" of container window to {170, 205}
        set position of item "Applications" of container window to {490, 205}
        -- 視窗內容 660×400，再加上標題列的高度
        set bounds of container window to {200, 120, 860, 552}
        update without registering applications
        delay 1
        -- 關掉再打開一次，Finder 才會把視窗大小寫進 .DS_Store
        close
        open
        set bounds of container window to {200, 120, 860, 552}
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
hdiutil detach -quiet "/Volumes/$VOLUME"
hdiutil convert -quiet "$TMP/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$DIST/$NAME.dmg"

echo "安裝包："
ls -lh "$DIST"
