import Foundation

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var url: String

    var host: String { URL(string: url)?.host() ?? url }
}

/// 網址收藏，以 JSON 存在 UserDefaults。
@MainActor
final class BookmarkStore: ObservableObject {
    static let shared = BookmarkStore()

    @Published private(set) var items: [Bookmark] = []

    private let key = "bookmarks"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Bookmark].self, from: data) {
            items = saved
        }
    }

    func contains(_ url: URL?) -> Bool {
        guard let url else { return false }
        return items.contains { $0.url == url.absoluteString }
    }

    /// 已收藏就移除，否則加入；回傳之後是否為收藏狀態
    @discardableResult
    func toggle(title: String, url: URL) -> Bool {
        if let index = items.firstIndex(where: { $0.url == url.absoluteString }) {
            items.remove(at: index)
            save()
            return false
        }
        let name = title.isEmpty ? (url.host() ?? url.absoluteString) : title
        items.insert(Bookmark(title: name, url: url.absoluteString), at: 0)
        save()
        return true
    }

    func remove(_ bookmark: Bookmark) {
        items.removeAll { $0.id == bookmark.id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func matching(_ query: String) -> [Bookmark] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.title.lowercased().contains(q) || $0.url.lowercased().contains(q) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
