import AppKit
import Carbon.HIToolbox

/// 一組快捷鍵：實體按鍵位置（keyCode）加上修飾鍵。
/// 用 keyCode 而不是字元比對，切到注音等輸入法時字元會變成「ㄠ」之類，不能拿來比對。
struct KeyCombo: Codable, Hashable {
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    let keyCode: UInt16
    let modifiers: UInt

    init(keyCode: Int, _ modifiers: NSEvent.ModifierFlags) {
        self.keyCode = UInt16(keyCode)
        self.modifiers = modifiers.intersection(Self.relevantModifiers).rawValue
    }

    init(_ event: NSEvent) {
        self.init(keyCode: Int(event.keyCode), event.modifierFlags)
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// 例如「⌘⇧T」，修飾鍵照 macOS 選單的順序排
    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// 用英文鍵盤配置算出按鍵上的字，注音輸入法開著時也顯示「L」而不是「ㄠ」
    static func keyName(_ keyCode: UInt16) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer in
            UCKeyTranslate(buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress, keyCode,
                           UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// 面板裡可以用快捷鍵觸發的功能
enum Shortcut: String, CaseIterable, Identifiable {
    case addressBar, newTab, closeTab, reopenTab, previousTab, nextTab, tabNumber, overview
    case bookmark, back, forward, reload, home, copyURL
    case zoomIn, zoomOut, zoomReset, pin, hide, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addressBar: "叫出 / 收回網址列"
        case .newTab: "新增分頁"
        case .closeTab: "關閉分頁"
        case .reopenTab: "重新打開關閉的分頁"
        case .previousTab: "上一個分頁"
        case .nextTab: "下一個分頁"
        case .tabNumber: "切到第幾個分頁"
        case .overview: "所有分頁"
        case .bookmark: "收藏 / 取消收藏"
        case .back: "上一頁"
        case .forward: "下一頁"
        case .reload: "重新整理 / 停止"
        case .home: "回首頁"
        case .copyURL: "拷貝網址"
        case .zoomIn: "放大"
        case .zoomOut: "縮小"
        case .zoomReset: "實際大小"
        case .pin: "釘住 / 取消釘住"
        case .hide: "立刻收起面板"
        case .settings: "設定"
        }
    }

    /// ⌘1～⌘9 是一整組，不開放自訂
    var isCustomizable: Bool { self != .tabNumber }

    var defaultCombo: KeyCombo? {
        let cmd: NSEvent.ModifierFlags = .command
        let cmdShift: NSEvent.ModifierFlags = [.command, .shift]
        switch self {
        case .addressBar: return KeyCombo(keyCode: kVK_ANSI_L, cmd)
        case .newTab: return KeyCombo(keyCode: kVK_ANSI_T, cmd)
        case .closeTab: return KeyCombo(keyCode: kVK_ANSI_W, cmd)
        case .reopenTab: return KeyCombo(keyCode: kVK_ANSI_T, cmdShift)
        case .previousTab: return KeyCombo(keyCode: kVK_ANSI_LeftBracket, cmdShift)
        case .nextTab: return KeyCombo(keyCode: kVK_ANSI_RightBracket, cmdShift)
        case .tabNumber: return nil
        case .overview: return KeyCombo(keyCode: kVK_ANSI_Backslash, cmdShift)
        case .bookmark: return KeyCombo(keyCode: kVK_ANSI_D, cmd)
        case .back: return KeyCombo(keyCode: kVK_ANSI_LeftBracket, cmd)
        case .forward: return KeyCombo(keyCode: kVK_ANSI_RightBracket, cmd)
        case .reload: return KeyCombo(keyCode: kVK_ANSI_R, cmd)
        case .home: return KeyCombo(keyCode: kVK_ANSI_H, cmdShift)
        case .copyURL: return KeyCombo(keyCode: kVK_ANSI_C, cmdShift)
        case .zoomIn: return KeyCombo(keyCode: kVK_ANSI_Equal, cmd)
        case .zoomOut: return KeyCombo(keyCode: kVK_ANSI_Minus, cmd)
        case .zoomReset: return KeyCombo(keyCode: kVK_ANSI_0, cmd)
        case .pin: return KeyCombo(keyCode: kVK_ANSI_P, cmd)
        case .hide: return KeyCombo(keyCode: kVK_ANSI_H, cmd)
        case .settings: return KeyCombo(keyCode: kVK_ANSI_Comma, cmd)
        }
    }

    /// 選單和提示上顯示的按鍵
    @MainActor var keys: String {
        self == .tabNumber ? "⌘1–9" : ShortcutStore.shared.combo(for: self)?.display ?? "—"
    }

    /// 按鈕的滑鼠提示，例如「新增分頁（⌘T）」
    @MainActor var help: String { "\(title)（\(keys)）" }
}

/// 使用者自訂的快捷鍵，存在 UserDefaults；沒自訂的用預設值
@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()

    /// 固定給 ⌘1～9 切分頁和編輯指令用的組合，不能拿來綁其他功能
    static let numberKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                             kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
    private static let editKeys = [kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_A, kVK_ANSI_Z]

    @Published private(set) var custom: [String: KeyCombo] = [:]
    private let key = "shortcuts"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: KeyCombo].self, from: data) {
            custom = saved
        }
    }

    func combo(for shortcut: Shortcut) -> KeyCombo? {
        custom[shortcut.rawValue] ?? shortcut.defaultCombo
    }

    func isCustomized(_ shortcut: Shortcut) -> Bool {
        custom[shortcut.rawValue] != nil
    }

    func shortcut(matching combo: KeyCombo) -> Shortcut? {
        Shortcut.allCases.first { $0.isCustomizable && self.combo(for: $0) == combo }
    }

    /// 這組按鍵如果已經有用途，回傳那個用途的名稱
    func conflict(for combo: KeyCombo, excluding shortcut: Shortcut) -> String? {
        if combo.flags == .command {
            if Self.numberKeys.contains(Int(combo.keyCode)) { return Shortcut.tabNumber.title }
            if Self.editKeys.contains(Int(combo.keyCode)) { return "編輯指令" }
        }
        if let other = self.shortcut(matching: combo), other != shortcut { return other.title }
        return nil
    }

    func set(_ combo: KeyCombo, for shortcut: Shortcut) {
        custom[shortcut.rawValue] = combo == shortcut.defaultCombo ? nil : combo
        save()
    }

    func reset(_ shortcut: Shortcut) {
        custom[shortcut.rawValue] = nil
        save()
    }

    func resetAll() {
        custom = [:]
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
