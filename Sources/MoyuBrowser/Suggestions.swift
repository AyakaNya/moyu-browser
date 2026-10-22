import Foundation

/// 網址列下方的一筆建議：要去的網頁，或要搜尋的關鍵字
enum SuggestionItem: Identifiable, Hashable {
    case page(title: String, url: String, bookmarked: Bool)
    case search(String)

    var id: String {
        switch self {
        case .page(_, let url, _): "page:" + url
        case .search(let text): "search:" + text
        }
    }
}

/// 網址列的聯想與補全：收藏和瀏覽紀錄依常用程度排序，再加上搜尋引擎的建議關鍵字
@MainActor
final class SuggestionProvider: ObservableObject {
    /// 網址列裡直接補上的網址：text 是顯示的文字（例如 youtube.com），url 是按 Return 要開的網址
    struct Completion: Equatable {
        let text: String
        let url: String
    }

    @Published private(set) var items: [SuggestionItem] = []
    private(set) var completion: Completion?

    private var localItems: [SuggestionItem] = []
    private var remoteItems: [SuggestionItem] = []
    private var fetchTask: Task<Void, Never>?
    private var query = ""

    private struct Candidate {
        let url: String
        let title: String
        let score: Double
        let bookmarked: Bool
    }

    func update(query newQuery: String) {
        let trimmed = newQuery.trimmingCharacters(in: .whitespaces)
        guard trimmed != query else { return }
        query = trimmed
        fetchTask?.cancel()
        remoteItems = []
        guard !trimmed.isEmpty else {
            completion = nil
            localItems = []
            publish()
            return
        }
        localItems = localMatches(for: trimmed)
        publish()
        fetchRemote(for: trimmed)
    }

    /// 打字時呼叫：回傳要顯示在網址列裡的完整文字（開頭就是使用者打的字），沒有可以補的就回傳 nil
    func inlineCompletion(for typed: String) -> String? {
        let typedLower = typed.lowercased()
        guard !typedLower.isEmpty, !typedLower.contains(" "), !typedLower.contains("://") else {
            completion = nil
            return nil
        }
        let wantsPath = typedLower.contains("/")
        var best: (text: String, url: String, score: Double)?
        for candidate in candidates() {
            guard let parsed = URL(string: candidate.url), let hostName = parsed.host()?.lowercased() else { continue }
            // 有指定連接埠（例如 localhost:3000）就一起補上
            let host = parsed.port.map { "\(hostName):\($0)" } ?? hostName
            // 打到「/」之後就補完整網址，否則只補網域
            let full = Self.stripped(candidate.url)
            let options = wantsPath ? [Self.stripWWW(full), full] : [Self.stripWWW(host), host]
            guard let match = options.first(where: { $0.hasPrefix(typedLower) && $0 != typedLower }) else { continue }
            if best == nil || candidate.score > best!.score {
                let target = wantsPath ? candidate.url : "\(parsed.scheme ?? "https")://\(host)/"
                best = (match, target, candidate.score)
            }
        }
        guard let best else {
            completion = nil
            return nil
        }
        // 保留使用者自己打的大小寫，後面接上補的部分
        let shown = typed + best.text.dropFirst(typed.count)
        completion = Completion(text: shown, url: best.url)
        return shown
    }

    // MARK: - 本機：收藏與瀏覽紀錄

    private func candidates() -> [Candidate] {
        var byURL: [String: Candidate] = [:]
        let now = Date.now
        for entry in HistoryStore.shared.entries.values {
            // 去得越多、越近期的越前面
            let days = now.timeIntervalSince(entry.lastVisit) / 86_400
            let score = Double(entry.visitCount) + max(0, 10 - days)
            byURL[entry.url] = Candidate(url: entry.url, title: entry.title, score: score, bookmarked: false)
        }
        for bookmark in BookmarkStore.shared.items {
            let previous = byURL[bookmark.url]?.score ?? 0
            byURL[bookmark.url] = Candidate(url: bookmark.url, title: bookmark.title, score: previous + 20, bookmarked: true)
        }
        return Array(byURL.values)
    }

    private func localMatches(for query: String) -> [SuggestionItem] {
        let q = query.lowercased()
        let matches = candidates().compactMap { candidate -> (Candidate, Double)? in
            let url = Self.stripped(candidate.url)
            let title = candidate.title.lowercased()
            guard url.contains(q) || title.contains(q) else { return nil }
            // 網址開頭就對上的排最前面
            let bonus = url.hasPrefix(q) || Self.stripWWW(url).hasPrefix(q) ? 50.0 : 0
            return (candidate, candidate.score + bonus)
        }
        return matches.sorted { $0.1 > $1.1 }.prefix(4).map {
            .page(title: $0.0.title.isEmpty ? Self.stripped($0.0.url) : $0.0.title, url: $0.0.url, bookmarked: $0.0.bookmarked)
        }
    }

    // MARK: - 搜尋引擎建議

    private func fetchRemote(for query: String) {
        let store = SearchEngineStore.shared
        guard store.suggestionsEnabled, let template = store.current.suggestURL,
              let url = store.current.url(for: query, template: template) else { return }
        fetchTask = Task { [weak self] in
            // 停頓一下再送，不要每打一個字就送一次
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  !Task.isCancelled else { return }
            let suggestions = Self.parseOpenSearch(data)
            guard let self, self.query == query else { return }
            let lowered = query.lowercased()
            self.remoteItems = suggestions
                .filter { $0.lowercased() != lowered }
                .prefix(5)
                .map { .search($0) }
            self.publish()
        }
    }

    /// OpenSearch 格式：["關鍵字", ["建議一", "建議二", …]]；百度可能回 GB18030 編碼
    private static func parseOpenSearch(_ data: Data) -> [String] {
        var json = try? JSONSerialization.jsonObject(with: data)
        if json == nil {
            let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
            if let text = String(data: data, encoding: gb18030), let utf8 = text.data(using: .utf8) {
                json = try? JSONSerialization.jsonObject(with: utf8)
            }
        }
        guard let array = json as? [Any], array.count > 1, let list = array[1] as? [Any] else { return [] }
        return list.compactMap { $0 as? String }
    }

    private func publish() {
        var seen = Set<String>()
        items = (localItems + remoteItems).filter { seen.insert($0.id).inserted }
    }

    // MARK: - 網址整理

    /// 去掉 https://、結尾的「/」，用來比對與顯示
    static func stripped(_ url: String) -> String {
        var text = url.lowercased()
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        if text.hasSuffix("/") { text.removeLast() }
        return text
    }

    static func stripWWW(_ text: String) -> String {
        text.hasPrefix("www.") ? String(text.dropFirst(4)) : text
    }
}
