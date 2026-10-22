import AppKit

/// 面板收起時露在螢幕邊緣的細條。只負責顯示，不攔截滑鼠事件。
@MainActor
final class HandleWindow: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let pill = NSView()
        pill.wantsLayer = true
        pill.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.7).cgColor
        pill.layer?.cornerRadius = 2.5
        pill.autoresizingMask = [.width, .height]
        contentView = pill
    }

    func setVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? 0.2 : 0.1
            animator().alphaValue = visible ? 1 : 0
        }
    }
}
