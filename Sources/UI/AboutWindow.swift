import AppKit
import SwiftUI

/// Small About window: version, license, third-party notices.
struct AboutView: View {
    var onOpenLicense: () -> Void
    var onOpenNotices: () -> Void
    var onClose: () -> Void

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }

            Text("PerfectWhisper")
                .font(.system(size: 18, weight: .semibold))

            Text(L10n.t("Version %@", version))
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(L10n.t("Local dictation. Audio never leaves your Mac."))
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("© 2026 Sergei Kraev · MIT")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button(L10n.t("License"), action: onOpenLicense)
                Button(L10n.t("Third-party notices"), action: onOpenNotices)
                Spacer()
                Button(L10n.t("Close"), action: onClose)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400, height: 320)
    }
}

@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    init() {}

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 400, height: 320),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.t("About PerfectWhisper")
            window.isReleasedWhenClosed = false
            window.center()
            window.contentView = NSHostingView(rootView: AboutView(
                onOpenLicense: { Self.openBundled("LICENSE") },
                onOpenNotices: { Self.openBundled("THIRD_PARTY_NOTICES") },
                onClose: { [weak self] in self?.window?.orderOut(nil) }
            ))
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func openBundled(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: name == "LICENSE" ? nil : "md")
            ?? Bundle.main.url(forResource: name, withExtension: "md")
            ?? Bundle.main.url(forResource: name, withExtension: "txt") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
