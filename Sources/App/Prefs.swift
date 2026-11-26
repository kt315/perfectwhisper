import CoreGraphics
import Foundation

// MARK: - Preference keys

enum PrefKey {
    static let hotkeyKeyCode = "hotkey.keyCode"
    static let hotkeyModifiers = "hotkey.modifiers"
    static let hotkeyKind = "hotkey.kind"
    static let doubleModifier = "hotkey.doubleModifier"

    static let inputDeviceUID = "audio.inputDeviceUID"

    static let modelFolder = "model.folder"
    static let customModelFolders = "model.customFolders"
    static let modelVariant = "model.variant"

    static let language = "asr.language"
    static let initialPrompt = "asr.initialPrompt"

    static let insertMode = "insert.mode"
    static let trailingSpace = "insert.trailingSpace"

    static let sounds = "ui.sounds"
    static let minDuration = "audio.minDuration"

    static let didOfferModel = "onboarding.offeredModel"
    static let onboardingDone = "onboarding.completed"

    static let uiLanguage = "ui.language"
    static let showMenuBarIcon = "ui.showMenuBarIcon"
}

// MARK: - Insert mode

enum InsertMode: String, CaseIterable, Identifiable {
    case pasteAndRestore
    case clipboardOnly
    case typeUnicode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pasteAndRestore: return L10n.t("Paste (⌘V), restore clipboard")
        case .clipboardOnly: return L10n.t("Clipboard only")
        case .typeUnicode: return L10n.t("Type character by character")
        }
    }
}

// MARK: - Defaults

enum Defaults {
    /// Key codes: 2 = D (ANSI).
    static let defaultKeyCode = 2 // D
    static let defaultModifiers = Int(
        CGEventFlags.maskShift.rawValue | CGEventFlags.maskCommand.rawValue
    )

    /// No prompt by default: an English term list biased the decoder on Russian
    /// speech and could drop whole chunks. The field stays for those who need it.
    static let defaultPrompt = ""

    static var appSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PerfectWhisper", isDirectory: true)
    }

    static var modelsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    static var logsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefKey.hotkeyKeyCode: defaultKeyCode,
            PrefKey.hotkeyModifiers: defaultModifiers,
            PrefKey.hotkeyKind: "doubleMod",
            PrefKey.doubleModifier: "rightCommand",
            PrefKey.language: "auto",
            PrefKey.initialPrompt: defaultPrompt,
            PrefKey.insertMode: InsertMode.typeUnicode.rawValue,
            PrefKey.trailingSpace: true,
            PrefKey.sounds: true,
            PrefKey.minDuration: 0.35,
            PrefKey.modelVariant: "large-v3-v20240930_turbo",
            PrefKey.uiLanguage: "auto",
            PrefKey.showMenuBarIcon: true,
        ])
    }

    // MARK: Reading preferences from background contexts

    static var language: String {
        UserDefaults.standard.string(forKey: PrefKey.language) ?? "auto"
    }

    static var initialPrompt: String {
        UserDefaults.standard.string(forKey: PrefKey.initialPrompt) ?? ""
    }

    static var insertMode: InsertMode {
        let raw = UserDefaults.standard.string(forKey: PrefKey.insertMode) ?? ""
        return InsertMode(rawValue: raw) ?? .pasteAndRestore
    }

    static var trailingSpace: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.trailingSpace)
    }

    static var soundsEnabled: Bool {
        UserDefaults.standard.bool(forKey: PrefKey.sounds)
    }

    static var minDuration: Double {
        UserDefaults.standard.double(forKey: PrefKey.minDuration)
    }

    static var inputDeviceUID: String? {
        let value = UserDefaults.standard.string(forKey: PrefKey.inputDeviceUID) ?? ""
        return value.isEmpty ? nil : value
    }

    static var hotkeyKeyCode: UInt16 {
        UInt16(UserDefaults.standard.integer(forKey: PrefKey.hotkeyKeyCode))
    }

    static var hotkeyFlags: CGEventFlags {
        CGEventFlags(rawValue: UInt64(UserDefaults.standard.integer(forKey: PrefKey.hotkeyModifiers)))
    }

    /// "key" — a regular key combination, "media" — a media key (microphone, F5, etc.)
    static var hotkeyKind: String {
        UserDefaults.standard.string(forKey: PrefKey.hotkeyKind) ?? "key"
    }


    /// "fn" | "rightOption" | "rightCommand"
    static var doubleModifier: String {
        UserDefaults.standard.string(forKey: PrefKey.doubleModifier) ?? "fn"
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let perfectWhisperHotkeyChanged = Notification.Name("perfectWhisper.hotkeyChanged")
    static let perfectWhisperModelChanged = Notification.Name("perfectWhisper.modelChanged")
    static let perfectWhisperOpenModelSettings = Notification.Name("perfectWhisper.openModelSettings")
    static let perfectWhisperMenuBarIconChanged = Notification.Name("perfectWhisper.menuBarIconChanged")
}
