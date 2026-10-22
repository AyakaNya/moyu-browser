import AppKit
import QuartzCore

/// 緩動曲線。overshoot 越大回彈越明顯，0 時退化為三次緩動。
enum Easing {
    static func outBack(_ t: Double, overshoot s: Double) -> Double {
        let u = t - 1
        return 1 + (s + 1) * u * u * u + s * u * u
    }

    static func inBack(_ t: Double, overshoot s: Double) -> Double {
        (s + 1) * t * t * t - s * t * t
    }
}

/// 負責面板貼邊的狀態機：偵測滑鼠、展開/收起動畫、版面位置與拖曳縮放。
@MainActor
final class EdgeController {
    enum State { case collapsed, expanding, expanded, collapsing }

    let panel = BrowserPanel()
    private let shadow = ShadowWindow()
    private let handle = HandleWindow()
    private let settings = Settings.shared

    private(set) var state: State = .collapsed
    var isExpanded: Bool { state == .expanded || state == .expanding }
    var isPinned = false {
        didSet { panel.browser.showToast(isPinned ? "已釘住，不會自動收起" : "已取消釘住", symbol: isPinned ? "pin.fill" : "pin.slash") }
    }

    private let screenGap: CGFloat = 8
    private let handleThickness: CGFloat = 5
    private let handleLength: CGFloat = 96
    private let hoverTolerance: CGFloat = 12
    private let minSize = CGSize(width: 280, height: 360)

    private var pollTimer: Timer?
    private var animationTimer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var hoverTime: Double = 0
    private var awayTime: Double = 0
    /// 從選單手動展開時，滑鼠還沒進過面板前不自動收起
    private var awaitingHover = false
    /// 用快捷鍵手動收起時，滑鼠要先離開感應區才會再次展開
    private var suppressUntilExit = false

