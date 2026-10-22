import AppKit
import Carbon.HIToolbox
import SwiftUI
import WebKit

/// 設定視窗：分頁放在工具列（macOS 原生設定視窗的樣式），每頁內容是一層分組表單。
/// SwiftUI 的 TabView 放在一般視窗裡會多畫一層舊式分頁外框，跟視窗圓角和表單分組都不搭。
@MainActor
enum SettingsWindow {
    static func make(settings: Settings, bookmarks: BookmarkStore) -> NSWindow {
        let tabs = SettingsTabController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(page("一般", "gearshape", height: 440, GeneralTab(settings: settings)))
        tabs.addTabViewItem(page("外觀", "paintbrush", height: 500, AppearanceTab(settings: settings)))
        tabs.addTabViewItem(page("快捷鍵", "keyboard", height: 560, ShortcutsTab(store: .shared)))
        tabs.addTabViewItem(page("收藏", "star", height: 460, BookmarksTab(bookmarks: bookmarks)))
        tabs.addTabViewItem(page("Cookie", "externaldrive", height: 520, WebsiteDataTab()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.level = .floating
        tabs.fitWindow(to: tabs.tabViewItems[tabs.selectedTabViewItemIndex], animate: false)
        return window
    }

    private static func page(_ title: String, _ symbol: String, height: CGFloat,
                             _ view: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view.frame(width: 480, height: height))
        controller.sizingOptions = [.preferredContentSize]
        // 工具列分頁會拿這個當視窗標題
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}

/// 切換分頁時把視窗標題換成分頁名稱，並讓視窗大小剛好貼合該頁內容（左上角不動）
private final class SettingsTabController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let tabViewItem { fitWindow(to: tabViewItem, animate: true) }
    }

    func fitWindow(to item: NSTabViewItem, animate: Bool) {
        guard let window = view.window, let content = item.viewController?.preferredContentSize,
              content != .zero else { return }
        window.title = item.label
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animate)
    }
}

// MARK: - 一般

