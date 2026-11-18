import AppKit
import Observation
import SwiftUI

struct SettingsView: View {
    var env: AppEnvironment

    @AppStorage(PrefKey.uiLanguage) private var uiLanguage = "auto"
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            GeneralSettingsView()
                .tabItem { Label(L10n.t("General"), systemImage: "gearshape") }
                .tag(0)

            ModelSettingsView(env: env)
                .tabItem { Label(L10n.t("Model"), systemImage: "brain") }
                .tag(1)

            AudioSettingsView(env: env)
                .tabItem { Label(L10n.t("Microphone"), systemImage: "mic") }
                .tag(2)

            PermissionsSettingsView()
                .tabItem { Label(L10n.t("Access"), systemImage: "lock.shield") }
                .tag(3)
        }
        .id(uiLanguage) // rebuild the whole window when the language changes
        .onReceive(NotificationCenter.default.publisher(for: .perfectWhisperOpenModelSettings)) { _ in
            selection = 1
        }
        .frame(width: 620, height: 600)
    }
}
