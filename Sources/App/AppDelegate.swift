import AppKit
import SwiftUI

/// Wires the modules together. All menu and window handling lives in
/// separate controllers; this class only does composition.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let deviceManager = AudioDeviceManager()
    private let asrState = ASRState()
    private let repository = ModelRepository()

    private var transcriber: WhisperKitTranscriber!
    private var audio: AudioCaptureEngine!
    private var hud: HUDController!
    private var hotkey: HotkeyManager!
    private var controller: DictationController!
    private var env: AppEnvironment!
    private var menu: StatusMenuController!
    private var settings: SettingsWindowController!
    private var aboutWindow: AboutWindowController!
    private var onboardingWindow: OnboardingWindowController!
    private var updateController: UpdateController!
    private var updateWindow: UpdateWindowController!

    private var observations: [NSObjectProtocol] = []
    private var accessibilityTask: Task<Void, Never>?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        Defaults.registerDefaults()
        Log.info(
            "launch: macOS \(ProcessInfo.processInfo.operatingSystemVersionString), accessibility=\(Permissions.accessibilityGranted), microphone=\(Permissions.microphoneStatus.rawValue)"
        )

        transcriber = WhisperKitTranscriber(state: asrState)
        audio = AudioCaptureEngine()
        hud = HUDController()
        controller = DictationController(
            audio: audio,
            transcriber: transcriber,
            hud: hud,
            devices: deviceManager
        )
        hotkey = HotkeyManager()
        env = AppEnvironment(
            devices: deviceManager,
            asr: asrState,
            repository: repository,
            transcriber: transcriber
        )
        settings = SettingsWindowController(env: env)
        aboutWindow = AboutWindowController()
        onboardingWindow = OnboardingWindowController()
        updateController = UpdateController()
        updateWindow = UpdateWindowController()
        updateController.onAvailable = { [weak self] release in
            self?.updateWindow.show(
                release: release,
                currentVersion: self?.updateController.currentVersion ?? "",
                onDownload: { release in
                    if let url = release.downloadURL {
                        NSWorkspace.shared.open(url)
                    } else if let page = release.pageURL {
                        NSWorkspace.shared.open(page)
                    }
                },
                onSkip: { [weak self] release in
                    self?.updateController.skip(release)
                }
            )
        }
        menu = StatusMenuController(
            deviceManager: deviceManager,
            repository: repository,
            asrState: asrState
        )

        wireMenu()
        wireControllers()
        observeNotifications()
        menu.setIconVisible(UserDefaults.standard.bool(forKey: PrefKey.showMenuBarIcon))

        deviceManager.startObserving()
        registerHotkey(announce: false)
        onboardingWindow.onFinished = { [weak self] in
            self?.settings.show(modelTab: true)
        }
        onboardingWindow.showIfNeeded()
        watchAccessibility()
        controller.prepareModelIfPossible()
        offerModelIfNeeded()
        updateController.checkAutomaticallyIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        accessibilityTask?.cancel()
        deviceManager.stopObserving()
        hotkey.stop()
        for observation in observations {
            NotificationCenter.default.removeObserver(observation)
        }
    }

    // MARK: - Wiring

    private func wireMenu() {
        menu.isRecording = { [weak self] in self?.controller.phase == .recording }
        menu.onToggle = { [weak self] in self?.controller.toggle() }
        menu.onSelectAudioInput = { uid in
            UserDefaults.standard.set(uid, forKey: PrefKey.inputDeviceUID)
        }
        menu.onSelectInsertMode = { raw in
            UserDefaults.standard.set(raw, forKey: PrefKey.insertMode)
            Log.info("insert mode: \(raw)")
        }
        menu.onSelectModel = { [weak self] url in
            guard ModelResolver.isModelFolder(url) else {
                Log.error("selected model is gone from disk: \(url.path)")
                return
            }
            self?.repository.select(url)
        }
        menu.onOpenSettings = { [weak self] in self?.settings.show() }
        menu.onOpenModelSettings = { [weak self] in self?.settings.show(modelTab: true) }
        menu.onOpenAccessibilitySettings = { Permissions.promptAccessibility() }
        menu.onAbout = { [weak self] in self?.aboutWindow.show() }
        menu.onCheckUpdates = { [weak self] in
            Task { await self?.updateController.check() }
        }
        menu.onRequestMicrophone = { [weak self] in self?.requestMicrophoneInteractively() }
        menu.onQuit = { NSApp.terminate(nil) }
    }

    private func wireControllers() {
        hotkey.onTrigger = { [weak self] in
            Task { @MainActor in
                self?.controller.toggle()
                self?.menu.updateIcon()
            }
        }
        controller.onNeedsSetup = { [weak self] in self?.settings.show() }
        controller.onMicrophonePermissionNeeded = { [weak self] in self?.requestMicrophoneInteractively() }
        controller.onPhaseChanged = { [weak self] in self?.menu.updateIcon() }
        repository.onSelectionChanged = { [weak self] in self?.controller.reloadModel() }
        hud.onCancel = { [weak self] in self?.controller.cancelRecording() }
        hud.onCopy = { [weak self] in self?.controller.finishToClipboard() }
        deviceManager.onChange = { [weak self] in self?.menu.updateIcon() }
    }

    /// Double-clicking the app in Finder or Spotlight sends a reopen event to the
    /// running instance: show the settings window, which is the only way back
    /// when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return true
    }

    private func observeNotifications() {
        observations.append(NotificationCenter.default.addObserver(
            forName: .perfectWhisperHotkeyChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.registerHotkey(announce: true) }
        })

        observations.append(NotificationCenter.default.addObserver(
            forName: .perfectWhisperMenuBarIconChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.menu.setIconVisible(UserDefaults.standard.bool(forKey: PrefKey.showMenuBarIcon))
            }
        })

        // A second launch (Spotlight, Finder, `open`) asks the running instance
        // to open its settings window.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(
            forName: Notification.Name("com.kt315.perfectwhisper.showSettings"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.settings.show() }
        }
    }

    /// Shows the system microphone prompt directly, without an intermediate alert.
    func requestMicrophoneInteractively() {
        Task {
            let granted = await Permissions.requestMicrophone()
            if !granted {
                Permissions.openMicrophoneSettings()
            }
        }
    }

    // MARK: - Hotkey and onboarding

    private func registerHotkey(announce: Bool) {
        if hotkey.start() {
            Log.info("hotkey registered")
            return
        }
        Log.error("hotkey not registered (no Accessibility)")
        if announce {
            hud.flash(L10n.t("Accessibility access required"), isError: true, duration: .milliseconds(2600))
            Permissions.openAccessibilitySettings()
        }
    }

    /// The user may grant Accessibility while the app is already running —
    /// in that case we bring up the CGEventTap ourselves, without a restart.
    private func watchAccessibility() {
        accessibilityTask?.cancel()
        accessibilityTask = Task { [weak self] in
            var wasRunning = false
            while !Task.isCancelled {
                guard let self else { return }
                let granted = Permissions.accessibilityGranted

                if granted, !self.hotkey.isRunning {
                    self.registerHotkey(announce: false)
                    if self.hotkey.isRunning, !wasRunning {
                        self.hud.flash(L10n.t("Hotkey active"))
                    }
                } else if !granted, self.hotkey.isRunning {
                    // Permission was revoked on the fly — drop the tap, otherwise it interferes with typing.
                    self.hotkey.stop()
                    Log.info("Accessibility revoked — tap stopped")
                    self.hud.flash(L10n.t("Accessibility access required"), isError: true, duration: .milliseconds(2200))
                }

                wasRunning = self.hotkey.isRunning
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func offerModelIfNeeded() {
        guard ModelResolver.currentFolder() == nil else { return }
        if UserDefaults.standard.bool(forKey: PrefKey.didOfferModel) { return }
        UserDefaults.standard.set(true, forKey: PrefKey.didOfferModel)

        hud.flash(L10n.t("Download a Whisper model"), isError: true, duration: .milliseconds(3000))
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            settings.show(modelTab: true)
        }
    }

}
