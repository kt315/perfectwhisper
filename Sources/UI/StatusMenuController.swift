import AppKit

/// Status bar icon and all menus. Knows nothing about dictation — it only
/// reports clicks through closures.
@MainActor
final class StatusMenuController {
    private let statusItem: NSStatusItem
    private let deviceManager: AudioDeviceManager
    private let repository: ModelRepository
    private let asrState: ASRState

    // Actions wired by AppDelegate.
    var isRecording: () -> Bool = { false }
    var onToggle: () -> Void = {}
    var onSelectAudioInput: (String) -> Void = { _ in }
    var onSelectInsertMode: (String) -> Void = { _ in }
    var onSelectModel: (URL) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    var onOpenModelSettings: () -> Void = {}
    var onOpenAccessibilitySettings: () -> Void = {}
    var onAbout: () -> Void = {}
    var onCheckUpdates: () -> Void = {}
    var onRequestMicrophone: () -> Void = {}
    var onQuit: () -> Void = {}

    init(deviceManager: AudioDeviceManager, repository: ModelRepository, asrState: ASRState) {
        self.deviceManager = deviceManager
        self.repository = repository
        self.asrState = asrState
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = statusImage()
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "PerfectWhisper"
        }
    }

    func updateIcon() {
        statusItem.button?.image = statusImage()
        statusItem.button?.image?.isTemplate = true
    }

    private func statusImage() -> NSImage? {
        let name = isRecording() ? "waveform.circle.fill" : "waveform"
        return NSImage(systemSymbolName: name, accessibilityDescription: "PerfectWhisper")
    }

    // MARK: - Clicks

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || event?.modifierFlags.contains(.control) == true
        if isRightClick {
            showMenu()
        } else {
            onToggle()
            updateIcon()
        }
    }

    private func showMenu() {
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Menus

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let recording = isRecording()
        let toggleItem = NSMenuItem(
            title: recording ? L10n.t("Stop and insert") : L10n.t("Start dictation"),
            action: #selector(toggleDictation),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.attributedTitle = NSAttributedString(
            string: toggleItem.title,
            attributes: [.font: NSFont.menuFont(ofSize: 0)]
        )
        menu.addItem(toggleItem)

        let hotkeyTitle: String
        switch Defaults.hotkeyKind {
        case "doubleMod":
            hotkeyTitle = KeyNames.displayDoubleModifier(Defaults.doubleModifier)
        default:
            hotkeyTitle = KeyNames.display(
                keyCode: Defaults.hotkeyKeyCode,
                modifiers: Defaults.hotkeyFlags
            )
        }
        let hotkeyItem = NSMenuItem(
            title: L10n.t("Hotkey: %@", hotkeyTitle),
            action: nil,
            keyEquivalent: ""
        )
        hotkeyItem.isEnabled = false
        menu.addItem(hotkeyItem)

        menu.addItem(.separator())

        let micItem = NSMenuItem(title: L10n.t("Microphone"), action: nil, keyEquivalent: "")
        micItem.submenu = buildAudioMenu()
        menu.addItem(micItem)

        let insertItem = NSMenuItem(title: L10n.t("Insertion"), action: nil, keyEquivalent: "")
        insertItem.submenu = buildInsertionMenu()
        menu.addItem(insertItem)

        let modelTitle: String = asrState.isLoading
            ? L10n.t("Model: compiling… %d s", Int32(clamping: asrState.loadingSeconds))
            : L10n.t("Model: %@", asrState.modelTitle)
        let modelItem = NSMenuItem(title: modelTitle, action: nil, keyEquivalent: "")
        modelItem.submenu = buildModelMenu()
        menu.addItem(modelItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: L10n.t("Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        if !Permissions.microphoneGranted {
            let micItem = NSMenuItem(
                title: L10n.t("Microphone access…"),
                action: #selector(requestMicrophone),
                keyEquivalent: ""
            )
            micItem.target = self
            menu.addItem(micItem)
        }

        if !Permissions.accessibilityGranted {
            let permissionItem = NSMenuItem(
                title: L10n.t("Grant Accessibility access…"),
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            permissionItem.target = self
            menu.addItem(permissionItem)
        }

        let updatesItem = NSMenuItem(
            title: L10n.t("Check for Updates…"),
            action: #selector(checkUpdates),
            keyEquivalent: ""
        )
        updatesItem.target = self
        menu.addItem(updatesItem)

        let aboutItem = NSMenuItem(
            title: L10n.t("About PerfectWhisper"),
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.t("Quit PerfectWhisper"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func buildInsertionMenu() -> NSMenu {
        let submenu = NSMenu()
        let current = Defaults.insertMode
        for mode in InsertMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(selectInsertMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            let allowed = mode == .clipboardOnly || Permissions.accessibilityGranted
            item.isEnabled = allowed
            item.state = (mode == current) || (!Permissions.accessibilityGranted && mode == .clipboardOnly)
                ? .on
                : .off
            submenu.addItem(item)
        }
        return submenu
    }

    private func buildAudioMenu() -> NSMenu {
        let submenu = NSMenu()
        let preferred = Defaults.inputDeviceUID

        let autoItem = NSMenuItem(
            title: L10n.t("Automatic (system default)"),
            action: #selector(selectAudioInput(_:)),
            keyEquivalent: ""
        )
        autoItem.target = self
        autoItem.representedObject = ""
        autoItem.state = preferred == nil ? .on : .off
        submenu.addItem(autoItem)

        if !deviceManager.devices.isEmpty {
            submenu.addItem(.separator())
            for device in deviceManager.devices {
                let isDefault = device.id == deviceManager.defaultDeviceUID
                let item = NSMenuItem(
                    title: isDefault ? L10n.t("%@ (default)", device.name) : device.name,
                    action: #selector(selectAudioInput(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = device.id
                item.state = preferred == device.id ? .on : .off
                submenu.addItem(item)
            }
        }

        if deviceManager.preferredDeviceMissing {
            submenu.addItem(.separator())
            let note = NSMenuItem(
                title: L10n.t("Selected microphone is unavailable — using system default"),
                action: nil,
                keyEquivalent: ""
            )
            note.isEnabled = false
            submenu.addItem(note)
        }

        return submenu
    }

    private func buildModelMenu() -> NSMenu {
        let submenu = NSMenu()
        repository.refresh()

        if repository.installed.isEmpty {
            let empty = NSMenuItem(
                title: L10n.t("No models installed"),
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for model in repository.installed {
                let title = ModelCatalog.variant(id: model.title)?.title ?? model.title
                let item = NSMenuItem(
                    title: title,
                    action: #selector(selectInstalledModel(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = model.folder.path
                item.state = repository.isCurrent(model.folder) ? .on : .off
                submenu.addItem(item)
            }
        }

        submenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: L10n.t("Model settings…"),
            action: #selector(openModelSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        submenu.addItem(settingsItem)

        return submenu
    }

    // MARK: - Actions

    @objc private func toggleDictation() {
        onToggle()
        updateIcon()
    }

    @objc private func selectAudioInput(_ sender: NSMenuItem) {
        onSelectAudioInput(sender.representedObject as? String ?? "")
    }

    @objc private func selectInsertMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        onSelectInsertMode(raw)
    }

    @objc private func selectInstalledModel(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        onSelectModel(URL(fileURLWithPath: path))
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func openModelSettings() {
        onOpenModelSettings()
    }

    @objc private func requestMicrophone() {
        onRequestMicrophone()
    }

    @objc private func checkUpdates() {
        onCheckUpdates()
    }

    @objc private func showAbout() {
        onAbout()
    }

    @objc private func openAccessibilitySettings() {
        onOpenAccessibilitySettings()
    }

    @objc private func quit() {
        onQuit()
    }
}
