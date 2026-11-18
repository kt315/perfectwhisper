import AppKit
import Observation
import SwiftUI

// MARK: - Hotkey recorder

struct HotkeyField: View {
    @AppStorage(PrefKey.hotkeyKeyCode) private var keyCode = Defaults.defaultKeyCode
    @AppStorage(PrefKey.hotkeyModifiers) private var modifiers = Defaults.defaultModifiers

    @State private var isCapturing = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(KeyNames.display(
                keyCode: UInt16(clamping: keyCode),
                modifiers: CGEventFlags(rawValue: UInt64(max(0, modifiers)))
            ))
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.12))
            )

            Spacer()

            Button(isCapturing ? L10n.t("Press shortcut… (Esc to cancel)") : L10n.t("Change")) {
                isCapturing ? stopCapture() : startCapture()
            }
            .buttonStyle(.bordered)
        }
        .onDisappear { stopCapture() }
    }

    private func startCapture() {
        guard monitor == nil else { return }
        isCapturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stopCapture()
                return nil
            }
            let cgFlags = Self.cgFlags(from: event.modifierFlags)
            let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            let filtered = cgFlags.intersection(relevant)
            guard !filtered.isEmpty else { return nil } // at least one modifier is required

            keyCode = Int(event.keyCode)
            modifiers = Int(filtered.rawValue)
            // Recording a combination switches back to keyboard mode.
            UserDefaults.standard.set("key", forKey: PrefKey.hotkeyKind)
            NotificationCenter.default.post(name: .perfectWhisperHotkeyChanged, object: nil)
            stopCapture()
            return nil
        }
    }

    private func stopCapture() {
        isCapturing = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private static func cgFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result: CGEventFlags = []
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.function) { result.insert(.maskSecondaryFn) }
        return result
    }
}
