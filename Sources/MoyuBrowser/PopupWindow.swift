import AppKit
import WebKit

/// 網頁用 window.open 開的彈窗（例如 Google / Apple 帳號登入）。
/// 必須用 WebKit 給的 configuration 建立新的 WKWebView，window.opener 和登入後回傳結果才會正常。
@MainActor
final class PopupWindow: NSObject, NSWindowDelegate, WKUIDelegate, WKNavigationDelegate {
    let webView: WKWebView
    private let window: NSWindow
    private var previousApp: NSRunningApplication?
    private var titleObservation: NSKeyValueObservation?

    var onClose: ((PopupWindow) -> Void)?

    init(configuration: WKWebViewConfiguration, features: WKWindowFeatures,
         userAgent: String?, centeredOn anchor: NSRect) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = userAgent

        let width = CGFloat(features.width?.doubleValue ?? 480)
        let height = CGFloat(features.height?.doubleValue ?? 640)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()

        window.title = "載入中…"
        window.isReleasedWhenClosed = false
        // 要蓋在浮動面板上面
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.contentView = webView
        window.delegate = self
        webView.uiDelegate = self
        webView.navigationDelegate = self

        var origin = NSPoint(x: anchor.midX - width / 2, y: anchor.midY - height / 2)
        if let visible = (NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - height)
        }
        window.setFrameOrigin(origin)

        titleObservation = webView.observe(\.title) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                if let title = webView.title, !title.isEmpty { self?.window.title = title }
            }
        }
    }

    func show() {
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
        // 登入完回到原本在用的 App，摸魚面板維持原樣
        if let previousApp, previousApp != NSRunningApplication.current {
            previousApp.activate()
        }
    }

    // 登入完成後網頁呼叫 window.close()
    func webViewDidClose(_ webView: WKWebView) {
        window.close()
    }

    // 彈窗裡再開新視窗，就在彈窗本身打開
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        webView.load(navigationAction.request)
        return nil
    }

    // 彈窗裡的 JS 對話框用系統對話框就好（這時 App 已經被啟用）
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        _ = runAlert(message: message, frame: frame, buttons: ["好"])
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        runAlert(message: message, frame: frame, buttons: ["好", "取消"]) == .alertFirstButtonReturn
    }

    private func runAlert(message: String, frame: WKFrameInfo, buttons: [String]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        alert.window.level = NSWindow.Level(rawValue: window.level.rawValue + 1)
        return alert.runModal()
    }
}
