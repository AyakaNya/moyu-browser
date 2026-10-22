import AppKit
import WebKit

/// 把網頁下載存到「下載項目」資料夾，並記住這次執行期間最近下載的檔案。
@MainActor
final class DownloadManager: NSObject, WKDownloadDelegate {
    static let shared = DownloadManager()

    /// 最近下載的檔案，新的在前
    private(set) var recent: [URL] = []
    /// 下載開始、完成、失敗時通知面板顯示提示
    var onEvent: ((String, String) -> Void)?

    private var destinations: [ObjectIdentifier: URL] = [:]

    static var folder: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        let destination = uniqueURL(for: suggestedFilename.isEmpty ? "未命名" : suggestedFilename)
        destinations[ObjectIdentifier(download)] = destination
        onEvent?("開始下載 \(destination.lastPathComponent)", "arrow.down.circle")
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        recent.removeAll { $0 == url }
        recent.insert(url, at: 0)
        recent = Array(recent.prefix(10))
        // 讓 Dock 上的「下載項目」堆疊彈一下
        DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: url.path)
        onEvent?("已下載 \(url.lastPathComponent)", "checkmark.circle")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let name = destinations.removeValue(forKey: ObjectIdentifier(download))?.lastPathComponent ?? "檔案"
        onEvent?("\(name) 下載失敗", "xmark.octagon")
    }

    /// 同名檔案已存在時加上「 (2)」「 (3)」…
    private func uniqueURL(for filename: String) -> URL {
        let base = Self.folder.appendingPathComponent(filename)
        let fm = FileManager.default
        guard fm.fileExists(atPath: base.path) else { return base }
        let stem = base.deletingPathExtension().lastPathComponent
        let ext = base.pathExtension
        for n in 2... {
            let name = ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)"
            let candidate = Self.folder.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return base
    }
}
