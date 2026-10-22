import AppKit
import SwiftUI
import WebKit

/// 面板內容：圓角容器裡放滿版的 WKWebView，上面疊一層 Liquid Glass 介面，最上層是縮放把手。
@MainActor
final class BrowserView: NSView, WKUIDelegate {
    static let iPhoneUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"

    let webView: WKWebView
    private let model = BrowserModel()
    private let bookmarks = BookmarkStore.shared
    private let overlay: OverlayHostingView

    private let sideHandle = ResizeHandle(axis: .horizontal)
    private let edgeHandle = ResizeHandle(axis: .vertical)
    private let cornerHandle = ResizeHandle(axis: .both)
    private var dockEdge: DockEdge = .left
    private var verticalAlign: VerticalAlign = .bottom
    private var cornerRadius: CGFloat = 30
    /// 網頁的主題色或背景色，用來填頂部留白，讓它跟網頁融為一體
    private var pageColor: NSColor?

    /// 頂部留白：圓角越大留越多，避免網頁內容貼著圓角
    private var topInset: CGFloat { max(14, (cornerRadius * 0.6).rounded()) }

    private var observations: [NSKeyValueObservation] = []

    var onResize: ((CGFloat, CGFloat) -> Void)? {
        didSet { [sideHandle, edgeHandle, cornerHandle].forEach { $0.onDrag = onResize } }
    }

    var isAddressBarVisible: Bool { model.isAddressBarVisible }

    override init(frame frameRect: NSRect) {
        let config = WKWebViewConfiguration()
        // 預設的資料儲存區會把 Cookie、登入狀態等寫進磁碟，重開 App 仍保留
        config.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: config)
        overlay = OverlayHostingView(rootView: BrowserOverlay(model: model, bookmarks: BookmarkStore.shared))
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5

        setupSubviews()
        bindModel()
        observeWebView()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = (pageColor ?? NSColor.windowBackgroundColor).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    // MARK: - 版面

    private func setupSubviews() {
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)

        overlay.isInteractive = { [weak self] in self?.model.isAddressBarVisible ?? false }
        // 不讓 SwiftUI 內容反過來限制面板大小
        overlay.sizingOptions = []
        overlay.autoresizingMask = [.width, .height]
        addSubview(overlay)

