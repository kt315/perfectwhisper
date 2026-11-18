import AVFoundation
import Cocoa

/// macOS permissions. Microphone — for recording, Accessibility — for the global
/// hotkey and synthetic ⌘V into other apps.
enum Permissions {
    static var microphoneStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static var microphoneGranted: Bool {
        microphoneStatus == .authorized
    }

    static func requestMicrophone() async -> Bool {
        Log.info("requesting microphone access, status=\(microphoneStatus.rawValue)")
        // A background menu bar app has to be active, otherwise macOS
        // denies the request without showing a dialog.
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }
        try? await Task.sleep(for: .milliseconds(250))
        switch microphoneStatus {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            Log.info("microphone request response: \(granted)")
            return granted
        default:
            return false
        }
    }

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func promptAccessibility() -> Bool {
        // Use the string key instead of kAXTrustedCheckOptionPrompt: the global variable
        // from ApplicationServices doesn't pass Swift 6 concurrency checking.
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Resets the remembered denial so macOS shows the dialog again.
    static func resetMicrophoneDecision() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Microphone", bundleID]
        do {
            try process.run()
            process.waitUntilExit()
            Log.info("microphone decision reset (tccutil exit=\(process.terminationStatus))")
        } catch {
            Log.error("failed to reset the microphone decision: \(error.localizedDescription)")
        }
    }

    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
