import AppKit
import Observation
import SwiftUI

/// Everything the settings window needs.
@MainActor
@Observable
final class AppEnvironment {
    let devices: AudioDeviceManager
    let asr: ASRState
    let repository: ModelRepository
    let transcriber: WhisperKitTranscriber

    var reloadModel: () -> Void = {}

    init(
        devices: AudioDeviceManager,
        asr: ASRState,
        repository: ModelRepository,
        transcriber: WhisperKitTranscriber
    ) {
        self.devices = devices
        self.asr = asr
        self.repository = repository
        self.transcriber = transcriber
    }
}
