import AppKit
import AVFoundation
import SwiftUI

/// Permission onboarding as a checklist.
///
/// The order is strict: the microphone is the minimum requirement, without it the
/// app is useless. Accessibility is optional; without it text goes to the clipboard.
@MainActor
@Observable
final class OnboardingModel {
    var microphoneGranted = false
    var microphoneDenied = false
    var accessibilityGranted = false
    /// Seconds left before the checklist closes itself once both permissions
    /// are granted. `nil` while something is still missing.
    var countdown: Int?
}

struct OnboardingView: View {
    var model: OnboardingModel
    var onRequestMicrophone: () -> Void
    var onRestartForRequest: () -> Void
    var onOpenAccessibility: () -> Void
    var onContinue: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("PerfectWhisper")
                .font(.system(size: 16, weight: .semibold))

            permissionRow(
                title: L10n.t("Microphone"),
                granted: model.microphoneGranted,
                text: L10n.t("Minimum requirement. Without the microphone speech recognition does not work at all."),
                button: model.microphoneGranted
                    ? nil
                    : (model.microphoneDenied
                        ? L10n.t("Restart to request again")
                        : L10n.t("Request access")),
                action: model.microphoneDenied ? onRestartForRequest : onRequestMicrophone
            )

            if model.microphoneDenied, !model.microphoneGranted {
                Text(L10n.t("Access was denied. macOS remembers the decision, so restarting is the only way to see the dialog again."))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            permissionRow(
                title: L10n.t("Accessibility"),
                granted: model.accessibilityGranted,
                text: L10n.t("Needed for the global hotkey and for inserting text into other apps. Without it the text goes to the clipboard and you paste it yourself with ⌘V."),
                button: model.accessibilityGranted ? nil : L10n.t("Open System Settings"),
                action: onOpenAccessibility
            )

            Spacer(minLength: 0)

            HStack {
                Button(L10n.t("Quit"), action: onQuit)
                Spacer()
                Button(continueTitle, action: onContinue)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.microphoneGranted)
            }
        }
        .padding(20)
        .frame(width: 520, height: 360, alignment: .topLeading)
    }

    private var continueTitle: String {
        guard let countdown = model.countdown else { return L10n.t("Continue") }
        return L10n.t("Continue (%d)", Int32(clamping: countdown))
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        granted: Bool,
        text: String,
        button: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(granted ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if granted {
                    Text(L10n.t("Granted"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let button {
                Button(button, action: action)
                    .controlSize(.small)
            }
        }
    }
}

@MainActor
final class OnboardingWindowController {
    private let model = OnboardingModel()
    private var window: NSWindow?
    private var ticker: Task<Void, Never>?
    /// When both permissions are granted the checklist stays visible for a
    /// moment so the user can see the result, then the window closes itself.
    private var closeAt: Date?

    var onFinished: () -> Void = {}

    init() {}

    func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: PrefKey.onboardingDone) else { return }
        show()
    }

    func show() {
        refresh()
        // Nothing to show when both permissions are already in place.
        if isComplete {
            finish()
            return
        }

        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "PerfectWhisper"
            window.isReleasedWhenClosed = false
            window.center()
            // Floating: the checklist must stay reachable while the system
            // permission dialog or System Settings is in front of us.
            window.level = .floating
            window.hidesOnDeactivate = false
            window.contentView = NSHostingView(rootView: OnboardingView(
                model: model,
                onRequestMicrophone: { [weak self] in self?.requestMicrophone() },
                onRestartForRequest: { [weak self] in self?.restartForRequest() },
                onOpenAccessibility: { [weak self] in self?.openAccessibility() },
                onContinue: { [weak self] in self?.finish() },
                onQuit: { NSApp.terminate(nil) }
            ))
            self.window = window
        }

        presentFront()
        // Activation during launch can be overridden when the launch sequence
        // finishes, so re-assert it on the next main-actor turn.
        Task { @MainActor in self.presentFront() }
        startTicker()
    }

    /// For a menu bar (accessory) app activation only succeeds once there is a
    /// window that can become key, so the window is ordered in first.
    private func presentFront() {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func requestMicrophone() {
        guard Permissions.microphoneStatus == .notDetermined else { return }
        Task {
            _ = await Permissions.requestMicrophone()
            self.refresh()
            self.presentFront()
        }
    }

    /// macOS caches the denial per process, so the only way to see the dialog
    /// again is a new process: reset the decision and relaunch.
    private func restartForRequest() {
        Permissions.resetMicrophoneDecision()
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open -n '\(path)'"]
        try? process.run()
        NSApp.terminate(nil)
    }

    private func openAccessibility() {
        // Do not cover System Settings: while the user is toggling the switch
        // the checklist goes back to the normal level and is raised again when
        // the app becomes active.
        window?.level = .normal
        window?.orderBack(nil)
        // The system dialog itself offers "Open System Settings".
        Permissions.promptAccessibility()
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: PrefKey.onboardingDone)
        closeAt = nil
        model.countdown = nil
        ticker?.cancel()
        ticker = nil
        window?.orderOut(nil)
        onFinished()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled else { return }
                self.refresh()

                if self.isComplete {
                    if self.closeAt == nil {
                        self.closeAt = Date().addingTimeInterval(3)
                    }
                    let remaining = max(0, Int(ceil(self.closeAt?.timeIntervalSinceNow ?? 0)))
                    self.model.countdown = remaining
                    if remaining == 0 {
                        self.finish()
                        return
                    }
                } else if self.closeAt != nil || self.model.countdown != nil {
                    self.closeAt = nil
                    self.model.countdown = nil
                }

                if NSApp.isActive, self.window?.isVisible == true {
                    self.window?.level = .floating
                }
            }
        }
    }

    private var isComplete: Bool {
        model.microphoneGranted && model.accessibilityGranted
    }

    private func refresh() {
        model.microphoneGranted = Permissions.microphoneGranted
        model.microphoneDenied = Permissions.microphoneStatus == .denied
        model.accessibilityGranted = Permissions.accessibilityGranted
    }
}