        // 縮放把手疊在最上層，位置在 layout() 裡依貼邊方向決定
        [sideHandle, edgeHandle, cornerHandle].forEach(addSubview)
    }

    func configure(edge: DockEdge, verticalAlign: VerticalAlign, cornerRadius: CGFloat) {
        dockEdge = edge
        self.verticalAlign = verticalAlign
        self.cornerRadius = cornerRadius
        layer?.cornerRadius = cornerRadius
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let b = bounds
        webView.frame = NSRect(x: 0, y: 0, width: b.width, height: max(b.height - topInset, 0))
        overlay.frame = b

        let thickness: CGFloat = 6
        let corner: CGFloat = 14
        // 可拖曳的是「沒貼著螢幕」的那一側與那一端
        let freeOnRight = dockEdge == .left
        let freeOnTop = verticalAlign != .top

        sideHandle.frame = NSRect(x: freeOnRight ? b.maxX - thickness : b.minX, y: 0,
                                  width: thickness, height: b.height)
        edgeHandle.frame = NSRect(x: 0, y: freeOnTop ? b.maxY - thickness : b.minY,
                                  width: b.width, height: thickness)
        cornerHandle.frame = NSRect(x: freeOnRight ? b.maxX - corner : b.minX,
                                    y: freeOnTop ? b.maxY - corner : b.minY,
                                    width: corner, height: corner)
    }

    private func bindModel() {
        model.onSubmit = { [weak self] text in
            guard let self, let url = Self.url(from: text) else { return }
            open(url)
        }
        model.onOpen = { [weak self] url in self?.open(url) }
        model.onDismiss = { [weak self] in self?.hideAddressBar() }
        model.onToggleBookmark = { [weak self] in self?.toggleBookmark() }
    }

    // MARK: - 網址列

    func showAddressBar() {
        let current = webView.url?.absoluteString ?? ""
        model.originalQuery = current
        model.query = current
        if model.isAddressBarVisible {
            (window?.firstResponder as? NSTextView)?.selectAll(nil)
        }
        model.isAddressBarVisible = true
        window?.makeKey()
    }

    func hideAddressBar() {
        guard model.isAddressBarVisible else { return }
        model.isAddressBarVisible = false
        window?.makeFirstResponder(webView)
    }

    func toggleAddressBar() {
        if model.isAddressBarVisible { hideAddressBar() } else { showAddressBar() }
    }

    private func open(_ url: URL) {
        webView.load(URLRequest(url: url))
        hideAddressBar()
    }

    // MARK: - 快捷鍵動作

    func toggleBookmark() {
        guard let url = webView.url else {
            showToast("目前沒有網頁可以收藏", symbol: "exclamationmark.circle")
            return
        }
        let added = bookmarks.toggle(title: webView.title ?? "", url: url)
        showToast(added ? "已加入收藏" : "已移除收藏", symbol: added ? "star.fill" : "star.slash")
    }

    func copyCurrentURL() {
        guard let url = webView.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        showToast("已拷貝網址", symbol: "link")
    }

    func reloadOrStop() {
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }

    func goHome() {
        if let url = Self.url(from: Settings.shared.homeURL) { open(url) }
    }

    func zoom(by step: CGFloat?) {
        webView.pageZoom = step.map { min(max(webView.pageZoom + $0, 0.5), 3) } ?? 1
        showToast("縮放 \(Int((webView.pageZoom * 100).rounded()))%", symbol: "plus.magnifyingglass")
    }

    func showToast(_ text: String, symbol: String) {
        model.showToast(text, symbol: symbol)
    }

    // MARK: - 網頁

    func open(urlString: String) {
        if let url = Self.url(from: urlString) { open(url) }
    }

    func loadInitialPage() {
        let settings = Settings.shared
        if let url = Self.url(from: settings.lastURL ?? settings.homeURL) {
            webView.load(URLRequest(url: url))
        }
    }

    func applyUserAgent(mobile: Bool) {
        let agent = mobile ? Self.iPhoneUserAgent : nil
        guard webView.customUserAgent != agent else { return }
        webView.customUserAgent = agent
        if webView.url != nil { webView.reload() }
    }

    /// 有網址格式就直接開，否則當作關鍵字丟給 Google
    static func url(from text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about"].contains(scheme) {
            return url
        }
        if !text.contains(" "), text.contains("."), let url = URL(string: "https://" + text) {
            return url
        }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.url
    }

    private func observeWebView() {
        observations = [
            webView.observe(\.url) { [weak self] webView, _ in
                MainActor.assumeIsolated {
                    self?.model.currentURL = webView.url
                    if let url = webView.url { Settings.shared.lastURL = url.absoluteString }
                }
            },
            webView.observe(\.estimatedProgress) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.model.progress = webView.estimatedProgress }
            },
            webView.observe(\.isLoading) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.model.isLoading = webView.isLoading }
            },
            webView.observe(\.themeColor) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updatePageColor() }
            },
            webView.observe(\.underPageBackgroundColor) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.updatePageColor() }
            },
        ]
    }

    private func updatePageColor() {
        pageColor = webView.themeColor ?? webView.underPageBackgroundColor
        if let rgb = pageColor?.usingColorSpace(.sRGB) {
            let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
            model.pageIsDark = luminance < 0.5
        }
        needsDisplay = true
    }

    // 開新視窗的連結（target=_blank）直接在目前頁面打開
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

/// 面板邊緣的透明拖曳區，回報滑鼠位移（螢幕座標）
@MainActor
final class ResizeHandle: NSView {
    enum Axis { case horizontal, vertical, both }

    let axis: Axis
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    private var lastLocation = NSPoint.zero

    init(axis: Axis) {
        self.axis = axis
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var cursor: NSCursor {
        switch axis {
        case .horizontal: .resizeLeftRight
        case .vertical: .resizeUpDown
        case .both: .crosshair
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { cursor.set() }
    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        lastLocation = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        let location = NSEvent.mouseLocation
        let dx = axis == .vertical ? 0 : location.x - lastLocation.x
        let dy = axis == .horizontal ? 0 : location.y - lastLocation.y
        lastLocation = location
        cursor.set()
        onDrag?(dx, dy)
    }
}

