import AppKit

// 把一張「圓角方形畫在白底上」的圖做成 macOS 圖示：
// 裁出圓角方形、縮放到 1024 畫布中央的 824×824，並用圓角遮罩去掉角落外的白底。
// 用法：swift scripts/icon-from-image.swift 輸入圖 輸出.png x y 寬 高 圓角比例
let args = CommandLine.arguments
guard args.count == 8, let source = NSImage(contentsOfFile: args[1]),
      let rep = source.representations.first else {
    FileHandle.standardError.write("用法：icon-from-image.swift 輸入圖 輸出.png x y 寬 高 圓角比例\n".data(using: .utf8)!)
    exit(1)
}
let crop = NSRect(x: Double(args[3])!, y: Double(args[4])!, width: Double(args[5])!, height: Double(args[6])!)
let radiusRatio = CGFloat(Double(args[7])!)

// 來源座標是左上角原點，NSImage 繪圖是左下角原點
let pixelHeight = CGFloat(rep.pixelsHigh)
let scale = source.size.height / pixelHeight
let from = NSRect(x: crop.minX * scale, y: (pixelHeight - crop.maxY) * scale,
                  width: crop.width * scale, height: crop.height * scale)

let canvas = 1024
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: out)!
context.imageInterpolation = .high
NSGraphicsContext.current = context
// 遮罩往內縮 2px，確保邊緣不殘留白底
let mask = tile.insetBy(dx: 2, dy: 2)
let radius = mask.width * radiusRatio
NSBezierPath(roundedRect: mask, xRadius: radius, yRadius: radius).addClip()
source.draw(in: tile, from: from, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
