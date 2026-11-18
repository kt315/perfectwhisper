import Cocoa

/// Human-readable names of keys and modifier symbols — for the settings UI.
enum KeyNames {
    static func display(keyCode: UInt16, modifiers: CGEventFlags) -> String {
        var result = ""
        if modifiers.contains(.maskControl) { result += "⌃" }
        if modifiers.contains(.maskAlternate) { result += "⌥" }
        if modifiers.contains(.maskShift) { result += "⇧" }
        if modifiers.contains(.maskCommand) { result += "⌘" }
        if modifiers.contains(.maskSecondaryFn) { result += "fn " }
        return result + name(for: keyCode)
    }

    static func displayDoubleModifier(_ modifier: String) -> String {
        switch modifier {
        case "leftOption": return L10n.t("Double Left Option")
        case "rightOption": return L10n.t("Double Right Option")
        case "leftCommand": return L10n.t("Double Left Command")
        case "rightCommand": return L10n.t("Double Right Command")
        default: return L10n.t("Double Fn")
        }
    }

    static func name(for keyCode: UInt16) -> String {
        if let letter = ansiNames[keyCode] { return letter }
        return "Key \(keyCode)"
    }

    /// The ANSI layout (like a US keyboard); for hotkeys this is the right
    /// reference because the keycode doesn't depend on the selected layout.
    private static let ansiNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
        26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
        34: "I", 35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥", 49: "Space",
        50: "`", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 114: "Help",
        115: "↖", 116: "⇞", 117: "⌦", 118: "F4", 119: "↘", 120: "F2", 121: "⇟",
        122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
