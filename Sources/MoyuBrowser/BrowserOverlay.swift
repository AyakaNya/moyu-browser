import AppKit
import SwiftUI

/// 網頁上方那層 SwiftUI 介面（網址列、收藏建議、載入進度、提示訊息）的狀態
@MainActor
final class BrowserModel: ObservableObject {
    struct Toast: Equatable, Identifiable {
        let id = UUID()
        let text: String
        let symbol: String
    }

    /// 網頁呼叫 alert / confirm / prompt 時顯示的對話框
    struct Dialog: Identifiable {
        enum Kind { case alert, confirm, prompt }
        let id = UUID()
        let kind: Kind
        let host: String
        let message: String
        let finish: (_ confirmed: Bool, _ text: String?) -> Void
    }

    @Published var isAddressBarVisible = false
    @Published var query = ""
    /// 叫出網址列時填入的原始網址；query 跟它不同就代表使用者開始輸入了
    @Published var originalQuery = ""
    @Published var progress: Double = 0
    @Published var isLoading = false
    @Published var currentURL: URL?
    @Published var toast: Toast?
    /// 網頁是深色的嗎；網址列和底下的毛玻璃跟著網頁明暗走，而不是跟系統
    @Published var pageIsDark = false
    @Published var dialog: Dialog?
    @Published var dialogText = ""

    var queryEdited: Bool { query != originalQuery }

    var onSubmit: (String) -> Void = { _ in }
    var onOpen: (URL) -> Void = { _ in }
    var onDismiss: () -> Void = {}
    var onToggleBookmark: () -> Void = {}

    /// 關掉對話框並把結果回傳給網頁；每個對話框只會回傳一次
    func finishDialog(confirmed: Bool) {
        guard let dialog else { return }
        self.dialog = nil
        dialog.finish(confirmed, confirmed ? dialogText : nil)
    }

    func showToast(_ text: String, symbol: String) {
        let toast = Toast(text: text, symbol: symbol)
        self.toast = toast
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            if self?.toast?.id == toast.id { self?.toast = nil }
        }
    }
}

/// 沒有叫出網址列時完全不攔截滑鼠，讓點擊直接落到網頁上
final class OverlayHostingView: NSHostingView<BrowserOverlay> {
    var isInteractive: () -> Bool = { false }

    required init(rootView: BrowserOverlay) {
        super.init(rootView: rootView)
    }

    @MainActor required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isInteractive() ? super.hitTest(point) : nil
    }
}

