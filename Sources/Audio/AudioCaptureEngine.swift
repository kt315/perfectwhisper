import AVFoundation
import CoreAudio
import Foundation

enum AudioCaptureError: LocalizedError {
    case noInputDevice
    case converterUnavailable
    case engineStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return L10n.t("No input audio device found")
        case .converterUnavailable:
            return L10n.t("Could not create audio converter")
        case .engineStartFailed(let message):
            return L10n.t("Could not start recording: %@", message)
        }
    }
}

/// Captures the microphone into memory, converted to 16 kHz mono Float32 —
/// exactly the format Whisper expects.
final class AudioCaptureEngine: @unchecked Sendable {
    static let targetSampleRate: Double = 16_000

    /// Right after start AVAudioEngine sends a ConfigurationChange
    /// (it "rebuilds" the graph for the selected device). That is not a recording break.
    private static let startGracePeriod: TimeInterval = 1.2
    /// If there are no buffers for longer than this — assume the engine quietly died.
    private static let stallTimeout: TimeInterval = 1.5

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private let stallQueue = DispatchQueue(label: "com.kt315.perfectwhisper.audio.stall")

    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var isRunning = false
    private var lastStartDate: Date?
    private var lastBufferDate: Date?
    private var currentDeviceID: AudioDeviceID?
    private var lastLevelTime = Date.distantPast
    private var smoothedLevel: Float = 0
    private var configObserver: NSObjectProtocol?
    private var stallTimer: DispatchSourceTimer?
    private var didLogFirstBuffer = false
    private var didLogConversionError = false

    /// Signal level 0…1, delivered from the audio thread.
    var onLevel: (@Sendable (Float) -> Void)?
    /// Recording was interrupted because the audio device changed.
    /// We pass along the samples captured so far so nothing said is lost.
    var onCaptureInterrupted: (@Sendable ([Float]) -> Void)?

