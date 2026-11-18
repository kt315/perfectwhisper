import AppKit

// Debug mode without UI: transcribe a file and exit.
// PerfectWhisper.app/Contents/MacOS/PerfectWhisper --transcribe /path/audio.wav
let arguments = CommandLine.arguments

#if DEBUG
// Debug microphone list: --devices
if arguments.contains("--devices-all") {
    for line in AudioDeviceManager.debugDumpAllInputDevices() {
        print(line)
    }
    exit(0)
}

if arguments.contains("--devices") {
    let manager = AudioDeviceManager()
    print("Microphones:")
    for device in manager.devices {
        print("  • \(device.name)  [uid=\(device.id)]")
    }
    print("Default: \(manager.defaultDeviceUID ?? "—")")
    exit(0)
}

// Debug launch-at-login: --login-item on|off|status
if let index = arguments.firstIndex(of: "--login-item"), arguments.count > index + 1 {
    let action = arguments[index + 1]
    switch action {
    case "on":
        LoginItemController.shared.setEnabled(true)
    case "off":
        LoginItemController.shared.setEnabled(false)
    default:
        LoginItemController.shared.refresh()
    }
    print("login item: \(LoginItemController.shared.state), error: \(LoginItemController.shared.lastError ?? "none")")
    exit(0)
}

if let index = arguments.firstIndex(of: "--transcribe"), arguments.count > index + 1 {
    await TranscribeHarness.run(path: arguments[index + 1])
    exit(0)
}
#endif

// A second instance (for example, a copy from .build and one from /Applications)
// would cause double hotkeys and double pasting.
if !InstanceGuard.acquire() {
    InstanceGuard.activateExistingInstance()
    exit(0)
}

// The app lives only in the status bar: no Dock icon, no main window.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
