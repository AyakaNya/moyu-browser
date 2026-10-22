import AppKit
import SwiftUI
import WebKit

/// 面板內容：圓角容器裡放目前分頁的 WKWebView，上面疊一層 Liquid Glass 介面，最上層是縮放把手。
@MainActor
final class BrowserView: NSView, WKUIDelegate, WKNavigationDelegate {
    static let iPhoneUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1"

    private let model = BrowserModel()
    private let bookmarks = BookmarkStore.shared
    private let overlay: OverlayHostingView
    /// 放目前分頁網頁的容器，切換分頁時在這裡做推移轉場
    private let pageContainer = NSView()

    private var tabs: [Tab] = []
    private var currentIndex = 0
    /// 關掉的分頁網址，⌘⇧T 依序重新打開
    private var closedTabURLs: [URL] = []

    var webView: WKWebView { tabs[currentIndex].webView }

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
    private var popups: [PopupWindow] = []
    private var isPickingFiles = false

    /// 網址列附近的觸控板手勢：左右滑切換分頁、往上滑打開分頁總覽。
    /// 記錄這次手勢累積的手指位移、判定的方向，以及是否已經觸發過
    private enum SwipeAxis { case horizontal, vertical }
    private var swipeOffset = CGSize.zero
    private var swipeAxis: SwipeAxis?
    private var swipeHandled = false

    var onResize: ((CGFloat, CGFloat) -> Void)? {
        didSet { [sideHandle, edgeHandle, cornerHandle].forEach { $0.onDrag = onResize } }
    }

    var isAddressBarVisible: Bool { model.isAddressBarVisible }
    var isOverviewVisible: Bool { model.isOverviewVisible }

    /// 正在跟使用者互動（網址列、分頁總覽、對話框、選檔案、登入彈窗），面板不該自動收起
    var isBusy: Bool {
        model.isAddressBarVisible || model.isOverviewVisible || model.dialog != nil
            || isPickingFiles || !popups.isEmpty
    }

    var hasDialog: Bool { model.dialog != nil }

    /// 網頁需要使用者回應（例如跳出對話框）時，請面板展開
    var onNeedsAttention: (() -> Void)?

    override init(frame frameRect: NSRect) {
        overlay = OverlayHostingView(rootView: BrowserOverlay(model: model, bookmarks: BookmarkStore.shared))
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5

        setupSubviews()
        bindModel()
        restoreTabs()
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
        pageContainer.wantsLayer = true
        addSubview(pageContainer)

        overlay.isInteractive = { [weak self] in
            guard let self else { return false }
            return model.isAddressBarVisible || model.isOverviewVisible || model.dialog != nil
        }
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
        pageContainer.frame = NSRect(x: 0, y: 0, width: b.width, height: max(b.height - topInset, 0))
        webView.frame = pageContainer.bounds
        overlay.frame = b
        if model.topInset != topInset { model.topInset = topInset }

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
        model.onShowOverview = { [weak self] in self?.showOverview() }
        model.onDismissOverview = { [weak self] in self?.hideOverview() }
        model.onSelectTab = { [weak self] id in
            guard let self, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
            select(index)
            hideOverview()
        }
        model.onCloseTab = { [weak self] id in self?.closeTab(id: id) }
        model.onNewTab = { [weak self] in self?.newTab() }
        DownloadManager.shared.onEvent = { [weak self] text, symbol in self?.showToast(text, symbol: symbol) }
    }

    func finishDialog(confirmed: Bool) {
        model.finishDialog(confirmed: confirmed)
    }

    // MARK: - 分頁

