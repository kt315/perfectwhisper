import Carbon
import Cocoa

/// Insertion of recognized text into the active app.
/// How the insertion ended up.
enum InsertOutcome: Equatable {
    case inserted
    /// The text stayed on the pasteboard instead of being typed.
    case clipboard(ClipboardReason)
}

enum ClipboardReason: Equatable {
    /// The user chose "clipboard only".
    case requested
    /// macOS blocks synthetic events without Accessibility.
    case noAccessibility
    /// A password field or a terminal holds secure input; synthetic events are ignored.
    case secureInput
}

@MainActor
final class TextInserter {
    /// Key V (ANSI keycode 9).
    private static let vKeyCode: CGKeyCode = 9

    /// While secure input is on (password fields, `sudo`, some terminals) macOS
    /// silently drops synthetic keystrokes, so there is no point typing at all.
    static var isSecureInputEnabled: Bool { IsSecureEventInputEnabled() }

    func insert(_ rawText: String, mode: InsertMode, trailingSpace: Bool) async -> InsertOutcome {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .inserted }
        if trailingSpace, mode != .clipboardOnly {
            text += " "
        }

        if mode != .clipboardOnly, Self.isSecureInputEnabled {
            copyToClipboard(text)
            return .clipboard(.secureInput)
        }

        switch mode {
        case .clipboardOnly:
            copyToClipboard(text)
            return .clipboard(.requested)
        case .pasteAndRestore:
            await paste(text)
            return .inserted
        case .typeUnicode:
            await type(text)
            return .inserted
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - ⌘V with clipboard restore

    private func paste(_ text: String) async {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let changeCount = pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // A short pause: the app needs to see the new pasteboard contents.
        try? await Task.sleep(for: .milliseconds(60))
        postCommandV()

        // Give the target app time to read the pasteboard, then restore it.
        try? await Task.sleep(for: .milliseconds(300))
        if pasteboard.changeCount == changeCount {
            snapshot.restore(to: pasteboard)
        }
    }

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: Self.vKeyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Character-by-character typing

    /// Fallback for apps that ignore ⌘V (some games, RDP,
    /// certain Electron windows). Slower, but it doesn't touch the pasteboard.
    private func type(_ text: String) async {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            // Short chunks: terminals and some editors drop long Unicode strings
            // sent in a single synthetic keystroke.
            let end = min(index + 4, characters.count)
            let chunk = String(characters[index..<end])
            let utf16 = Array(chunk.utf16)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                index = end
                continue
            }
            utf16.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: buffer.baseAddress)
                up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: buffer.baseAddress)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            index = end
            try? await Task.sleep(for: .milliseconds(8))
        }
    }
}

/// A snapshot of the whole pasteboard (all items and all types) so that dictation
/// insertion doesn't overwrite what the user copied earlier.
struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let value = item.data(forType: type) {
                    data[type] = value
                }
            }
            return data
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { data -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, value) in data {
                item.setData(value, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
