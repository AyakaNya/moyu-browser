import AppKit
import SwiftUI
import WebKit

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var bookmarks: BookmarkStore

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("一般", systemImage: "gearshape") }
            AppearanceTab(settings: settings)
                .tabItem { Label("外觀", systemImage: "paintbrush") }
            BookmarksTab(bookmarks: bookmarks)
                .tabItem { Label("收藏", systemImage: "star") }
            WebsiteDataTab()
                .tabItem { Label("Cookie", systemImage: "externaldrive") }
        }
        .frame(width: 480, height: 560)
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

// MARK: - 收藏

private struct BookmarksTab: View {
    @ObservedObject var bookmarks: BookmarkStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if bookmarks.items.isEmpty {
                ContentUnavailableView("還沒有收藏", systemImage: "star",
                                       description: Text("在面板裡按 ⌘D 收藏目前的網頁"))
            } else {
                List {
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
                }
                Text("拖曳可以調整順序").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Cookie 和登入狀態會一直保存在這台 Mac 上，重開 App 也不用重新登入。")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("搜尋網站", text: $filter).textFieldStyle(.roundedBorder)
                Button("重新整理") { Task { await reload() } }
            }

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView("沒有網站資料", systemImage: "externaldrive")
            } else {
                List(filtered) { site in
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

            HStack {
                Text("\(sites.count) 個網站").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("清除全部…", role: .destructive) { confirmClearAll = true }
                    .disabled(sites.isEmpty)
            }
        }
        .padding()
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
