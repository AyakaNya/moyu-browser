#!/bin/zsh
# 從 Support/Art/ 的原始檔產生 App 圖示（Support/AppIcon.icns）與 dmg 背景（Support/DMGBackground.tiff）
# 改過原始檔之後跑一次，產出的檔案會一起 commit，平常打包不需要重跑。
set -euo pipefail
cd "$(dirname "$0")/.."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
render() { swift scripts/svg2png.swift "$@"; }

# App 圖示：原圖是畫在白底上的圓角方形（1254×1254），
# 圓角方形位在 (62, 62)、1122×1102，圓角約為邊長的 25.8%；換原圖時要重新量這幾個數字
swift scripts/icon-from-image.swift Support/Art/AppIcon-source.png "$TMP/icon1024.png" 62 62 1122 1102 0.258

# iconutil 需要的各種尺寸
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size "$TMP/icon1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$TMP/icon1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o Support/AppIcon.icns

# dmg 背景：1x 與 2x 合成一張 TIFF，Retina 螢幕上才不會糊
render Support/Art/DMGBackground.svg "$TMP/bg.png" 660 400
render Support/Art/DMGBackground.svg "$TMP/bg@2x.png" 1320 800
tiffutil -cathidpicheck "$TMP/bg.png" "$TMP/bg@2x.png" -out Support/DMGBackground.tiff >/dev/null

echo "已產生 Support/AppIcon.icns、Support/DMGBackground.tiff"
