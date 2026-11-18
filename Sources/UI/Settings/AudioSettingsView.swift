import AppKit
import Observation
import SwiftUI

// MARK: - Microphone

struct AudioSettingsView: View {
    var env: AppEnvironment

    @AppStorage(PrefKey.inputDeviceUID) private var preferredUID = ""

    var body: some View {
        Form {
            Section(L10n.t("Input device")) {
                Picker(L10n.t("Microphone"), selection: $preferredUID) {
                    Text(L10n.t("Automatic (system default)")).tag("")
                    Divider()
                    ForEach(env.devices.devices) { device in
                        Text(deviceLabel(device)).tag(device.id)
                    }
                }

                if let preferred = env.devices.device(withUID: preferredUID.isEmpty ? nil : preferredUID) {
                    Text(L10n.t("Recording will use “%@”. If it's the built-in microphone, Bluetooth headphones stay in A2DP and music quality is preserved.", preferred.name))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if !preferredUID.isEmpty {
                    Text(L10n.t("The selected microphone is currently unavailable — the system default will be used."))
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text(L10n.t("macOS picks the microphone itself. With Bluetooth headphones active, music quality may drop because they switch to headset mode."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(L10n.t("Refresh list")) { env.devices.refresh() }
            }

            Section(L10n.t("How it works")) {
                Text(L10n.t("“Automatic” follows the system input device: take the headphones off and recording moves to the built-in microphone. If you pick a microphone explicitly, PerfectWhisper will always record from it, even when headphones are connected."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
    }

    private func deviceLabel(_ device: AudioInputDevice) -> String {
        device.id == env.devices.defaultDeviceUID
            ? L10n.t("%@ (default)", device.name)
            : device.name
    }
}
