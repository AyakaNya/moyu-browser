# 摸魚瀏覽器 MoyuBrowser

一個平常藏在螢幕邊緣、滑鼠靠近才滑出來的 macOS 小瀏覽器。

收起時只在螢幕邊緣留一條細條。滑鼠碰到邊緣，面板會帶著輕微回彈滑出來；滑鼠離開後，面板會自己收回去。不佔 Dock，也不會出現在 ⌘Tab 裡。只是滑過去的話，不會搶走你正在打字的 App 的輸入焦點。

用原生 Swift、AppKit、SwiftUI 和 WKWebView 寫成，不依賴任何第三方套件。

## 功能

**貼邊隱藏**
- 可以貼在左側或右側，垂直位置有上方、中間、下方，也可以指定要貼在哪個螢幕
- 收起時留一條細條，滑鼠靠近就展開，離開就收起
- 展開延遲、收起延遲、動畫時長、回彈強度都能調整
- 面板可以釘住，不自動收起

**外觀**
- 預設是手機螢幕大小（390 × 844 pt），拖曳沒貼著螢幕的那幾條邊就能調整大小
- 大圓角和明顯的陰影，強度都能調整
- 頂部留白會自動填上網頁的主題色，看起來像 iPhone 版 Safari 的狀態列
- 預設用手機版網頁，也可以切回電腦版

**Liquid Glass 網址列**
- 網址列平常是隱藏的，網頁會佔滿整個面板
- 按 ⌘L 會從底部彈出 Liquid Glass 網址列，同時列出你的收藏
- 輸入時會即時篩選收藏，用 ↑ ↓ 選擇，Return 前往
- 網址列底下有一層毛玻璃，明暗會跟著網頁走

**瀏覽**
- 網址收藏
- Cookie 和登入狀態會保存在本機；設定裡能看到哪些網站存了資料，也能逐一或全部清除
- 網頁的 alert、confirm、prompt 會顯示成 Liquid Glass 對話框
- 支援檔案上傳、下載（存到「下載項目」），也支援 Google、Apple 等網站的登入彈窗
- 網頁當掉時會自動重新載入

## 系統需求

- macOS 26 以上，因為用到了 Liquid Glass
- 從原始碼編譯需要 Swift 6；裝完整的 Xcode 或只裝 Command Line Tools 都可以

## 安裝

```bash
git clone https://github.com/AyakaNya/moyu-browser.git
cd moyu-browser
./scripts/build.sh --run
```

`build.sh` 會用 SwiftPM 編譯 release 版，打包成 `build/MoyuBrowser.app`，並做本機 ad-hoc 簽名。加上 `--run` 會順便重新啟動 App。想長期使用的話，可以把 `MoyuBrowser.app` 拖到「應用程式」資料夾。

開發時也可以直接用 Xcode 打開 `Package.swift`。

## 使用方式

啟動後，選單列會出現一個 🐟 圖示，螢幕邊緣也會出現一條細條。把滑鼠移到細條附近停一下，面板就會滑出來。

### 快捷鍵

面板是「不啟用 App」的浮動視窗，所以要**先點一下面板**，鍵盤輸入才會送到面板。快捷鍵用實體按鍵位置判斷，切到注音等輸入法時也能用。

| 快捷鍵 | 功能 |
|---|---|
| ⌘L | 叫出或收回網址列 |
| ⌘D | 收藏或取消收藏目前的網頁 |
| ⌘[ / ⌘] | 上一頁 / 下一頁 |
| ⌘R | 重新整理，載入中則停止 |
| ⌘⇧H | 回首頁 |
| ⌘⇧C | 拷貝目前網址 |
| ⌘+ / ⌘- / ⌘0 | 放大 / 縮小 / 實際大小 |
| ⌘P | 釘住或取消釘住 |
| ⌘W | 立刻收起面板 |
| ⌘, | 打開設定 |
| Esc | 收回網址列，或取消網頁對話框 |

### 選單列

點 🐟 圖示可以展開或收起面板、切換釘住，也能打開收藏的網頁、查看最近下載的檔案、切換螢幕和貼邊位置、查看快捷鍵和打開設定。

### 設定

| 分頁 | 內容 |
|---|---|
| 一般 | 螢幕、貼齊邊緣、垂直位置、展開與收起延遲、手機版網頁、首頁 |
| 外觀 | 動畫時長、回彈強度、寬度、高度、圓角、陰影強度 |
| 收藏 | 查看、刪除、拖曳排序 |
| Cookie | 查看哪些網站存了資料，可以逐一或全部清除 |

## 隱私

- 收藏和設定存在本機的 UserDefaults，Cookie 和網站資料存在 WebKit 的本機資料儲存區。
- 沒有帳號、沒有雲端同步，也不收集任何使用資料。
- 下載的檔案會帶上系統的隔離標記，打開來路不明的檔案時 macOS 會照常提醒你。

## 已知限制

- 如果面板貼的那一側旁邊還有另一個螢幕，游標會直接滑到另一個螢幕，很難停在邊緣觸發展開。建議貼在沒有相鄰螢幕的那一側。
- 一次只有一個分頁。
- 沒有全域快捷鍵，要叫出面板只能把滑鼠移到邊緣，或從選單列打開。

## 專案結構

```
Sources/MoyuBrowser/
├── App.swift              App 進入點與主選單
├── AppDelegate.swift      選單列圖示與選單
├── EdgeController.swift   貼邊狀態機：滑鼠偵測、展開收起動畫、位置與縮放
├── BrowserPanel.swift     浮動面板與快捷鍵
├── BrowserView.swift      WKWebView、網址列、下載、上傳、對話框、彈窗
├── BrowserOverlay.swift   SwiftUI 的 Liquid Glass 介面（網址列、收藏、提示、對話框）
├── PopupWindow.swift      登入彈窗視窗
├── Downloads.swift        下載管理
├── Bookmarks.swift        收藏
├── Settings.swift         設定（UserDefaults）
├── SettingsView.swift     設定視窗
├── HandleWindow.swift     收起時的細條
├── ShadowWindow.swift     自繪陰影
└── Debug.swift            除錯紀錄
Support/Info.plist         App 的 Info.plist
scripts/build.sh           編譯並打包成 .app
```

## 除錯

面板該收起卻不收起時，可以用除錯模式執行，終端機會印出它沒有收起的原因：

```bash
swift build && MOYU_DEBUG=1 .build/debug/MoyuBrowser
```

## 授權

[MIT](LICENSE)