struct BrowserOverlay: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var bookmarks: BookmarkStore

    @FocusState private var fieldFocused: Bool
    @State private var highlighted: Int?

    private let rowHeight: CGFloat = 44

    private var suggestions: [Bookmark] {
        model.queryEdited ? bookmarks.matching(model.query) : bookmarks.items
    }

    var body: some View {
        ZStack {
            if model.isAddressBarVisible {
                // 透明的一層，只負責「點旁邊收回」
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.onDismiss() }
                    .transition(.opacity)
            }

            if let dialog = model.dialog {
                Color.black.opacity(0.08)
                    .transition(.opacity)
                DialogCard(model: model, dialog: dialog)
                    .environment(\.colorScheme, model.pageIsDark ? .dark : .light)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .zIndex(1)
            }

            VStack(spacing: 0) {
                progressBar
                toastView
                Spacer(minLength: 0)
                if model.isAddressBarVisible {
                    addressArea
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: model.isAddressBarVisible)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.toast)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.dialog?.id)
        .onChange(of: model.query) { highlighted = nil }
    }

    // MARK: - 載入進度與提示

    private var progressBar: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(Color.accentColor)
                .frame(width: geometry.size.width * model.progress, height: 3)
                .animation(.easeOut(duration: 0.25), value: model.progress)
        }
        .frame(height: 3)
        .opacity(model.isLoading ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: model.isLoading)
    }

    @ViewBuilder
    private var toastView: some View {
        if let toast = model.toast {
            Label(toast.text, systemImage: toast.symbol)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 10)
                .id(toast.id)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - 網址列

    private var addressArea: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                suggestionCard
                addressCapsule
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .background { frostedBackdrop }
        .environment(\.colorScheme, model.pageIsDark ? .dark : .light)
    }

    /// 網址列與收藏後方的毛玻璃：剛好蓋住網址區，往上多延伸一小段淡出
    private var frostedBackdrop: some View {
        let fade: CGFloat = 36
        return FrostedBackdrop(dark: model.pageIsDark)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: fade)
                    Color.black
                }
            }
            .padding(.top, -fade)
    }

    private var addressCapsule: some View {
        let isBookmarked = bookmarks.contains(model.currentURL)
        return HStack(spacing: 10) {
            Image(systemName: model.queryEdited ? "magnifyingglass" : "globe")
                .foregroundStyle(.secondary)
            TextField("搜尋或輸入網址", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($fieldFocused)
                .onSubmit(submit)
                .onExitCommand { model.onDismiss() }
                .onKeyPress(.downArrow) { moveHighlight(1); return .handled }
                .onKeyPress(.upArrow) { moveHighlight(-1); return .handled }
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            Button(action: model.onToggleBookmark) {
                Image(systemName: isBookmarked ? "star.fill" : "star")
                    .foregroundStyle(isBookmarked ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .help("收藏目前的網頁（⌘D）")
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .glassEffect(.regular.interactive(), in: .capsule)
        .onAppear {
            // 輸入框要等放進視窗後才能拿焦點；拿到之後再全選，
            // 直接對 nil 送 selectAll 會在焦點還在網頁時選到整頁
            DispatchQueue.main.async {
                fieldFocused = true
                DispatchQueue.main.async {
                    (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
                }
            }
        }
    }

    private var suggestionCard: some View {
        let items = Array(suggestions.prefix(50))
        return VStack(alignment: .leading, spacing: 0) {
            Text(model.queryEdited ? "符合的收藏" : "收藏")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            if items.isEmpty {
                Text(bookmarks.items.isEmpty ? "還沒有收藏，按 ⌘D 收藏目前的網頁" : "沒有符合的收藏，按 Return 直接前往")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, bookmark in
                            BookmarkRow(bookmark: bookmark, highlighted: highlighted == index)
                                .frame(height: rowHeight)
                                .onTapGesture { open(bookmark) }
                                .contextMenu {
                                    Button("移除收藏", role: .destructive) { bookmarks.remove(bookmark) }
                                }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(CGFloat(items.count) * rowHeight + 6, 300))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func moveHighlight(_ delta: Int) {
        let count = min(suggestions.count, 50)
        guard count > 0 else { return }
        if let current = highlighted {
            highlighted = (current + delta + count) % count
        } else {
            highlighted = delta > 0 ? 0 : count - 1
        }
    }

    private func submit() {
        if let index = highlighted, index < suggestions.count {
            open(suggestions[index])
        } else {
            model.onSubmit(model.query)
        }
    }

    private func open(_ bookmark: Bookmark) {
        if let url = URL(string: bookmark.url) { model.onOpen(url) }
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark
    let highlighted: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Text(String(bookmark.title.prefix(1)).uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(avatarColor))
            VStack(alignment: .leading, spacing: 1) {
                Text(bookmark.title).font(.system(size: 13)).lineLimit(1)
                Text(bookmark.host).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(highlighted ? 0.14 : hovering ? 0.08 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var avatarColor: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .red]
        let hash = bookmark.host.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}

/// 毛玻璃底：用標題列材質（給「內容捲到底下」用的），明暗由網頁決定
private struct FrostedBackdrop: NSViewRepresentable {
    let dark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .headerView
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}

/// Liquid Glass 樣式的 alert / confirm / prompt
private struct DialogCard: View {
    @ObservedObject var model: BrowserModel
    let dialog: BrowserModel.Dialog
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text(dialog.host.isEmpty ? "網頁訊息" : dialog.host)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(dialog.message)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .textSelection(.enabled)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 220)
            .fixedSize(horizontal: false, vertical: true)

            if dialog.kind == .prompt {
                TextField("", text: $model.dialogText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .focused($fieldFocused)
                    .onAppear { DispatchQueue.main.async { fieldFocused = true } }
            }

            HStack(spacing: 10) {
                if dialog.kind != .alert {
                    Button("取消") { model.finishDialog(confirmed: false) }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
                Button("好") { model.finishDialog(confirmed: true) }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(maxWidth: 300)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(24)
    }
}
