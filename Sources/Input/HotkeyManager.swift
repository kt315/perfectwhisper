import Cocoa

/// Global hotkey via CGEventTap.
///
/// Requires Accessibility. Without the permission, `start()` returns false —
/// the caller must surface that to the user explicitly.
/// CFMachPort and CFRunLoopSource aren't Sendable, but they live on the tap thread.
private final class TapContext: @unchecked Sendable {
    let tap: CFMachPort
    let source: CFRunLoopSource

    init(tap: CFMachPort, source: CFRunLoopSource) {
        self.tap = tap
        self.source = source
    }
}

final class HotkeyManager: @unchecked Sendable {
    /// Called on the main thread.
    var onTrigger: (@Sendable () -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    // Read from the callback on the tap thread.
    private nonisolated(unsafe) var keyCode: CGKeyCode = CGKeyCode(Defaults.defaultKeyCode)
    private nonisolated(unsafe) var requiredFlags: CGEventFlags = CGEventFlags(rawValue: UInt64(Defaults.defaultModifiers))
    private nonisolated(unsafe) var isDoubleMode = false
    private nonisolated(unsafe) var doubleModifier = "fn"
    private nonisolated(unsafe) var pressStarted: Date?
    private nonisolated(unsafe) var lastTapDate: Date?

    private static let relevantFlags: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn
    ]

    var isRunning: Bool { tap != nil }

    deinit { stop() }

    func update(keyCode: CGKeyCode, flags: CGEventFlags) {
        self.keyCode = keyCode
        self.requiredFlags = flags.intersection(Self.relevantFlags)
    }

    func reloadFromDefaults() {
        isDoubleMode = Defaults.hotkeyKind == "doubleMod"
        doubleModifier = Defaults.doubleModifier
        pressStarted = nil
        lastTapDate = nil
        update(keyCode: CGKeyCode(Defaults.hotkeyKeyCode), flags: Defaults.hotkeyFlags)
        Log.info("hotkey: mode=\(isDoubleMode ? "double tap" : "combination")")
    }

    @discardableResult
    func start() -> Bool {
        stop()
        reloadFromDefaults()

        guard Permissions.accessibilityGranted else { return false }

        var mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        if isDoubleMode {
            mask |= CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.error("CGEventTap not created (no Accessibility?)")
            return false
        }

        self.tap = tap
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            stop()
            return false
        }
        runLoopSource = source

        // Dedicated thread: if the main one is busy (a dialog, model loading), the tap
        // must not slow down input across the whole system.
        let context = TapContext(tap: tap, source: source)
        let thread = Thread { [weak self, context] in
            guard let self else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), context.source, .commonModes)
            CGEvent.tapEnable(tap: context.tap, enable: true)
            Log.info("hotkey thread started")
            CFRunLoopRun()
        }
        thread.name = "PerfectWhisper.hotkey"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        return true
    }

    /// Double tap of a modifier (Fn, right Option, right Command).
    /// We don't swallow the event so that a single Fn keeps working as usual.
    private func handleDoubleModifier(_ event: CGEvent) -> Bool {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        let expectedKeyCode: CGKeyCode
        let flag: CGEventFlags
        switch doubleModifier {
        case "leftOption":
            expectedKeyCode = 58 // kVK_Option
            flag = .maskAlternate
        case "rightOption":
            expectedKeyCode = 61 // kVK_RightOption
            flag = .maskAlternate
        case "leftCommand":
            expectedKeyCode = 55 // kVK_Command
            flag = .maskCommand
        case "rightCommand":
            expectedKeyCode = 54 // kVK_RightCommand
            flag = .maskCommand
        default:
            expectedKeyCode = 63 // kVK_Function
            flag = .maskSecondaryFn
        }

        guard keyCode == expectedKeyCode else { return false }

        let now = Date()
        let isDown = event.flags.contains(flag)

        if isDown {
            pressStarted = now
            return false
        }

        guard let started = pressStarted else { return false }
        pressStarted = nil

        // A long hold is not a "tap".
        guard now.timeIntervalSince(started) < 0.5 else {
            lastTapDate = nil
            return false
        }

        if let last = lastTapDate, now.timeIntervalSince(last) < 0.55 {
            lastTapDate = nil
            let handler = onTrigger
            DispatchQueue.main.async { handler?() }
        } else {
            lastTapDate = now
        }
        return true
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let tapRunLoop {
            CFRunLoopStop(tapRunLoop)
        }
        runLoopSource = nil
        tap = nil
        tapThread = nil
        tapRunLoop = nil
        Log.info("hotkey tap stopped")
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if Permissions.accessibilityGranted, let tap {
                Log.info("tap disabled by the system, re-enabling")
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                // Permission was revoked: back off quietly, otherwise the keyboard hangs.
                Log.info("tap disabled without permission — stopping")
                DispatchQueue.main.async { self.stop() }
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged, isDoubleMode {
            _ = handleDoubleModifier(event)
            return Unmanaged.passUnretained(event)
        }

        // In double-tap mode the regular combination must not fire.
        if isDoubleMode {
            return Unmanaged.passUnretained(event)
        }

        let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags.intersection(Self.relevantFlags)

        guard eventKeyCode == keyCode, flags == requiredFlags else {
            return Unmanaged.passUnretained(event)
        }

        // Key auto-repeat while holding must not retrigger dictation.
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
            return nil
        }

        let handler = onTrigger
        DispatchQueue.main.async { handler?() }
        return nil // the event doesn't reach the active app
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handle(type: type, event: event)
}
