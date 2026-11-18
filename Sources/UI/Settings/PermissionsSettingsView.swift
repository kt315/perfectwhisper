import AppKit
import Observation
import SwiftUI

// MARK: - Permissions

struct PermissionsSettingsView: View {
    @State private var microphoneGranted = Permissions.microphoneGranted
    @State private var accessibilityGranted = Permissions.accessibilityGranted

    var body: some View {
        Form {
            Section(L10n.t("Microphone")) {
                statusRow(
                    granted: microphoneGranted,
                    text: microphoneGranted ? L10n.t("Access granted") : L10n.t("No access")
                )
                if !microphoneGranted {
                    HStack {
                        Button(L10n.t("Request access")) {
                            Task {
                                _ = await Permissions.requestMicrophone()
                                refresh()
                            }
                        }
                        Button(L10n.t("Open System Settings")) { Permissions.openMicrophoneSettings() }
                    }
                }
            }

            Section(L10n.t("Accessibility")) {
                statusRow(
                    granted: accessibilityGranted,
                    text: accessibilityGranted ? L10n.t("Access granted") : L10n.t("No access")
                )
                Text(L10n.t("Required for the global hotkey and for inserting text with ⌘V into other apps."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !accessibilityGranted {
                    HStack {
                        Button(L10n.t("Request access")) {
                            Permissions.promptAccessibility()
                            refresh()
                        }
                        Button(L10n.t("Open System Settings")) { Permissions.openAccessibilitySettings() }
                    }
                }
            }

            Section {
                Button(L10n.t("Check again")) { refresh() }
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
        .onAppear { refresh() }
    }

    private func statusRow(granted: Bool, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.red)
            Text(text)
        }
    }

    private func refresh() {
        microphoneGranted = Permissions.microphoneGranted
        accessibilityGranted = Permissions.accessibilityGranted
    }
}
