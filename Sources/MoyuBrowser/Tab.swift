import AppKit
import WebKit

/// 一個分頁：自己的 WKWebView，加上還沒載入時要開的網址，以及分頁總覽用的縮圖。
@MainActor
final class Tab {
    let id = UUID()
    let webView: WKWebView
    /// 重開 App 還原的分頁先不載入，第一次切過去才載入，省記憶體
    var pendingURL: URL?
    private(set) var snapshot: NSImage?
    /// 網址或標題變了（分頁總覽與保存分頁要跟著更新）
    var onChange: (() -> Void)?

    private var observations: [NSKeyValueObservation] = []

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.autoresizingMask = [.width, .height]
        observations = [
            webView.observe(\.url) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.onChange?() }
            },
            webView.observe(\.title) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.onChange?() }
            },
        ]
    }

    var url: URL? { webView.url ?? pendingURL }

    var title: String {
        if let title = webView.title, !title.isEmpty { return title }
        return url?.host() ?? "新分頁"
    }

    func loadIfNeeded() {
        guard let pendingURL else { return }
        self.pendingURL = nil
        webView.load(URLRequest(url: pendingURL))
    }

    /// 只有正在畫面上的分頁拍得到縮圖
    func updateSnapshot() async {
        guard webView.window != nil, webView.url != nil else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 360
        if let image = try? await webView.takeSnapshot(configuration: configuration) {
            snapshot = image
        }
    }
}
