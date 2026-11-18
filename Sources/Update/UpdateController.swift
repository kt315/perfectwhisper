import AppKit
import Foundation
import Observation

/// Update checking via GitLab Releases.
///
/// The project is set in `Info.plist` under the `PWUpdateProject` key (for example,
/// `kt315/perfectwhisper`) or overridden in settings
/// (`update.project`). The network is used only for the GitLab request.
@MainActor
@Observable
final class UpdateController {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(UpdateRelease)
        case failed(String)
    }

    private(set) var state: State = .idle

    var onAvailable: ((UpdateRelease) -> Void)?

    private let defaults = UserDefaults.standard
    private static let lastCheckKey = "update.lastCheck"
    private static let skippedKey = "update.skippedVersion"
    private static let projectOverrideKey = "update.project"
    private static let providerKey = "update.provider"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var projectPath: String {
        if let override = defaults.string(forKey: Self.projectOverrideKey), !override.isEmpty {
            return override
        }
        return Bundle.main.infoDictionary?["PWUpdateProject"] as? String ?? ""
    }

    var provider: String {
        if let override = defaults.string(forKey: Self.providerKey), !override.isEmpty {
            return override
        }
        return Bundle.main.infoDictionary?["PWUpdateProvider"] as? String ?? "gitlab"
    }

    var isConfigured: Bool { !projectPath.isEmpty }

    private func fetchLatest() async throws -> UpdateRelease {
        switch provider {
        case "github":
            return try await GitHubUpdater.latestRelease(projectPath: projectPath)
        default:
            return try await GitLabUpdater.latestRelease(projectPath: projectPath)
        }
    }

    /// Check at launch: no more than once a day and without nagging.
    func checkAutomaticallyIfNeeded() {
        guard isConfigured else { return }
        let last = defaults.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > Self.checkInterval else { return }
        Task { await check(silent: true) }
    }

    func check(silent: Bool = false) async {
        guard isConfigured else {
            if !silent { state = .failed(UpdateError.notConfigured.localizedDescription) }
            return
        }

        state = .checking
        defer { defaults.set(Date(), forKey: Self.lastCheckKey) }

        do {
            let release = try await fetchLatest()
            guard VersionCompare.isNewer(release.version, than: currentVersion) else {
                state = .upToDate
                if !silent { presentUpToDate() }
                return
            }

            let skipped = defaults.string(forKey: Self.skippedKey)
            if silent, skipped == release.version { return }

            state = .available(release)
            onAvailable?(release)
        } catch {
            state = .failed(error.localizedDescription)
            if !silent { presentError(error.localizedDescription) }
        }
    }

    func skip(_ release: UpdateRelease) {
        defaults.set(release.version, forKey: Self.skippedKey)
        state = .idle
    }

    // MARK: - Simple alerts for a manual check

    private func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = L10n.t("No updates")
        alert.informativeText = L10n.t("You are running the latest version (%@).", currentVersion)
        alert.runModal()
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.t("Could not check for updates")
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