    private func makeTab(url: URL? = nil) -> Tab {
        let configuration = WKWebViewConfiguration()
        // 預設的資料儲存區會把 Cookie、登入狀態等寫進磁碟，重開 App 仍保留；所有分頁共用
        configuration.websiteDataStore = .default()
        // 預設的 User-Agent 沒有 Safari 字樣，Google 等網站會擋登入，所以補上
        configuration.applicationNameForUserAgent = "Version/18.5 Safari/605.1.15"
        let tab = Tab(configuration: configuration)
        tab.webView.uiDelegate = self
        tab.webView.navigationDelegate = self
        tab.webView.customUserAgent = Settings.shared.mobileUserAgent ? Self.iPhoneUserAgent : nil
        tab.pendingURL = url
        tab.onChange = { [weak self] in self?.tabsDidChange() }
        return tab
    }

    /// 還原上次開著的分頁；只有目前分頁會在 loadInitialPage() 時載入
    private func restoreTabs() {
        let settings = Settings.shared
        var urls = settings.savedTabs.compactMap(Self.url(from:))
        if urls.isEmpty, let home = Self.url(from: settings.homeURL) { urls = [home] }
        tabs = urls.map { makeTab(url: $0) }
        if tabs.isEmpty { tabs = [makeTab()] }
        currentIndex = min(max(settings.savedTabIndex, 0), tabs.count - 1)
        pageContainer.addSubview(webView)
        observeCurrentTab()
    }

    func loadInitialPage() {
        tabs[currentIndex].loadIfNeeded()
        tabsDidChange()
    }

    private enum Push { case fromLeft, fromRight }

    private func select(_ index: Int, push: Push? = nil) {
        guard tabs.indices.contains(index) else { return }
        let incoming = tabs[index]
        guard incoming.webView.superview == nil else { return }

        pageContainer.subviews.forEach { $0.removeFromSuperview() }
        currentIndex = index
        incoming.webView.frame = pageContainer.bounds
        if let push {
            let transition = CATransition()
            transition.type = .push
            transition.subtype = push == .fromRight ? .fromRight : .fromLeft
            transition.duration = 0.28
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pageContainer.layer?.add(transition, forKey: "switchTab")
        }
        pageContainer.addSubview(incoming.webView)
        incoming.loadIfNeeded()
        observeCurrentTab()
        updatePageColor()

        if model.isAddressBarVisible {
            fillAddressBar()
        } else {
            window?.makeFirstResponder(incoming.webView)
        }
        tabsDidChange()
    }

    /// 切到前一個或後一個分頁；快捷鍵會繞回頭尾，滑動手勢不會
    func selectTab(offset: Int, wrap: Bool = true) {
        guard tabs.count > 1 else { return }
        var target = currentIndex + offset
        if wrap {
            target = (target + tabs.count) % tabs.count
        } else if !tabs.indices.contains(target) {
            return
        }
        select(target, push: offset > 0 ? .fromRight : .fromLeft)
    }

    /// ⌘1～⌘8 切到第幾個分頁，⌘9 切到最後一個
    func selectTab(number: Int) {
        let target = number == 9 ? tabs.count - 1 : number - 1
        guard target != currentIndex else { return }
        select(target, push: target > currentIndex ? .fromRight : .fromLeft)
    }

    @discardableResult
    func newTab(url: URL? = nil, showAddressBar: Bool = true) -> Tab {
        let tab = makeTab(url: url ?? Self.url(from: Settings.shared.homeURL))
        tabs.insert(tab, at: currentIndex + 1)
        hideOverview()
        select(currentIndex + 1, push: .fromRight)
        if showAddressBar { self.showAddressBar() }
        return tab
    }

    func closeCurrentTab() {
        closeTab(id: tabs[currentIndex].id)
    }

    private func closeTab(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        if let url = tab.url { closedTabURLs.append(url) }
        tab.webView.stopLoading()
        tab.webView.removeFromSuperview()
        tabs.remove(at: index)

        // 關掉最後一個分頁時，留一個首頁分頁
        if tabs.isEmpty { tabs = [makeTab(url: Self.url(from: Settings.shared.homeURL))] }
        if index < currentIndex || currentIndex >= tabs.count {
            currentIndex = max(currentIndex - 1, 0)
        }
        if pageContainer.subviews.isEmpty {
            select(min(index, tabs.count - 1), push: model.isOverviewVisible ? nil : .fromRight)
        } else {
            tabsDidChange()
        }
    }

