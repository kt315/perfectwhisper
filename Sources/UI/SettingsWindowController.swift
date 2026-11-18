import AppKit
import SwiftUI

/// Settings window. Lives separately from AppDelegate, which only wires
/// modules together.
@MainActor
final class SettingsWindowController {
    private let env: AppEnvironment
    private var window: NSWindow?

    init(env: AppEnvironment) {
        self.env = env
    }

    func show(modelTab: Bool = false) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "PerfectWhisper"
            window.contentView = NSHostingView(rootView: SettingsView(env: env))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if modelTab {
            NotificationCenter.default.post(name: .perfectWhisperOpenModelSettings, object: nil)
        }
    }
}
