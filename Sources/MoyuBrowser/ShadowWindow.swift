import AppKit

extension NSScreen {
    var displayID: Int {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }
}

/// 疊在面板後面、只畫陰影的視窗。系統陰影不能調強度，所以自己畫。
/// 陰影只畫在面板外圍（用遮罩挖掉中間），不攔截滑鼠。
@MainActor
final class ShadowWindow: NSPanel {
    static let margin: CGFloat = 70

    private let shadowLayer = CALayer()
    private let maskLayer = CAShapeLayer()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let host = NSView()
        host.wantsLayer = true
        host.layer?.addSublayer(shadowLayer)
        shadowLayer.shadowColor = NSColor.black.cgColor
        maskLayer.fillRule = .evenOdd
        shadowLayer.mask = maskLayer
        contentView = host
    }

    func update(panelFrame: NSRect, cornerRadius: CGFloat, strength: Double) {
        let m = Self.margin
        setFrame(panelFrame.insetBy(dx: -m, dy: -m), display: false)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = NSRect(origin: .zero, size: frame.size)
        let inner = NSRect(x: m, y: m, width: panelFrame.width, height: panelFrame.height)
        let s = CGFloat(strength)
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = CGPath(roundedRect: inner, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        shadowLayer.shadowOpacity = Float(0.15 + 0.4 * s)
        shadowLayer.shadowRadius = 10 + 26 * s
        shadowLayer.shadowOffset = CGSize(width: 0, height: -(4 + 12 * s))

        let maskPath = CGMutablePath()
        maskPath.addRect(bounds)
        maskPath.addPath(CGPath(roundedRect: inner.insetBy(dx: 1, dy: 1),
                                cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        maskLayer.frame = bounds
        maskLayer.path = maskPath
        CATransaction.commit()
    }
}