    func reopenClosedTab() {
        guard let url = closedTabURLs.popLast() else { return }
        newTab(url: url, showAddressBar: false)
    }

    /// 分頁有變動時更新總覽並保存，重開 App 可以還原
    private func tabsDidChange() {
        model.tabs = tabs.map { BrowserModel.TabItem(id: $0.id, title: $0.title, host: $0.url?.host() ?? "", snapshot: $0.snapshot) }
        model.currentTabID = tabs[currentIndex].id
        model.currentURL = webView.url
        let settings = Settings.shared
        settings.savedTabs = tabs.compactMap { $0.url?.absoluteString }
        settings.savedTabIndex = currentIndex
    }

    // MARK: - 分頁總覽

    func showOverview() {
        hideAddressBar()
        let tab = tabs[currentIndex]
        Task {
            await tab.updateSnapshot()
            // 背景要用原尺寸的快照，動畫開頭還沒模糊時才會跟網頁本身一模一樣
            model.overviewBackdrop = try? await tab.webView.takeSnapshot(configuration: nil)
            tabsDidChange()
            model.isOverviewVisible = true
            window?.makeKey()
        }
    }

    func hideOverview() {
        guard model.isOverviewVisible else { return }
        model.isOverviewVisible = false
        window?.makeFirstResponder(webView)
    }

    func toggleOverview() {
        if model.isOverviewVisible { hideOverview() } else { showOverview() }
    }

    /// 網址列開著時，在面板下方用觸控板左右滑動切換分頁、往上滑打開分頁總覽。回傳 true 代表事件已處理
    func handleSwipe(_ event: NSEvent) -> Bool {
        guard model.isAddressBarVisible else { return false }
        guard convert(event.locationInWindow, from: nil).y < 140 else { return false }
        // 滑鼠滾輪沒有手勢階段，不算
        guard event.phase != [] || event.momentumPhase != [] else { return false }
        if event.phase == .began {
            swipeOffset = .zero
            swipeAxis = nil
            swipeHandled = false
        }
        // 手指離開後的慣性捲動不算
        if event.momentumPhase != [] { return true }

        // 換算成手指實際移動的方向，不受「自然捲動」設定影響：正值代表往右、往上
        let natural = event.isDirectionInvertedFromDevice
        swipeOffset.width += natural ? event.scrollingDeltaX : -event.scrollingDeltaX
        swipeOffset.height += natural ? -event.scrollingDeltaY : event.scrollingDeltaY

        // 先看手指主要往哪個方向動，同一次手勢只做一種事
        if swipeAxis == nil, max(abs(swipeOffset.width), abs(swipeOffset.height)) > 8 {
            swipeAxis = abs(swipeOffset.width) > abs(swipeOffset.height) ? .horizontal : .vertical
        }
        if !swipeHandled {
            switch swipeAxis {
            case .horizontal where abs(swipeOffset.width) > 40 && tabs.count > 1:
                swipeHandled = true
                // 手指往右滑看前一個分頁，跟翻頁的方向一致
                selectTab(offset: swipeOffset.width > 0 ? -1 : 1, wrap: false)
            case .vertical where swipeOffset.height > 50:
                swipeHandled = true
                showOverview()
            default:
                break
            }
        }
        if event.phase == .ended || event.phase == .cancelled {
            swipeOffset = .zero
            swipeAxis = nil
            swipeHandled = false
        }
        return true
    }

    // MARK: - 網址列

    func showAddressBar() {
        fillAddressBar()
        if model.isAddressBarVisible {
            (window?.firstResponder as? NSTextView)?.selectAll(nil)
        }
        model.isAddressBarVisible = true
        window?.makeKey()
    }

