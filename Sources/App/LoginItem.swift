import Foundation
import Observation
import ServiceManagement

/// Launch at login.
///
/// We use `SMAppService.mainApp` — this is a Login Item proper,
/// not a background agent/daemon: the app simply starts at login and sits
/// in the menu bar. In System Settings it appears under
/// "General → Login Items → Open at Login".
@MainActor
@Observable
final class LoginItemController {
    static let shared = LoginItemController()

    enum State: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case unavailable(String)
    }

    private(set) var state: State = .disabled
    private(set) var lastError: String?

    private init() {
        refresh()
    }

    var isOn: Bool {
        state == .enabled || state == .requiresApproval
    }

    func refresh() {
        guard #available(macOS 13.0, *) else {
            state = .unavailable("macOS 13+ required")
            return
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            state = .enabled
        case .notRegistered:
            state = .disabled
        case .requiresApproval:
            state = .requiresApproval
        case .notFound:
            // Before the first registration the system reports notFound — that is a normal
            // "off" state, not an error.
            state = .disabled
        @unknown default:
            state = .disabled
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }

        if !enabled {
            if SMAppService.mainApp.status != .notRegistered {
                do {
                    try SMAppService.mainApp.unregister()
                    Log.info("launch at login disabled")
                } catch {
                    lastError = error.localizedDescription
                    Log.error("failed to disable launch at login: \(error.localizedDescription)")
                }
            }
            refresh()
            return
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            break
        case .requiresApproval:
            // Already registered, but the user has to approve it in the system.
            openSystemSettings()
        default:
            do {
                try SMAppService.mainApp.register()
                Log.info("launch at login enabled")
            } catch {
                lastError = error.localizedDescription
                Log.error("failed to enable launch at login: \(error.localizedDescription)")
            }
        }
        refresh()
    }

    func openSystemSettings() {
        guard #available(macOS 13.0, *) else { return }
        SMAppService.openSystemSettingsLoginItems()
    }
}
