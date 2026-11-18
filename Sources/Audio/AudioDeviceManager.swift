import CoreAudio
import Foundation
import Observation

/// An input audio device in CoreAudio terms.
struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let id: String        // device UID, stable across restarts
    let name: String
    let deviceID: AudioDeviceID
}

/// Enumeration of input devices, hot-plug tracking, and the system default.
@MainActor
@Observable
final class AudioDeviceManager {
    private(set) var devices: [AudioInputDevice] = []
    private(set) var defaultDeviceUID: String?

    /// Called when the device list changes (to rebuild the menu).
    var onChange: (() -> Void)?

    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var started = false

    init() {
        refresh()
    }

    // MARK: - Public API

    func refresh() {
        devices = Self.enumerateInputDevices()
        defaultDeviceUID = Self.defaultInputDevice().flatMap { Self.deviceUID(for: $0) }
        onChange?()
    }

    /// The device with the given UID, or nil if it's gone.
    func device(withUID uid: String?) -> AudioInputDevice? {
        guard let uid else { return nil }
        return devices.first { $0.id == uid }
    }

    /// The UID actually used for recording: the explicit choice,
    /// or the system default if there is none.
    func effectiveUID(preferred: String?) -> String? {
        if let device = device(withUID: preferred) {
            return device.id
        }
        return defaultDeviceUID
    }

    var preferredDeviceMissing: Bool {
        guard let preferred = Defaults.inputDeviceUID else { return false }
        return device(withUID: preferred) == nil
    }

    // MARK: - Observation

    func startObserving() {
        guard !started else { return }
        started = true

        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = Self.systemAddress(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                Task { @MainActor in self?.refresh() }
            }
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
            )
            if status == noErr {
                listeners.append((address, block))
            }
        }
    }

    func stopObserving() {
        for (address, block) in listeners {
            var addr = address
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block
            )
        }
        listeners.removeAll()
        started = false
    }

    // MARK: - CoreAudio

    private static func systemAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func defaultInputDevice() -> AudioDeviceID? {
        var address = systemAddress(kAudioHardwarePropertyDefaultInputDevice)
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return status == noErr && deviceID != 0 ? deviceID : nil
    }

    static func enumerateInputDevices() -> [AudioInputDevice] {
        var address = systemAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids.compactMap { id in
            guard inputChannelCount(id) > 0,
                  let uid = deviceUID(for: id),
                  !isAggregateOrHidden(deviceID: id, uid: uid) else { return nil }
            return AudioInputDevice(
                id: uid,
                name: deviceName(for: id) ?? L10n.t("Audio device %@", String(id)),
                deviceID: id
            )
        }
    }

    /// Virtual aggregate devices (`CADefaultDeviceAggregate-*`) and
    /// hidden system devices aren't microphones, so they don't belong in the list.
    private static func isAggregateOrHidden(deviceID: AudioDeviceID, uid: String) -> Bool {
        if uid.hasPrefix("CADefaultDeviceAggregate") { return true }
        if deviceName(for: deviceID)?.hasPrefix("CADefaultDeviceAggregate") == true { return true }

        var address = systemAddress(kAudioDevicePropertyIsHidden)
        var hidden: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &hidden)
        return status == noErr && hidden != 0
    }

#if DEBUG
    /// Debug: everything CoreAudio considers an input device, including hidden ones.
    static func debugDumpAllInputDevices() -> [String] {
        var address = systemAddress(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        var lines: [String] = []
        for id in ids {
            let channels = inputChannelCount(id)
            let name = deviceName(for: id) ?? "?"
            let uid = deviceUID(for: id) ?? "?"
            let hidden = isHidden(id)
            let transport = transportType(id)
            lines.append(
                "\(name) | uid=\(uid) | transport=\(transport) | in=\(channels) | hidden=\(hidden)"
            )
        }
        return lines
    }

#endif

    static func isHidden(_ deviceID: AudioDeviceID) -> Bool {
        var address = systemAddress(kAudioDevicePropertyIsHidden)
        var hidden: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &hidden)
        return status == noErr && hidden != 0
    }

    static func transportType(_ deviceID: AudioDeviceID) -> String {
        var address = systemAddress(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr else {
            return "?"
        }
        let bytes = [
            UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "?"
    }

    static func inputChannelCount(_ deviceID: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return 0
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, raw) == noErr else {
            return 0
        }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var address = systemAddress(kAudioDevicePropertyDeviceUID)
        var cfString: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &cfString) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value = cfString else { return nil }
        return value as String
    }

    static func deviceName(for deviceID: AudioDeviceID) -> String? {
        var address = systemAddress(kAudioDevicePropertyDeviceNameCFString)
        var cfString: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &cfString) { pointer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value = cfString else { return nil }
        return value as String
    }
}
