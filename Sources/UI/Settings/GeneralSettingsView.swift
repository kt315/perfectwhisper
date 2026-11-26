import AppKit
import Observation
import SwiftUI

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage(PrefKey.uiLanguage) private var uiLanguage = "auto"
    @AppStorage(PrefKey.insertMode) private var insertMode = InsertMode.typeUnicode.rawValue
    @AppStorage(PrefKey.trailingSpace) private var trailingSpace = true
    @AppStorage(PrefKey.sounds) private var sounds = true
    @AppStorage(PrefKey.language) private var language = "auto"
    @AppStorage(PrefKey.initialPrompt) private var prompt = Defaults.defaultPrompt
    @AppStorage(PrefKey.hotkeyKind) private var hotkeyKind = "doubleMod"
    @AppStorage(PrefKey.doubleModifier) private var doubleModifier = "rightCommand"
    @AppStorage(PrefKey.showMenuBarIcon) private var showMenuBarIcon = true
    @State private var accessibilityGranted = Permissions.accessibilityGranted

    private let languages: [(String, String)] = [
        ("auto", L10n.t("Auto-detect")),
        ("ru", "Русский"),
        ("en", "English"),
        ("uk", "Українська"),
        ("de", "Deutsch"),
        ("fr", "Français"),
        ("es", "Español"),
        ("it", "Italiano"),
        ("pl", "Polski"),
        ("pt", "Português"),
        ("nl", "Nederlands"),
        ("tr", "Türkçe"),
        ("zh", "中文"),
        ("ja", "日本語"),
        ("ko", "한국어"),
    ]

    var body: some View {
        Form {
            Section(L10n.t("Interface language")) {
                Picker(L10n.t("Language"), selection: $uiLanguage) {
                    Text(L10n.t("System")).tag("auto")
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
            }

            Section(L10n.t("Hotkey")) {
                if accessibilityGranted {
                    Picker("", selection: $hotkeyKind) {
                        Text(L10n.t("Keyboard shortcut")).tag("key")
                        Text(L10n.t("Double tap")).tag("doubleMod")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: hotkeyKind) { _, _ in
                        NotificationCenter.default.post(name: .perfectWhisperHotkeyChanged, object: nil)
                    }

                    if hotkeyKind == "doubleMod" {
                        Picker(L10n.t("Modifier"), selection: $doubleModifier) {
                            Text("Fn (🌐)").tag("fn")
                            Text(L10n.t("Right Option")).tag("rightOption")
                            Text(L10n.t("Left Option")).tag("leftOption")
                            Text(L10n.t("Right Command")).tag("rightCommand")
                            Text(L10n.t("Left Command")).tag("leftCommand")
                        }
                        .onChange(of: doubleModifier) { _, _ in
                            NotificationCenter.default.post(name: .perfectWhisperHotkeyChanged, object: nil)
                        }

                        Text(L10n.t("Tap the modifier twice quickly."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(L10n.t("Single Fn still switches the input source. To keep the system quiet, set “Press 🌐 key to” → Do Nothing in Keyboard settings."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        HotkeyField()
                    }

                    Text(L10n.t("Press the hotkey once to start recording, again to stop and insert the text."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    AccessibilityWarning(text: L10n.t("Accessibility is required for the hotkey and automatic insertion."))
                }
            }

            Section(L10n.t("Insertion")) {
                if accessibilityGranted {
                    Picker(L10n.t("Where to put text"), selection: $insertMode) {
                        ForEach(InsertMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                } else {
                    LabeledContent(L10n.t("Where to put text")) {
                        Text(InsertMode.clipboardOnly.title)
                    }
                    AccessibilityWarning(text: L10n.t("Without Accessibility only clipboard mode is available."))
                }

                Toggle(L10n.t("Add trailing space"), isOn: $trailingSpace)
            }

            Section(L10n.t("Recognition")) {
                Picker(L10n.t("Language"), selection: $language) {
                    ForEach(languages, id: \.0) { code, title in
                        Text(title).tag(code)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Model hint (initial prompt)"))
                        .font(.callout)
                    TextEditor(text: $prompt)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 78)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.secondary.opacity(0.25))
                        )
                    Text(L10n.t("Optional. Can help with rare names and product terms, but may also bias recognition — leave it empty if unsure."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle(L10n.t("Launch at login"), isOn: Binding(
                    get: { LoginItemController.shared.isOn },
                    set: { LoginItemController.shared.setEnabled($0) }
                ))
                if LoginItemController.shared.state == .requiresApproval {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(L10n.t("macOS needs your approval to add PerfectWhisper to login items."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.t("Open Login Items settings")) {
                            LoginItemController.shared.openSystemSettings()
                        }
                        .controlSize(.small)
                    }
                }
                if let error = LoginItemController.shared.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text(L10n.t("The app starts automatically when you log in. It appears in System Settings → General → Login Items."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.t("Menu bar")) {
                Toggle(L10n.t("Show icon in menu bar"), isOn: $showMenuBarIcon)
                    .onChange(of: showMenuBarIcon) { _, _ in
                        NotificationCenter.default.post(name: .perfectWhisperMenuBarIconChanged, object: nil)
                    }
                if !showMenuBarIcon {
                    Text(L10n.t("The icon is hidden. Launch PerfectWhisper again from Spotlight or Finder to reopen this window."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(L10n.t("Quit PerfectWhisper")) { NSApp.terminate(nil) }
                        .controlSize(.small)
                }
            }

            Section(L10n.t("Sounds")) {
                Toggle(L10n.t("Start and stop signals"), isOn: $sounds)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
        .onAppear {
            // Migrate from the old media-key mode.
            if hotkeyKind == "media" { hotkeyKind = "key" }
            accessibilityGranted = Permissions.accessibilityGranted
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = Permissions.accessibilityGranted
        }
    }
}
