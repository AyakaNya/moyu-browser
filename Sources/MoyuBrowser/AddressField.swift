import AppKit
import SwiftUI

/// 網址列的輸入框。用 NSTextField 而不是 SwiftUI 的 TextField，才能像 Safari 一樣
/// 把補全的網址直接接在打的字後面、反白顯示：繼續打字就蓋掉，Tab 或 → 接受，Return 前往。
struct AddressField: NSViewRepresentable {
    /// 使用者實際打的字，不含補全的部分
    @Binding var text: String
    var placeholder: String
    /// 打字後要顯示的完整文字（開頭必須是打的字），沒有可補的就回傳 nil
    var complete: (String) -> String?
    /// 按 Return，參數是輸入框裡看到的完整文字（可能含補全）
    var onSubmit: (String) -> Void
    var onMove: (Int) -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.placeholderString = placeholder
        field.stringValue = text
        field.delegate = context.coordinator
        context.coordinator.typed = text
        // 要等放進視窗後才能拿焦點；拿到之後再全選
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
            field.currentEditor()?.selectAll(nil)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        // 外面改了內容（例如切換分頁換成新網址），就整個換掉並全選
        if text != context.coordinator.typed {
            context.coordinator.typed = text
            field.stringValue = text
            field.currentEditor()?.selectAll(nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AddressField
        var typed = ""
        private var deleting = false

        init(_ parent: AddressField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView else { return }
            let current = editor.string
            let wasDeleting = deleting || current.count < typed.count
            deleting = false
            typed = current
            parent.text = current

            // 注音等輸入法還在組字時不能動輸入框，刪除時也不補
            guard !editor.hasMarkedText(), !wasDeleting,
                  editor.selectedRange().location == (current as NSString).length,
                  let full = parent.complete(current), full.count > current.count else { return }
            let start = (current as NSString).length
            editor.string = full
            editor.setSelectedRange(NSRange(location: start, length: (full as NSString).length - start))
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(textView.string)
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMove(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMove(1)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.moveRight(_:)),
                 #selector(NSResponder.moveToEndOfLine(_:)):
                // 後面有反白的補全時，接受它
                let selection = textView.selectedRange()
                let length = (textView.string as NSString).length
                if selection.length > 0, NSMaxRange(selection) == length {
                    textView.setSelectedRange(NSRange(location: length, length: 0))
                    typed = textView.string
                    parent.text = typed
                    return true
                }
                // Tab 不要把焦點移出網址列
                return selector == #selector(NSResponder.insertTab(_:))
            case #selector(NSResponder.deleteBackward(_:)), #selector(NSResponder.deleteForward(_:)),
                 #selector(NSResponder.deleteWordBackward(_:)), #selector(NSResponder.deleteToBeginningOfLine(_:)):
                deleting = true
                return false
            default:
                return false
            }
        }
    }
}
