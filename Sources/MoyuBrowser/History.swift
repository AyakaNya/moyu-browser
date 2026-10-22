import Foundation

struct HistoryEntry: Codable, Hashable {
    var url: String
    var title: String
    var visitCount: Int
    var lastVisit: Date
}

/// 瀏覽紀錄，只存在本機（Application Support），給網址補全與聯想用
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    /// 超過這個數量時，丟掉最久沒去的
    private static let limit = 3000

    @Published private(set) var entries: [String: HistoryEntry] = [:]
    private var saveTask: Task<Void, Never>?

    private static var fileURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoyuBrowser", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("History.json")
    }

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = Dictionary(saved.map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })
        }
    }

    func recordVisit(url: URL, title: String) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        let key = url.absoluteString
        var entry = entries[key] ?? HistoryEntry(url: key, title: "", visitCount: 0, lastVisit: .now)
        entry.visitCount += 1
        entry.lastVisit = .now
        if !title.isEmpty { entry.title = title }
        entries[key] = entry
        if entries.count > Self.limit {
            let oldest = entries.values.sorted { $0.lastVisit < $1.lastVisit }.prefix(entries.count - Self.limit)
            oldest.forEach { entries[$0.url] = nil }
        }
        scheduleSave()
    }

    func clear() {
        entries = [:]
        scheduleSave()
    }

    /// 連續瀏覽時合併成一次寫檔
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = Array(entries.values)
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