    init() {
        panel.browser.onResize = { [weak self] dx, dy in self?.resize(dx: dx, dy: dy) }
        panel.onTogglePin = { [weak self] in self?.isPinned.toggle() }
        panel.onCollapse = { [weak self] in self?.collapse(suppress: true) }
        panel.browser.onNeedsAttention = { [weak self] in self?.expand(manual: true) }

        let center = NotificationCenter.default
        center.addObserver(forName: .settingsDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsDidChange() }
        }
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }

        panel.browser.applyUserAgent(mobile: settings.mobileUserAgent)
        panel.browser.loadInitialPage()
        layout()
        handle.orderFrontRegardless()
        startPolling()
    }

    // MARK: - 展開 / 收起

    func toggle() {
        if isExpanded { collapse() } else { expand(manual: true) }
    }

    func expand(manual: Bool = false) {
        guard state == .collapsed || state == .collapsing else { return }
        state = .expanding
        awaitingHover = manual
        suppressUntilExit = false
        hoverTime = 0
        awayTime = 0

        if !panel.isVisible {
            panel.setFrame(collapsedFrame(), display: false)
            updateShadow()
            panel.orderFrontRegardless()
            panel.addChildWindow(shadow, ordered: .below)
        }
        handle.setVisible(false)

        let overshoot = settings.bounce
        animatePanel(to: expandedFrame(), duration: settings.animationDuration, fadingIn: true,
                     easing: { Easing.outBack($0, overshoot: overshoot) }) { [weak self] in
            self?.state = .expanded
            self?.panel.invalidateShadow()
        }
    }

    func collapse(suppress: Bool = false) {
        guard state == .expanded || state == .expanding else { return }
        state = .collapsing
        awayTime = 0
        suppressUntilExit = suppress
        panel.browser.hideAddressBar()

        let overshoot = settings.bounce * 0.5
        animatePanel(to: collapsedFrame(), duration: settings.animationDuration * 0.8, fadingIn: false,
                     easing: { Easing.inBack($0, overshoot: overshoot) }) { [weak self] in
            guard let self else { return }
            state = .collapsed
            panel.removeChildWindow(shadow)
            shadow.orderOut(nil)
            panel.orderOut(nil)
            handle.setVisible(true)
        }
    }

    private func animatePanel(to target: NSRect, duration: Double, fadingIn: Bool,
                              easing: @escaping (Double) -> Double,
                              completion: @escaping () -> Void) {
        animationTimer?.invalidate()
        let start = panel.frame
        let startTime = CACurrentMediaTime()
        let total = max(duration, 0.01)
        // 隔壁還有螢幕時，滑到螢幕外會跑到另一個螢幕上，所以邊滑邊淡出
        let fade = hasNeighborScreen()

        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let progress = min((CACurrentMediaTime() - startTime) / total, 1)
                let e = CGFloat(easing(progress))
                let frame = NSRect(x: start.minX + (target.minX - start.minX) * e,
                                   y: start.minY + (target.minY - start.minY) * e,
                                   width: target.width, height: target.height)
                self.panel.setFrame(frame, display: true)
                let alpha = fade ? min(1, (fadingIn ? progress : 1 - progress) / 0.4) : 1
                self.panel.alphaValue = alpha
                self.shadow.alphaValue = alpha
                if progress >= 1 {
                    timer.invalidate()
                    self.animationTimer = nil
                    completion()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    // MARK: - 滑鼠偵測

    private var lastLog = 0.0
    private func debugLog(_ message: @autoclosure () -> String) {
        let now = CACurrentMediaTime()
        guard Debug.enabled, now - lastLog > 0.5 else { return }
        lastLog = now
        Debug.log("[\(state)] \(message())")
    }

    private func startPolling() {
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = now - lastTick
        lastTick = now
        let mouse = NSEvent.mouseLocation
        let inTrigger = triggerZone().contains(mouse)

        switch state {
        case .collapsed:
            if suppressUntilExit {
                if !inTrigger { suppressUntilExit = false }
                return
            }
            if inTrigger {
                hoverTime += dt
                if hoverTime >= settings.expandDelay { expand() }
            } else {
                hoverTime = 0
            }

        case .collapsing:
            if !suppressUntilExit, inTrigger || panel.frame.contains(mouse) { expand() }

        case .expanding, .expanded:
            let inside = expandedFrame().insetBy(dx: -hoverTolerance, dy: -hoverTolerance).contains(mouse) || inTrigger
            if inside { awaitingHover = false }
            let editing = panel.browser.isBusy
            let hold = inside || isPinned || awaitingHover || editing || NSEvent.pressedMouseButtons != 0
            if hold {
                debugLog("hold inside=\(inside) pinned=\(isPinned) awaiting=\(awaitingHover) editing=\(editing) buttons=\(NSEvent.pressedMouseButtons)")
                awayTime = 0
            } else {
                awayTime += dt
                if awayTime >= settings.collapseDelay { collapse() }
            }
        }
    }

    // MARK: - 版面

    private var screen: NSScreen? {
        let screens = NSScreen.screens
        if settings.displayID != 0, let chosen = screens.first(where: { $0.displayID == settings.displayID }) {
            return chosen
        }
        return screens.first
    }

    private func settingsDidChange() {
        panel.browser.applyUserAgent(mobile: settings.mobileUserAgent)
        layout()
    }

    private func layout() {
        handle.setFrame(handleFrame(), display: true)
        panel.browser.configure(edge: settings.edge, verticalAlign: settings.verticalAlign,
                                cornerRadius: CGFloat(settings.cornerRadius))
        switch state {
        case .expanded:
            panel.setFrame(expandedFrame(), display: true)
            DispatchQueue.main.async { [weak self] in self?.panel.invalidateShadow() }
        case .collapsed:
            panel.setFrame(collapsedFrame(), display: false)
        case .expanding, .collapsing:
            break
        }
        updateShadow()
    }

    private func updateShadow() {
        shadow.update(panelFrame: panel.frame, cornerRadius: CGFloat(settings.cornerRadius),
                      strength: settings.shadowStrength)
    }

    private func hasNeighborScreen() -> Bool {
        guard let screen else { return false }
        let offscreen = collapsedFrame()
        return NSScreen.screens.contains { $0 != screen && $0.frame.intersects(offscreen) }
    }

    private func expandedFrame() -> NSRect {
        guard let vf = screen?.visibleFrame else { return panel.frame }
        let w = min(CGFloat(settings.width), vf.width - screenGap * 2)
        let h = min(CGFloat(settings.height), vf.height - screenGap * 2)
        let x = settings.edge == .left ? vf.minX + screenGap : vf.maxX - screenGap - w
        let y: CGFloat
        switch settings.verticalAlign {
        case .top: y = vf.maxY - screenGap - h
        case .center: y = vf.midY - h / 2
        case .bottom: y = vf.minY + screenGap
        }
        return NSRect(x: x, y: y, width: w, height: h).integral
    }

    /// 收起時整個面板移到螢幕外（連陰影一起）
    private func collapsedFrame() -> NSRect {
        var frame = expandedFrame()
        guard let sf = screen?.frame else { return frame }
        let offset = ShadowWindow.margin + 10
        frame.origin.x = settings.edge == .left ? sf.minX - frame.width - offset : sf.maxX + offset
        return frame
    }

    /// 收起時露在邊緣的細條，垂直置中對齊面板
    private func handleFrame() -> NSRect {
        guard let vf = screen?.visibleFrame else { return .zero }
        let panelFrame = expandedFrame()
        let length = min(handleLength, panelFrame.height)
        let x = settings.edge == .left ? vf.minX + 1 : vf.maxX - handleThickness - 1
        return NSRect(x: x, y: panelFrame.midY - length / 2, width: handleThickness, height: length)
    }

    /// 觸發展開的感應區：細條附近、貼著螢幕邊緣
    private func triggerZone() -> NSRect {
        guard let sf = screen?.frame else { return .zero }
        let hf = handleFrame()
        let minX = settings.edge == .left ? sf.minX - 1 : hf.minX - 3
        let maxX = settings.edge == .left ? hf.maxX + 3 : sf.maxX + 1
        return NSRect(x: minX, y: hf.minY - 24, width: maxX - minX, height: hf.height + 48)
    }

    /// 拖曳面板未貼邊的那幾條邊來調整大小，貼邊那側保持不動
    private func resize(dx: CGFloat, dy: CGFloat) {
        guard let vf = screen?.visibleFrame else { return }
        let current = expandedFrame()
        var w = current.width + (settings.edge == .left ? dx : -dx)
        var h = current.height
        switch settings.verticalAlign {
        case .top: h -= dy
        case .center: h += dy * 2
        case .bottom: h += dy
        }
        w = min(max(w, minSize.width), vf.width - screenGap * 2)
        h = min(max(h, minSize.height), vf.height - screenGap * 2)
        if w != current.width { settings.width = Double(w) }
        if h != current.height { settings.height = Double(h) }
    }
}
