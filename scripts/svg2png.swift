import AppKit

// 用系統內建的 SVG 支援把 SVG 畫成 PNG
// 用法：swift scripts/svg2png.swift 輸入.svg 輸出.png 寬 [高]
let args = CommandLine.arguments
guard args.count >= 4, let image = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("用法：svg2png.swift 輸入.svg 輸出.png 寬 [高]\n".data(using: .utf8)!)
    exit(1)
}
let width = Int(args[3])!
let height = args.count > 4 ? Int(args[4])! : width
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
