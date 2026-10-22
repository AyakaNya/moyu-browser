import Foundation

enum DockEdge: String, CaseIterable, Identifiable {
    case left, right

    var id: String { rawValue }
    var title: String { self == .left ? "左側" : "右側" }
}

enum VerticalAlign: String, CaseIterable, Identifiable {
    case top, center, bottom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .top: "上方"
        case .center: "中間"
        case .bottom: "下方"
        }
    }
}

extension Notification.Name {
    static let settingsDidChange = Notification.Name("MoyuSettingsDidChange")
}

/// 所有使用者設定，存在 UserDefaults；任何一項改變都會發出 `.settingsDidChange`。
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    static let phoneSize = CGSize(width: 390, height: 844)
    static let defaultHomeURL = "https://www.google.com"

    private let defaults = UserDefaults.standard

    @Published var edge: DockEdge { didSet { save(edge.rawValue, "edge") } }
    @Published var verticalAlign: VerticalAlign { didSet { save(verticalAlign.rawValue, "verticalAlign") } }
    /// 滑鼠停在邊緣多久才展開（秒）
    @Published var expandDelay: Double { didSet { save(expandDelay, "expandDelay") } }
    /// 滑鼠離開面板多久才收起（秒）
    @Published var collapseDelay: Double { didSet { save(collapseDelay, "collapseDelay") } }
    @Published var animationDuration: Double { didSet { save(animationDuration, "animationDuration") } }
    /// 展開時的回彈幅度，0 為無回彈
    @Published var bounce: Double { didSet { save(bounce, "bounce") } }
    @Published var width: Double { didSet { save(width, "width") } }
    @Published var height: Double { didSet { save(height, "height") } }
    @Published var mobileUserAgent: Bool { didSet { save(mobileUserAgent, "mobileUserAgent") } }
    @Published var homeURL: String { didSet { save(homeURL, "homeURL") } }
    /// 要貼在哪個螢幕；0 代表自動（主螢幕）
    @Published var displayID: Int { didSet { save(displayID, "displayID") } }
    @Published var cornerRadius: Double { didSet { save(cornerRadius, "cornerRadius") } }
    /// 陰影強度，0～1
    @Published var shadowStrength: Double { didSet { save(shadowStrength, "shadowStrength") } }

    /// 上次瀏覽的網址；變動很頻繁，所以不發通知。
    var lastURL: String? {
        get { defaults.string(forKey: "lastURL") }
        set { defaults.set(newValue, forKey: "lastURL") }
    }

    private init() {
        let d = UserDefaults.standard
        edge = DockEdge(rawValue: d.string(forKey: "edge") ?? "") ?? .left
        verticalAlign = VerticalAlign(rawValue: d.string(forKey: "verticalAlign") ?? "") ?? .bottom
        expandDelay = d.object(forKey: "expandDelay") as? Double ?? 0.15
        collapseDelay = d.object(forKey: "collapseDelay") as? Double ?? 0.5
        animationDuration = d.object(forKey: "animationDuration") as? Double ?? 0.38
        bounce = d.object(forKey: "bounce") as? Double ?? 1.0
        width = d.object(forKey: "width") as? Double ?? Self.phoneSize.width
        height = d.object(forKey: "height") as? Double ?? Self.phoneSize.height
        mobileUserAgent = d.object(forKey: "mobileUserAgent") as? Bool ?? true
        homeURL = d.string(forKey: "homeURL") ?? Self.defaultHomeURL
        displayID = d.integer(forKey: "displayID")
        cornerRadius = d.object(forKey: "cornerRadius") as? Double ?? 30
        shadowStrength = d.object(forKey: "shadowStrength") as? Double ?? 0.7
    }

    func resetToPhoneSize() {
        width = Self.phoneSize.width
        height = Self.phoneSize.height
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .settingsDidChange, object: self)
    }
}
