import Foundation

/// 設定環境變數 MOYU_DEBUG=1 執行時，把除錯訊息印到 stderr
enum Debug {
    static let enabled = ProcessInfo.processInfo.environment["MOYU_DEBUG"] != nil

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write((message() + "\n").data(using: .utf8)!)
    }
}