private struct GeneralTab: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section("位置") {
                Picker("螢幕", selection: $settings.displayID) {
                    Text("自動（主螢幕）").tag(0)
                    ForEach(NSScreen.screens, id: \.displayID) { screen in
                        Text(screen.localizedName).tag(screen.displayID)
                    }
                }
                Picker("貼齊邊緣", selection: $settings.edge) {
                    ForEach(DockEdge.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("垂直位置", selection: $settings.verticalAlign) {
                    ForEach(VerticalAlign.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("觸發") {
                SliderRow(title: "展開延遲", value: $settings.expandDelay, range: 0...1.5, step: 0.05, format: "%.2f 秒")
                SliderRow(title: "收起延遲", value: $settings.collapseDelay, range: 0...3, step: 0.1, format: "%.1f 秒")
            }

            Section("網頁") {
                Toggle("使用手機版網頁", isOn: $settings.mobileUserAgent)
                TextField("首頁", text: $settings.homeURL)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 外觀

private struct AppearanceTab: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section("動畫") {
                SliderRow(title: "動畫時長", value: $settings.animationDuration, range: 0.15...0.8, step: 0.01, format: "%.2f 秒")
                SliderRow(title: "回彈強度", value: $settings.bounce, range: 0...2, step: 0.1, format: "%.1f")
            }

            Section("視窗") {
                SliderRow(title: "寬度", value: $settings.width, range: 280...1000, step: 10, format: "%.0f pt")
                SliderRow(title: "高度", value: $settings.height, range: 360...1400, step: 10, format: "%.0f pt")
                SliderRow(title: "圓角", value: $settings.cornerRadius, range: 8...48, step: 1, format: "%.0f pt")
                SliderRow(title: "陰影強度", value: $settings.shadowStrength, range: 0...1, step: 0.05, format: "%.2f")
                Button("還原為手機尺寸") { settings.resetToPhoneSize() }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 快捷鍵

private struct ShortcutsTab: View {
    @ObservedObject var store: ShortcutStore
    @StateObject private var recorder = ShortcutRecorder()

    var body: some View {
        Form {
            Section {
                ForEach(Shortcut.allCases) { shortcut in
                    LabeledContent(shortcut.title) {
                        if shortcut.isCustomizable {
                            ShortcutField(shortcut: shortcut, store: store, recorder: recorder)
                        } else {
                            Text(shortcut.keys).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text("先點一下面板，快捷鍵才會生效。").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Button("全部還原預設") {
                    recorder.stop()
                    store.resetAll()
                }
                .disabled(store.custom.isEmpty)
            }
        }
        .formStyle(.grouped)
        .onDisappear { recorder.stop() }
    }
}

private struct ShortcutField: View {
    let shortcut: Shortcut
    @ObservedObject var store: ShortcutStore
    @ObservedObject var recorder: ShortcutRecorder

    private var isRecording: Bool { recorder.recording == shortcut }

    var body: some View {
        HStack(spacing: 8) {
            if isRecording, let conflict = recorder.conflict {
                Text("已用於「\(conflict)」").font(.caption).foregroundStyle(.red)
            }
            Button {
                isRecording ? recorder.stop() : recorder.start(shortcut)
            } label: {
                Text(isRecording ? "按下新的組合" : store.combo(for: shortcut)?.display ?? "—")
                    .frame(minWidth: 84)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            if store.isCustomized(shortcut) {
                Button { store.reset(shortcut) } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("還原預設（\(shortcut.defaultCombo?.display ?? "")）")
            }
        }
    }
}

/// 錄製快捷鍵：一次只錄一個，Esc 取消；要帶 ⌘、⌃ 或 ⌥，跟別的用途重複時不採用
@MainActor
private final class ShortcutRecorder: ObservableObject {
    @Published private(set) var recording: Shortcut?
    @Published private(set) var conflict: String?
    private var monitor: Any?

    func start(_ shortcut: Shortcut) {
        stop()
        recording = shortcut
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.record(event) ?? false }
            return consumed ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        conflict = nil
    }

    private func record(_ event: NSEvent) -> Bool {
        guard let shortcut = recording else { return false }
        let combo = KeyCombo(event)
        if combo.flags.isEmpty, Int(event.keyCode) == kVK_Escape {
            stop()
            return true
        }
        guard !combo.flags.isDisjoint(with: [.command, .control, .option]) else {
            NSSound.beep()
            return true
        }
        if let other = ShortcutStore.shared.conflict(for: combo, excluding: shortcut) {
            conflict = other
            NSSound.beep()
            return true
        }
        ShortcutStore.shared.set(combo, for: shortcut)
        stop()
        return true
    }
}

// MARK: - 收藏

private struct BookmarksTab: View {
    @ObservedObject var bookmarks: BookmarkStore

    var body: some View {
        if bookmarks.items.isEmpty {
            ContentUnavailableView("還沒有收藏", systemImage: "star",
                                   description: Text("在面板裡按 ⌘D 收藏目前的網頁"))
        } else {
            Form {
                Section {
                    ForEach(bookmarks.items) { bookmark in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.title).lineLimit(1)
                                Text(bookmark.url).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button(role: .destructive) { bookmarks.remove(bookmark) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("移除")
                        }
                    }
                    .onMove { bookmarks.move(from: $0, to: $1) }
                } footer: {
                    Text("拖曳可以調整順序").font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}

// MARK: - Cookie 與網站資料

private struct WebsiteDataTab: View {
    private struct Site: Identifiable {
        let record: WKWebsiteDataRecord
        var id: String { record.displayName }
        var hasCookies: Bool { record.dataTypes.contains(WKWebsiteDataTypeCookies) }
    }

    @State private var sites: [Site] = []
    @State private var filter = ""
    @State private var loading = true
    @State private var confirmClearAll = false

    private let store = WKWebsiteDataStore.default()

    private var filtered: [Site] {
        filter.isEmpty ? sites : sites.filter { $0.id.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        Form {
            Section {
                TextField("搜尋網站", text: $filter)
            } footer: {
                Text("Cookie 和登入狀態會一直保存在這台 Mac 上，重開 App 也不用重新登入。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if loading {
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                } else if filtered.isEmpty {
                    Text("沒有網站資料").foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { site in
                        HStack {
                            Image(systemName: site.hasCookies ? "lock.shield" : "doc")
                                .foregroundStyle(.secondary)
                            Text(site.id)
                            Spacer()
                            if site.hasCookies {
                                Text("Cookie").font(.caption).foregroundStyle(.secondary)
                            }
                            Button(role: .destructive) { Task { await remove(site) } } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("清除這個網站的資料（會登出）")
                        }
                    }
                }
            } header: {
                HStack {
                    Text("\(sites.count) 個網站")
                    Spacer()
                    Button("重新整理") { Task { await reload() } }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            Section {
                Button("清除全部網站資料…", role: .destructive) { confirmClearAll = true }
                    .disabled(sites.isEmpty)
            }
        }
        .formStyle(.grouped)
        .task { await reload() }
        .confirmationDialog("要清除所有網站的 Cookie 和資料嗎？", isPresented: $confirmClearAll) {
            Button("清除全部", role: .destructive) { Task { await clearAll() } }
        } message: {
            Text("所有網站都會被登出。")
        }
    }

    private func reload() async {
        loading = true
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        sites = records.map(Site.init).sorted { $0.id < $1.id }
        loading = false
    }

    private func remove(_ site: Site) async {
        await store.removeData(ofTypes: site.record.dataTypes, for: [site.record])
        await reload()
    }

    private func clearAll() async {
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        await reload()
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step)
                    .frame(width: 180)
                Text(String(format: format, value))
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }
}
