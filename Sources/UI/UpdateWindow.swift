import AppKit
import SwiftUI

struct UpdateView: View {
    var release: UpdateRelease
    var currentVersion: String
    var onDownload: () -> Void
    var onSkip: () -> Void
    var onLater: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("Update available"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(L10n.t("Version %@ is available. You have %@.", release.version, currentVersion))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if !release.notes.isEmpty {
                ScrollView {
                    Text(release.notes)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 140)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                )
            }

            Spacer(minLength: 0)

            HStack {
                Button(L10n.t("Skip this version"), action: onSkip)
                Spacer()
                Button(L10n.t("Later"), action: onLater)
                Button(L10n.t("Download"), action: onDownload)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 480, height: 320)
    }
}

@MainActor
final class UpdateWindowController {
    private var window: NSWindow?

    func show(
        release: UpdateRelease,
        currentVersion: String,
        onDownload: @escaping (UpdateRelease) -> Void,
        onSkip: @escaping (UpdateRelease) -> Void
    ) {
        close()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.t("Update available")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: UpdateView(
            release: release,
            currentVersion: currentVersion,
            onDownload: { [weak self] in
                onDownload(release)
                self?.close()
            },
            onSkip: { [weak self] in
                onSkip(release)
                self?.close()
            },
            onLater: { [weak self] in self?.close() }
        ))
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
    }
}
