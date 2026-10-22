#!/bin/zsh
# 產出可以發佈的安裝包：universal 的 .app，再包成 .zip 和 .dmg，放在 dist/
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh --universal

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
NAME="MoyuBrowser-$VERSION"
DIST=dist
rm -rf "$DIST"
mkdir -p "$DIST"

# zip：用 ditto 才會保留簽名與延伸屬性
ditto -c -k --keepParent build/MoyuBrowser.app "$DIST/$NAME.zip"

# dmg：裡面放 App 和「應用程式」捷徑，拖過去就裝好
STAGE=$(mktemp -d)
cp -R build/MoyuBrowser.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "摸魚瀏覽器 $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$NAME.dmg"
rm -rf "$STAGE"

echo "安裝包："
ls -lh "$DIST"
