import AppKit
import Foundation

/// Dictation state machine: recording → transcription → insertion.
@MainActor
final class DictationController {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
    }

    private let audio: AudioCaptureEngine
    private let transcriber: WhisperKitTranscriber
    private let hud: HUDController
    private let devices: AudioDeviceManager
    private let inserter = TextInserter()

    private(set) var phase: Phase = .idle
    private var startedAt: Date?

    /// Called when setup is needed (no model / no permission).
    var onNeedsSetup: (() -> Void)?
    /// Called on every phase change (for the status bar icon).
    var onPhaseChanged: (() -> Void)?
    var onMicrophonePermissionNeeded: (() -> Void)?

    init(
        audio: AudioCaptureEngine,
        transcriber: WhisperKitTranscriber,
        hud: HUDController,
        devices: AudioDeviceManager
    ) {
        self.audio = audio
        self.transcriber = transcriber
        self.hud = hud
        self.devices = devices
        wireAudioCallbacks()
    }

    var isRecording: Bool { phase == .recording }

    // MARK: - Control

    func toggle() {
        switch phase {
        case .idle: start()
        case .recording: finish()
        case .transcribing: break // don't disturb the ongoing transcription
        }
    }

    func start() {
        guard phase == .idle else { return }

        Log.info("start: microphone status=\(Permissions.microphoneStatus.rawValue)")
        switch Permissions.microphoneStatus {
        case .authorized:
            beginRecording()
        case .notDetermined:
            onMicrophonePermissionNeeded?()
        default:
            showPermissionProblem()
        }
    }

    func finish() {
        guard phase == .recording else { return }
        playSound("Pop")

        let samples = audio.stop()
        startedAt = nil
        setPhase(.transcribing)
        hud.update(phase: .transcribing)

        let duration = Double(samples.count) / AudioCaptureEngine.targetSampleRate
        Log.info("end of dictation: \(String(format: "%.2f", duration)) s of audio")
        guard duration >= Defaults.minDuration else {
            setPhase(.idle)
            Log.error("recording too short (\(String(format: "%.2f", duration)) s) — cancelling")
            hud.flash(L10n.t("Too short"), isError: true)
            return
        }

        Task { await self.transcribe(samples: samples) }
    }

    /// Recording was interrupted (e.g. headphones were unplugged): don't lose what we captured.
    func handleInterruption(samples: [Float]) {
        guard phase == .recording else { return }
        Log.error("recording interrupted externally: \(String(format: "%.2f", Double(samples.count) / AudioCaptureEngine.targetSampleRate)) s of audio")
        startedAt = nil
        setPhase(.transcribing)

        let duration = Double(samples.count) / AudioCaptureEngine.targetSampleRate
        guard duration >= Defaults.minDuration else {
            setPhase(.idle)
            hud.flash(L10n.t("Audio device changed"), isError: true)
            return
        }

        hud.update(phase: .transcribing)
        Task {
            await self.transcribe(samples: samples)
            self.hud.flash(L10n.t("Audio device changed — transcribed what was captured"), isError: true, duration: .milliseconds(1800))
        }
    }

    // MARK: - Model

    func prepareModelIfPossible() {
        guard let folder = ModelResolver.currentFolder() else {
            Log.error("model not found, skipping load")
            return
        }
        Log.info("loading model from \(folder.path)")
        Task {
            do {
                try await transcriber.prepare(folder: folder)
                Log.info("model ready")
            } catch is CancellationError {
                // Superseded by a newer model selection; the new load takes over.
                Log.info("model load superseded")
            } catch {
                Log.error("model failed to load: \(error.localizedDescription)")
                hud.flash(L10n.t("Model failed to load"), isError: true, duration: .milliseconds(2200))
            }
        }
    }

    func reloadModel() {
        transcriber.unload()
        prepareModelIfPossible()
    }

    // MARK: - Internals

    private func beginRecording() {
        guard ModelResolver.currentFolder() != nil else {
            hud.flash(L10n.t("Download a model first"), isError: true, duration: .milliseconds(2200))
            onNeedsSetup?()
            return
        }

        // No point recording without a model: the audio would be lost.
        // Show the current engine status instead (compiling, failed, not loaded).
        guard transcriber.isLoaded else {
            hud.flash(
                "\(L10n.t("Model not ready"))\n\(transcriber.state.status)",
                isError: true,
                duration: .milliseconds(2800)
            )
            Log.info("dictation blocked: model not ready (\(transcriber.state.status))")
            return
        }

        let preferredUID = Defaults.inputDeviceUID
        let effectiveUID = devices.effectiveUID(preferred: preferredUID)
        let deviceID = devices.device(withUID: effectiveUID)?.deviceID
        let deviceName = devices.device(withUID: effectiveUID)?.name ?? "system"
        Log.info(
            "dictation start: microphone=\(deviceName), mode=\(Defaults.insertMode.rawValue), language=\(Defaults.language)"
        )

        do {
            try audio.start(deviceID: deviceID)
        } catch {
            Log.error("audio.start() failed: \(error.localizedDescription)")
            hud.flash(error.localizedDescription, isError: true, duration: .milliseconds(2400))
            return
        }

        setPhase(.recording)
        startedAt = Date()
        playSound("Tink")
        hud.show(phase: .recording)
    }

    private func transcribe(samples: [Float]) async {
        guard let folder = ModelResolver.currentFolder() else {
            setPhase(.idle)
            hud.flash(L10n.t("Model not found"), isError: true)
            return
        }

        do {
            if !transcriber.isLoaded {
                hud.update(phase: .loading(L10n.t("Compiling model…")))
                try await transcriber.prepare(folder: folder)
                hud.update(phase: .transcribing)
            }

            let prompt = Defaults.initialPrompt
            let output = try await transcriber.transcribe(
                samples: samples,
                language: Defaults.language,
                prompt: prompt
            )

            let text = TextPostprocessor.clean(output.text)
            Log.info(
                "recognized: \(text.count) characters, language=\(output.detectedLanguage), \(String(format: "%.2f", output.seconds)) s for \(String(format: "%.1f", Double(samples.count) / AudioCaptureEngine.targetSampleRate)) s of audio"
            )
            Log.info("result [\(output.detectedLanguage)]: \(text)")
            if text.isEmpty {
                Log.error("transcription returned empty text")
                hud.flash(L10n.t("Nothing recognized"), isError: true)
            } else {
                // Without Accessibility neither synthetic ⌘V nor synthetic keystrokes
                // reach other apps — rather than pretend we inserted, put the text on
                // the clipboard and say so.
                let requestedMode = Defaults.insertMode
                let effectiveMode: InsertMode =
                    (requestedMode != .clipboardOnly && !Permissions.accessibilityGranted)
                    ? .clipboardOnly
                    : requestedMode

                Log.info("insert: mode=\(effectiveMode.rawValue), accessibility=\(Permissions.accessibilityGranted)")

                let outcome = await inserter.insert(
                    text,
                    mode: effectiveMode,
                    trailingSpace: Defaults.trailingSpace
                )

                switch outcome {
                case .inserted:
                    // Text is already in the editor — don't get in the user's way.
                    hud.hide()
                case .clipboard:
                    let fallback = effectiveMode != requestedMode
                    hud.showNotice(
                        title: fallback
                            ? L10n.t("No Accessibility — text is in clipboard")
                            : L10n.t("Copied to clipboard"),
                        body: preview(text),
                        isError: fallback
                    )
                }
            }
            Log.info(
                String(
                    format: "%.2f s of audio → %.2f s of transcription, language: %@",
                    Double(samples.count) / AudioCaptureEngine.targetSampleRate,
                    output.seconds,
                    output.detectedLanguage
                )
            )
        } catch {
            hud.flash(L10n.t("Error: %@", error.localizedDescription), isError: true, duration: .milliseconds(2600))
        }

        setPhase(.idle)
    }

    private func setPhase(_ newPhase: Phase) {
        guard phase != newPhase else { return }
        Log.info("phase: \(String(describing: phase)) → \(String(describing: newPhase))")
        phase = newPhase
        onPhaseChanged?()
    }

    private func wireAudioCallbacks() {
        audio.onLevel = { [weak self] level in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                self.hud.setLevel(level)
            }
        }
        audio.onCaptureInterrupted = { [weak self] samples in
            Task { @MainActor in self?.handleInterruption(samples: samples) }
        }
    }

    private func showPermissionProblem() {
        hud.flash(L10n.t("No microphone access"), isError: true, duration: .milliseconds(2400))
        Permissions.openMicrophoneSettings()
    }

    private func playSound(_ name: String) {
        guard Defaults.soundsEnabled else { return }
        NSSound(named: name)?.play()
    }

    private func preview(_ text: String) -> String {
        let limit = 300
        if text.count <= limit { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
