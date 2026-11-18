import AppKit
import Foundation

/// Prevents launching two instances at once (e.g. a copy from .build and one from /Applications).
///
/// The main protection is `flock` on a file in Application Support: it is reliable even
/// when both start simultaneously. Additionally, we activate the already running instance.
enum InstanceGuard {
    private nonisolated(unsafe) static var lockFileDescriptor: Int32 = -1

    /// Returns true if this is the only instance.
    static func acquire() -> Bool {
        let directory = Defaults.appSupportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let path = directory.appendingPathComponent("instance.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else { return true } // couldn't lock — don't block launch

        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            close(descriptor)
            return false
        }

        lockFileDescriptor = descriptor // hold until the process exits
        return true
    }

    /// Brings the already running instance to the front, if there is one.
    static func activateExistingInstance() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let current = NSRunningApplication.current
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != current }
        others.first?.activate()
    }
}
