import Foundation

/// 搜尋引擎：網址範本裡的 %s 會換成搜尋關鍵字
struct SearchEngine: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var searchURL: String
    /// 取得搜尋建議的網址，回傳 OpenSearch 格式的 JSON：["關鍵字", ["建議一", "建議二", …]]
    var suggestURL: String?
    /// 在網址列輸入「縮寫 關鍵字」就直接用這個引擎搜尋，例如「yt 貓咪」
    var keyword: String

    static let builtIn: [SearchEngine] = [
        SearchEngine(id: "google", name: "Google",
                     searchURL: "https://www.google.com/search?q=%s",
                     suggestURL: "https://suggestqueries.google.com/complete/search?client=firefox&q=%s",
                     keyword: "g"),
        SearchEngine(id: "bing", name: "Bing",
                     searchURL: "https://www.bing.com/search?q=%s",
                     suggestURL: "https://api.bing.com/osjson.aspx?query=%s",
                     keyword: "b"),
        SearchEngine(id: "duckduckgo", name: "DuckDuckGo",
                     searchURL: "https://duckduckgo.com/?q=%s",
                     suggestURL: "https://duckduckgo.com/ac/?q=%s&type=list",
                     keyword: "d"),
        SearchEngine(id: "baidu", name: "百度",
                     searchURL: "https://www.baidu.com/s?wd=%s",
                     suggestURL: "https://suggestion.baidu.com/su?wd=%s&action=opensearch&ie=utf-8",
                     keyword: "bd"),
        SearchEngine(id: "perplexity", name: "Perplexity",
                     searchURL: "https://www.perplexity.ai/search?q=%s",
                     suggestURL: nil,
                     keyword: "p"),
    ]

    var isBuiltIn: Bool { Self.builtIn.contains { $0.id == id } }

    func url(for query: String, template: String? = nil) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: Self.queryAllowed) ?? query
        return URL(string: (template ?? searchURL).replacingOccurrences(of: "%s", with: encoded))
    }

    /// 網址查詢字串裡要保留的字元；& + = # 這些會被當成分隔符號，要編碼
    private static let queryAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=#?")
        return set
    }()
}

/// 預設搜尋引擎與自訂搜尋引擎，存在 UserDefaults
@MainActor
final class SearchEngineStore: ObservableObject {
    static let shared = SearchEngineStore()

    @Published private(set) var custom: [SearchEngine] = []
    @Published var defaultID: String { didSet { UserDefaults.standard.set(defaultID, forKey: "searchEngine") } }
    /// 打字時向搜尋引擎取得建議關鍵字（會把輸入的文字傳給它）
    @Published var suggestionsEnabled: Bool {
        didSet { UserDefaults.standard.set(suggestionsEnabled, forKey: "searchSuggestions") }
    }

    private let customKey = "customSearchEngines"

    private init() {
        let defaults = UserDefaults.standard
        defaultID = defaults.string(forKey: "searchEngine") ?? "google"
        suggestionsEnabled = defaults.object(forKey: "searchSuggestions") as? Bool ?? true
        if let data = defaults.data(forKey: customKey),
           let saved = try? JSONDecoder().decode([SearchEngine].self, from: data) {
            custom = saved
        }
    }

    var all: [SearchEngine] { SearchEngine.builtIn + custom }

    var current: SearchEngine {
        all.first { $0.id == defaultID } ?? SearchEngine.builtIn[0]
    }

    /// 文字要怎麼搜尋：開頭是某個引擎的縮寫加空白，就用那個引擎搜尋後面的字
    func searchURL(for text: String) -> URL? {
        let parts = text.split(separator: " ", maxSplits: 1)
        if parts.count == 2, let engine = all.first(where: { $0.keyword.lowercased() == parts[0].lowercased() }) {
            return engine.url(for: String(parts[1]))
        }
        return current.url(for: text)
    }

    /// 這個縮寫是否已經被其他引擎用掉
    func keywordTaken(_ keyword: String, except id: String? = nil) -> Bool {
        let keyword = keyword.lowercased()
        return all.contains { $0.id != id && $0.keyword.lowercased() == keyword }
    }

    func add(name: String, searchURL: String, keyword: String) {
        custom.append(SearchEngine(id: UUID().uuidString, name: name, searchURL: searchURL,
                                   suggestURL: nil, keyword: keyword))
        save()
    }

    func remove(_ engine: SearchEngine) {
        custom.removeAll { $0.id == engine.id }
        if defaultID == engine.id { defaultID = SearchEngine.builtIn[0].id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: customKey)
        }
    }
}