    init() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
    }

    deinit {
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
        }
        stallTimer?.cancel()
    }

    private var isRunningNow: Bool {
        lock.lock(); defer { lock.unlock() }
        return isRunning
    }

    // MARK: - Recording

    /// - Parameter deviceID: a specific input device; nil — the system default.
    func start(deviceID: AudioDeviceID?) throws {
        if isRunningNow { _ = stop() }

        lock.lock()
        samples.removeAll(keepingCapacity: true)
        didLogFirstBuffer = false
        didLogConversionError = false
        lastBufferDate = nil
        lock.unlock()

        try configure(deviceID: deviceID)
        try startEngine()
        startStallMonitor()
    }

    /// Stops recording and returns the accumulated samples.
    @discardableResult
    func stop() -> [Float] {
        guard isRunningNow else { return [] }
        stallTimer?.cancel()
        stallTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        lock.lock()
        isRunning = false
        lastStartDate = nil
        lastBufferDate = nil
        currentDeviceID = nil
        converter = nil
        let result = samples
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
        Log.info("audio stopped: \(result.count) samples, \(String(format: "%.2f", Double(result.count) / Self.targetSampleRate)) s")
        return result
    }

    // MARK: - Graph setup

    private func configure(deviceID: AudioDeviceID?) throws {
        let input = engine.inputNode

        if let deviceID {
            input.withAudioUnit { audioUnit in
                guard let audioUnit else { return }
                var id = deviceID
                let status = AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &id,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                if status != noErr {
                    Log.error("failed to select audio device (status \(status))")
                }
            }
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            Log.error("no input device: format \(inputFormat.sampleRate) Hz / \(inputFormat.channelCount) ch")
            throw AudioCaptureError.noInputDevice
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ), let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            Log.error("failed to create converter \(inputFormat.sampleRate) Hz / \(inputFormat.channelCount) ch")
            throw AudioCaptureError.converterUnavailable
        }
        newConverter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Normal
        newConverter.sampleRateConverterQuality = AVAudioQuality.high.rawValue

        lock.lock()
        converter = newConverter
        currentDeviceID = deviceID
        lock.unlock()

        input.removeTap(onBus: 0)
        // The new API requires a buffer size of 100–400 ms.
        let tapBufferSize = AVAudioFrameCount(inputFormat.sampleRate * 0.1)
        try input.installAudioTap(onBus: 0, bufferSize: tapBufferSize, format: inputFormat) { [weak self] readOnly, _ in
            let buffer = AVAudioPCMBuffer(copying: readOnly)
            self?.process(buffer)
        }

        engine.prepare()
        Log.info("audio graph: \(Int(inputFormat.sampleRate)) Hz, \(inputFormat.channelCount) ch → 16000 Hz mono, deviceID=\(deviceID.map(String.init) ?? "auto")")
    }

    private func startEngine() throws {
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            lock.lock(); converter = nil; lock.unlock()
            Log.error("engine.start() failed: \(error.localizedDescription)")
            throw AudioCaptureError.engineStartFailed(error.localizedDescription)
        }

        lock.lock()
        isRunning = true
        lastStartDate = Date()
        lastBufferDate = Date()
        lock.unlock()
        Log.info("recording started")
    }

    // MARK: - Watchdog timer

    /// Catches the "engine thinks it is recording but there are no buffers" case:
    /// Bluetooth switched, the device went to sleep, the graph fell apart.
    private func startStallMonitor() {
        stallTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: stallQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self, self.isRunningNow else { return }
            self.lock.lock()
            let last = self.lastBufferDate
            self.lock.unlock()
            guard let last else { return }

            let silence = Date().timeIntervalSince(last)
            guard silence > Self.stallTimeout else { return }

            Log.error("no audio buffers for \(String(format: "%.1f", silence)) s — restarting capture")
            DispatchQueue.main.async {
                guard self.isRunningNow else { return }
                if self.resume() { return }
                let captured = self.stop()
                self.onCaptureInterrupted?(captured)
            }
        }
        timer.resume()
        stallTimer = timer
    }

    // MARK: - Handling configuration changes

    private func handleConfigurationChange() {
        guard isRunningNow else { return }

        lock.lock()
        let startedAt = lastStartDate
        lock.unlock()
        let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0

        // The first event after start is normal graph initialization.
        if elapsed < Self.startGracePeriod {
            Log.info("audio configuration changed after \(String(format: "%.2f", elapsed)) s — that's initialization, ignoring")
            return
        }
        Log.info("audio configuration changed after \(String(format: "%.1f", elapsed)) s — trying to continue")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.isRunningNow else { return }
            if self.resume() { return }
            let captured = self.stop()
            self.onCaptureInterrupted?(captured)
        }
    }

    /// Rebuilds the graph without losing what was recorded.
    private func resume() -> Bool {
        lock.lock()
        let deviceID = currentDeviceID
        lock.unlock()

        if attemptResume(deviceID: deviceID) { return true }

        // The explicitly selected microphone disappeared (headphones unplugged, headset disconnected).
        // Don't cut the dictation short — continue with the system default.
        if deviceID != nil, attemptResume(deviceID: nil) {
            Log.info("selected microphone disappeared, continued with the system default")
            return true
        }

        return false
    }

    private func attemptResume(deviceID: AudioDeviceID?) -> Bool {
        do {
            try configure(deviceID: deviceID)
            try startEngine()
            Log.info("capture restored")
            return true
        } catch {
            Log.error("failed to resume recording: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Audio stream

    private func process(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard let converter else { lock.unlock(); return }
        let targetFormat = converter.outputFormat
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            lock.unlock(); return
        }

        var provided = false
        var conversionError: NSError?
        let source = buffer
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if provided {
                inputStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            inputStatus.pointee = .haveData
            return source
        }

        guard status != .error, conversionError == nil, output.frameLength > 0,
              let channel = output.floatChannelData?[0] else {
            let shouldLog = !didLogConversionError
            if shouldLog { didLogConversionError = true }
            lock.unlock()
            if shouldLog {
                Log.error("audio conversion failed: status=\(status.rawValue), error=\(conversionError?.localizedDescription ?? "nil")")
            }
            return
        }

        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        samples.append(contentsOf: chunk)
        lastBufferDate = Date()

        let firstBuffer = !didLogFirstBuffer
        if firstBuffer { didLogFirstBuffer = true }

        let now = Date()
        let shouldReportLevel = now.timeIntervalSince(lastLevelTime) > 0.05
        if shouldReportLevel { lastLevelTime = now }
        lock.unlock()

        if firstBuffer {
            Log.info("first audio buffer received")
        }
        if shouldReportLevel {
            let meanSquare = chunk.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(chunk.count, 1))
            let rms = meanSquare.squareRoot()
            let db = 20 * log10(max(rms, 0.000_01))

            // Working range of ordinary speech: roughly −55…−15 dB.
            let normalized = min(1, max(0, (db + 55) / 40))
            // Perceptual curve: quiet sounds should still produce noticeable movement.
            let target = pow(normalized, 0.55)

            // Rise fast, fall smoothly — no jitter.
            smoothedLevel = target > smoothedLevel ? target : smoothedLevel * 0.82
            onLevel?(min(1, smoothedLevel))
        }
    }
}
