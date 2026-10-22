import AppKit
import Carbon.HIToolbox

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
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.process(event) ?? false }
            return consumed ? nil : event
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// 點到別的 App 時收回網址列和分頁總覽，否則面板會因為「正在操作」一直不收起
    override func resignKey() {
        super.resignKey()
        browser.hideAddressBar()
        browser.hideOverview()
    }

    /// 回傳 true 代表事件已處理、不再往下傳
    private func process(_ event: NSEvent) -> Bool {
        guard event.window === self else { return false }
        if event.type == .keyDown { return handleKeyDown(event) }
        if event.type == .scrollWheel { return browser.handleSwipe(event) }
        // 不啟用 App 的面板點了也不會自動變成 key window，鍵盤事件就會送到別的 App，
        // 所以點擊時手動 makeKey；滑鼠只是經過不會搶走原本 App 的輸入焦點。
        if !isKeyWindow { makeKey() }
        return false
    }

    /// 快捷鍵用實體按鍵位置（keyCode）判斷，切到注音等輸入法時字元會變成「ㄠ」之類，不能拿來比對。
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)

        let composing = (firstResponder as? NSTextView)?.hasMarkedText() == true

        // 網頁對話框：Return 確定、Esc 取消；正在用輸入法組字時先讓輸入法處理
        if browser.hasDialog, !composing {
            switch keyCode {
            case kVK_Return, kVK_ANSI_KeypadEnter: browser.finishDialog(confirmed: true); return true
            case kVK_Escape: browser.finishDialog(confirmed: false); return true
            default: break
            }
        }

        // Esc 收回分頁總覽
        if keyCode == kVK_Escape, browser.isOverviewVisible {
            browser.hideOverview()
            return true
        }

        // Esc 收回網址列
        if keyCode == kVK_Escape, browser.isAddressBarVisible {
            if composing { return false }
            browser.hideAddressBar()
            return true
        }

        let combo = KeyCombo(event)

        // ⌘1～⌘9 切分頁固定不變
        if combo.flags == .command, let number = ShortcutStore.numberKeys.firstIndex(of: keyCode) {
            browser.selectTab(number: number + 1)
            return true
        }

        if let shortcut = ShortcutStore.shared.shortcut(matching: combo) {
            perform(shortcut)
            return true
        }

        // App 沒被啟用時主選單收不到編輯快捷鍵，在這裡補上
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option),
              let action = editAction(for: keyCode, shift: flags.contains(.shift)) else { return false }
        return NSApp.sendAction(action, to: nil, from: self)
    }

    private func perform(_ shortcut: Shortcut) {
        switch shortcut {
        case .addressBar: browser.toggleAddressBar()
        case .newTab: browser.newTab()
        case .closeTab: browser.closeCurrentTab()
        case .reopenTab: browser.reopenClosedTab()
        case .previousTab: browser.selectTab(offset: -1)
        case .nextTab: browser.selectTab(offset: 1)
        case .tabNumber: break
        case .overview: browser.toggleOverview()
        case .bookmark: browser.toggleBookmark()
        case .back: browser.webView.goBack()
        case .forward: browser.webView.goForward()
        case .reload: browser.reloadOrStop()
        case .home: browser.goHome()
        case .copyURL: browser.copyCurrentURL()
        case .zoomIn: browser.zoom(by: 0.1)
        case .zoomOut: browser.zoom(by: -0.1)
        case .zoomReset: browser.zoom(by: nil)
        case .pin: onTogglePin?()
        case .hide: onCollapse?()
        case .settings: onOpenSettings?()
        }
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