    private func fillAddressBar() {
        let current = webView.url?.absoluteString ?? tabs[currentIndex].pendingURL?.absoluteString ?? ""
        model.originalQuery = current
        model.query = current
        (window?.firstResponder as? NSTextView)?.selectAll(nil)
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

    func applyUserAgent(mobile: Bool) {
        let agent = mobile ? Self.iPhoneUserAgent : nil
        for tab in tabs where tab.webView.customUserAgent != agent {
            tab.webView.customUserAgent = agent
            // 背景分頁等下次載入時才會用到新的 User-Agent
            if tab.webView === webView, tab.webView.url != nil { tab.webView.reload() }
        }
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

    /// 載入進度、主題色只看目前分頁
    private func observeCurrentTab() {
        observations = [
            webView.observe(\.estimatedProgress, options: [.initial]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.model.progress = webView.estimatedProgress }
            },
            webView.observe(\.isLoading, options: [.initial]) { [weak self] webView, _ in
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

    // 目前分頁載入完就更新縮圖，分頁總覽才有最新畫面
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let tab = tabs.first(where: { $0.webView === webView }), webView === self.webView else { return }
        Task {
            await tab.updateSnapshot()
            tabsDidChange()
        }
    }

    // MARK: - 彈窗

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // 一般 target=_blank 連結開在新分頁；
        // 網頁用 window.open 指定大小開的（多半是 OAuth 登入）才開獨立視窗
        let isPlainLink = navigationAction.navigationType == .linkActivated && windowFeatures.width == nil
        if isPlainLink {
            newTab(showAddressBar: false).webView.load(navigationAction.request)
            return nil
        }
        let popup = PopupWindow(configuration: configuration, features: windowFeatures,
                                userAgent: webView.customUserAgent,
                                centeredOn: window?.frame ?? .zero)
        popup.onClose = { [weak self] closed in
            self?.popups.removeAll { $0 === closed }
            self?.window?.makeKey()
        }
        popups.append(popup)
        popup.show()
        return popup.webView
    }

    // MARK: - JS 對話框

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        _ = await presentDialog(.alert, message: message, frame: frame, in: webView)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await presentDialog(.confirm, message: message, frame: frame, in: webView).confirmed
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        await presentDialog(.prompt, message: prompt, defaultText: defaultText ?? "", frame: frame, in: webView).text
    }

    private func presentDialog(_ kind: BrowserModel.Dialog.Kind, message: String, defaultText: String = "",
                               frame: WKFrameInfo, in source: WKWebView) async -> (confirmed: Bool, text: String?) {
        // 面板收著時先展開，背景分頁跳出的就先切過去，不然使用者看不到對話框
        onNeedsAttention?()
        if let index = tabs.firstIndex(where: { $0.webView === source }), index != currentIndex {
            select(index)
        }
        hideAddressBar()
        hideOverview()
        model.dialogText = defaultText
        return await withCheckedContinuation { continuation in
            model.dialog = BrowserModel.Dialog(kind: kind, host: frame.securityOrigin.host, message: message) {
                continuation.resume(returning: ($0, $1))
            }
            window?.makeKey()
        }
    }

    // MARK: - 檔案上傳

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.prompt = "上傳"
        // 要蓋在浮動面板上面
        panel.level = .modalPanel

        isPickingFiles = true
        let previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        let response = await panel.begin()
        isPickingFiles = false
        // 選完檔案回到原本在用的 App，面板保持可輸入
        if let previousApp, previousApp != NSRunningApplication.current { previousApp.activate() }
        window?.makeKey()
        return response == .OK ? panel.urls : nil
    }

    // MARK: - 下載

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        navigationAction.shouldPerformDownload ? .download : .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if !navigationResponse.canShowMIMEType || (navigationResponse.isForMainFrame && disposition.hasPrefix("attachment")) {
            return .download
        }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    // MARK: - 網頁當掉

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showToast("網頁意外結束，重新載入中", symbol: "arrow.clockwise")
        webView.reload()
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

