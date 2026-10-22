import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: EdgeController!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let settings = Settings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = EdgeController()
        controller.panel.onOpenSettings = { [weak self] in self?.openSettings() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "fish", accessibilityDescription: "摸魚瀏覽器")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // 每次打開選單時重建，勾選狀態才會是最新的
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(item(controller.isExpanded ? "收起" : "展開", #selector(toggle)))

        let pin = item("釘住（不自動收起）", #selector(togglePin))
        pin.state = controller.isPinned ? .on : .off
        menu.addItem(pin)
        menu.addItem(.separator())

        menu.addItem(submenu("收藏", bookmarkMenu()))
        menu.addItem(submenu("下載", downloadMenu()))
        menu.addItem(submenu("螢幕", screenMenu()))
        menu.addItem(submenu("位置", positionMenu()))
        menu.addItem(submenu("快捷鍵", shortcutMenu()))
        menu.addItem(item("設定…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("結束摸魚", #selector(quit), key: "q"))
    }

    private func bookmarkMenu() -> NSMenu {
        let menu = NSMenu()
        let items = BookmarkStore.shared.items
        if items.isEmpty {
            let empty = NSMenuItem(title: "還沒有收藏（在面板裡按 ⌘D）", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for bookmark in items {
            let entry = item(bookmark.title, #selector(openBookmark(_:)))
            entry.representedObject = bookmark.url
            entry.toolTip = bookmark.url
            menu.addItem(entry)
        }
        return menu
    }

    private func downloadMenu() -> NSMenu {
        let menu = NSMenu()
        let recent = DownloadManager.shared.recent
        if recent.isEmpty {
            let empty = NSMenuItem(title: "這次還沒有下載", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for url in recent {
            let entry = item(url.lastPathComponent, #selector(revealDownload(_:)))
            entry.representedObject = url
            entry.toolTip = "在 Finder 中顯示"
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(item("打開「下載項目」資料夾", #selector(openDownloadsFolder)))
        return menu
    }

    private func screenMenu() -> NSMenu {
        let menu = NSMenu()
        let auto = item("自動（主螢幕）", #selector(chooseScreen(_:)))
        auto.representedObject = 0
        auto.state = settings.displayID == 0 ? .on : .off
        menu.addItem(auto)
        menu.addItem(.separator())
        for screen in NSScreen.screens {
            let option = item(screen.localizedName, #selector(chooseScreen(_:)))
            option.representedObject = screen.displayID
            option.state = settings.displayID == screen.displayID ? .on : .off
            menu.addItem(option)
        }
        return menu
    }

    private func positionMenu() -> NSMenu {
        let menu = NSMenu()
        for edge in DockEdge.allCases {
            for align in VerticalAlign.allCases {
                let option = item(edge.title + align.title, #selector(choosePosition(_:)))
                option.representedObject = "\(edge.rawValue)-\(align.rawValue)"
                option.state = settings.edge == edge && settings.verticalAlign == align ? .on : .off
                menu.addItem(option)
            }
            if edge == .left { menu.addItem(.separator()) }
        }
        return menu
    }

    private func shortcutMenu() -> NSMenu {
        let menu = NSMenu()
        let note = NSMenuItem(title: "先點一下面板，再按以下快捷鍵", action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
        menu.addItem(.separator())
        for shortcut in Shortcut.allCases {
            let entry = NSMenuItem(title: "\(shortcut.keys)\t\(shortcut.title)", action: nil, keyEquivalent: "")
            entry.isEnabled = false
            menu.addItem(entry)
        }
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @objc private func toggle() { controller.toggle() }
    @objc private func togglePin() { controller.isPinned.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openBookmark(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? String else { return }
        controller.panel.browser.open(urlString: url)
        controller.expand(manual: true)
    }

    @objc private func revealDownload(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func openDownloadsFolder() {
        NSWorkspace.shared.open(DownloadManager.folder)
    }

    @objc private func chooseScreen(_ sender: NSMenuItem) {
        settings.displayID = sender.representedObject as? Int ?? 0
    }

    @objc private func choosePosition(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let parts = raw.split(separator: "-").map(String.init)
        guard parts.count == 2,
              let edge = DockEdge(rawValue: parts[0]),
              let align = VerticalAlign(rawValue: parts[1]) else { return }
        settings.edge = edge
        settings.verticalAlign = align
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = SettingsWindow.make(settings: settings, bookmarks: .shared)
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
