import AppKit
import Carbon.HIToolbox

/// 面板內的快捷鍵一覽，選單列的「快捷鍵」清單也從這裡產生
enum Shortcut: CaseIterable {
    case addressBar, bookmark, back, forward, reload, home, copyURL
    case zoomIn, zoomOut, zoomReset, pin, hide, settings

    var title: String {
        switch self {
        case .addressBar: "叫出 / 收回網址列"
        case .bookmark: "收藏 / 取消收藏"
        case .back: "上一頁"
        case .forward: "下一頁"
        case .reload: "重新整理 / 停止"
        case .home: "回首頁"
        case .copyURL: "拷貝網址"
        case .zoomIn: "放大"
        case .zoomOut: "縮小"
        case .zoomReset: "實際大小"
        case .pin: "釘住 / 取消釘住"
        case .hide: "立刻收起面板"
        case .settings: "設定"
        }
    }

    var keys: String {
        switch self {
        case .addressBar: "⌘L"
        case .bookmark: "⌘D"
        case .back: "⌘["
        case .forward: "⌘]"
        case .reload: "⌘R"
        case .home: "⌘⇧H"
        case .copyURL: "⌘⇧C"
        case .zoomIn: "⌘+"
        case .zoomOut: "⌘-"
        case .zoomReset: "⌘0"
        case .pin: "⌘P"
        case .hide: "⌘W"
        case .settings: "⌘,"
        }
    }
}

/// 無邊框、不搶焦點的浮動面板；圓角由內容視圖決定，重陰影由 ShadowWindow 負責。
@MainActor
final class BrowserPanel: NSPanel {
    let browser = BrowserView()

    var onTogglePin: (() -> Void)?
    var onCollapse: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var eventMonitor: Any?

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Settings.phoneSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        // 只在 init 傳入 .nonactivatingPanel 時，視窗伺服器有時不會套用「不啟用 App」，
        // 點面板會把整個 App 帶到前台；拿掉再加回去才會確實生效。
        styleMask.remove(.nonactivatingPanel)
        styleMask.insert(.nonactivatingPanel)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = browser
        initialFirstResponder = browser.webView

        // 用 App 層的事件監聽而不是 performKeyEquivalent：監聽在輸入法之前執行、每次按鍵只觸發一次；
        // performKeyEquivalent 在注音等輸入法下會被呼叫好幾次，Esc 也會被輸入法吃掉。
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.process(event) ?? false }
            return consumed ? nil : event
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 點到別的 App 時收回網址列，否則面板會因為「正在輸入」一直不收起
    override func resignKey() {
        super.resignKey()
        browser.hideAddressBar()
    }

    /// 回傳 true 代表事件已處理、不再往下傳
    private func process(_ event: NSEvent) -> Bool {
        guard event.window === self else { return false }
        if event.type == .keyDown { return handleKeyDown(event) }
        // 不啟用 App 的面板點了也不會自動變成 key window，鍵盤事件就會送到別的 App，
        // 所以點擊時手動 makeKey；滑鼠只是經過不會搶走原本 App 的輸入焦點。
        if !isKeyWindow { makeKey() }
        return false
    }

    /// 用實體按鍵位置（keyCode）判斷，切到注音等輸入法時字元會變成「ㄠ」之類，不能拿來比對。
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)

        // Esc 收回網址列；正在用輸入法組字時先讓輸入法處理
        if keyCode == kVK_Escape, browser.isAddressBarVisible {
            if (firstResponder as? NSTextView)?.hasMarkedText() == true { return false }
            browser.hideAddressBar()
            return true
        }

        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else { return false }
        let shift = flags.contains(.shift)

        switch (keyCode, shift) {
        case (kVK_ANSI_L, false): browser.toggleAddressBar()
        case (kVK_ANSI_D, false): browser.toggleBookmark()
        case (kVK_ANSI_LeftBracket, false): browser.webView.goBack()
        case (kVK_ANSI_RightBracket, false): browser.webView.goForward()
        case (kVK_ANSI_R, false): browser.reloadOrStop()
        case (kVK_ANSI_H, true): browser.goHome()
        case (kVK_ANSI_C, true): browser.copyCurrentURL()
        case (kVK_ANSI_Equal, _): browser.zoom(by: 0.1)
        case (kVK_ANSI_Minus, false): browser.zoom(by: -0.1)
        case (kVK_ANSI_0, false): browser.zoom(by: nil)
        case (kVK_ANSI_P, false): onTogglePin?()
        case (kVK_ANSI_W, false): onCollapse?()
        case (kVK_ANSI_Comma, false): onOpenSettings?()
        default:
            guard let action = editAction(for: keyCode, shift: shift) else { return false }
            return NSApp.sendAction(action, to: nil, from: self)
        }
        return true
    }

    private func editAction(for keyCode: Int, shift: Bool) -> Selector? {
        switch keyCode {
        case kVK_ANSI_C: #selector(NSText.copy(_:))
        case kVK_ANSI_V: #selector(NSText.paste(_:))
        case kVK_ANSI_X: #selector(NSText.cut(_:))
        case kVK_ANSI_A: #selector(NSText.selectAll(_:))
        case kVK_ANSI_Z: shift ? Selector(("redo:")) : Selector(("undo:"))
        default: nil
        }
    }
}
