import Foundation
import Observation
import WhisperKit

/// Engine state observed by the UI.
@MainActor
@Observable
final class ASRState {
    var status: String = L10n.t("Model not loaded")
    var isReady: Bool = false
    var isLoading: Bool = false
    var modelTitle: String = "—"
    var loadedFolder: String?
    var lastLatency: Double?
    /// How many seconds the current load has been running (for UI progress).
    var loadingSeconds: Int = 0
}

enum TranscriberError: LocalizedError {
    case modelNotLoaded
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return L10n.t("Model is not loaded yet")
        case .emptyAudio: return L10n.t("Empty recording")
        }
    }
}

/// Wrapper around WhisperKit: keeps the model in memory and transcribes clips.
///
/// The model is loaded once and stays resident — otherwise every dictation
/// would pay for CoreML initialization.
final class WhisperKitTranscriber: @unchecked Sendable {
    /// Mutable engine state, always accessed through `engine.withLock`.
    private struct Engine {
        var kit: WhisperKit?
        var loadedPath: String?
        /// The load that owns the Core ML compiler right now. It stays here even
        /// after `unload()`: compilation cannot be aborted, so the next load has
        /// to wait for it instead of starting a second compile in parallel.
        var compileTask: Task<Void, Error>?
        var compileID: UUID?
        /// Incremented on unload; a load started earlier must not publish its result.
        var generation = 0
    }

    let state: ASRState

    private let engine = Locked(Engine())

    init(state: ASRState) {
        self.state = state
    }

    var isLoaded: Bool { engine.withLock { $0.kit != nil } }

    private var currentKit: WhisperKit? { engine.withLock { $0.kit } }

    /// Loads the model from the given folder (idempotent).
    ///
    /// The first load after installation, a macOS update or a signing change
    /// can take minutes: CoreML specializes the model for the specific chip.
    /// That's why we show a seconds counter so it doesn't look like a hang.
    func prepare(folder: URL) async throws {
        let path = folder.path

        // Core ML compilation cannot be interrupted, so a second request waits
        // for the running one instead of starting a parallel compilation.
        let scheduled: (task: Task<Void, Error>, id: UUID)? = engine.withLock { engine in
            if engine.kit != nil, engine.loadedPath == path { return nil }

            let previous = engine.compileTask
            let generation = engine.generation
            let id = UUID()

            let task = Task { [weak self] in
                if let previous { _ = try? await previous.value }
                guard let self else { return }
                defer {
                    // Cleared only when this task really finished compiling, so
                    // the next request can never overtake it. If nothing else is
                    // queued and the result was dropped by `unload()`, the UI
                    // goes back to "not loaded".
                    let reset = self.engine.withLock { engine -> Bool in
                        if engine.compileID == id {
                            engine.compileTask = nil
                            engine.compileID = nil
                        }
                        return engine.compileTask == nil
                            && engine.kit == nil
                            && engine.generation != generation
                    }
                    if reset { await self.showNotLoaded() }
                }
                try await self.load(folder: folder, generation: generation)
            }

            engine.compileTask = task
            engine.compileID = id
            return (task, id)
        }

        guard let scheduled else { return }
        try await scheduled.task.value
    }

    private func load(folder: URL, generation myGeneration: Int) async throws {
        let started = Date()

        await MainActor.run {
            self.state.isLoading = true
            self.state.loadingSeconds = 0
            self.state.status = L10n.t("Compiling model…")
        }

        let ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.state.loadingSeconds = Int(Date().timeIntervalSince(started))
                self.state.status = L10n.t("Compiling model… %d s", Int32(clamping: self.state.loadingSeconds))
            }
        }
        defer { ticker.cancel() }

        let config = WhisperKitConfig(
            modelFolder: folder.path,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )

        do {
            let loaded = try await WhisperKit(config)
            try Task.checkCancellation()
            let seconds = Date().timeIntervalSince(started)

            let published = engine.withLock { engine -> Bool in
                guard engine.generation == myGeneration else { return false }
                engine.kit = loaded
                engine.loadedPath = folder.path
                return true
            }
            guard published else { throw CancellationError() }

            let title = folder.lastPathComponent
                .replacingOccurrences(of: "openai_whisper-", with: "")
            await MainActor.run {
                self.state.isLoading = false
                self.state.isReady = true
                self.state.status = L10n.t("Model ready (%.1f s)", seconds)
                self.state.modelTitle = title
                self.state.loadedFolder = folder.path
            }
        } catch {
            let isCurrentLoad = engine.withLock { $0.generation == myGeneration }
            if isCurrentLoad {
                await MainActor.run {
                    self.state.isLoading = false
                    self.state.isReady = false
                    self.state.status = L10n.t("Load failed: %@", error.localizedDescription)
                }
            }
            throw error
        }
    }

    func unload() {
        let idle = engine.withLock { engine -> Bool in
            engine.generation += 1
            // Do not drop the task: Core ML keeps compiling after cancellation,
            // and the next load must still wait for it to finish.
            engine.compileTask?.cancel()
            engine.kit = nil
            engine.loadedPath = nil
            return engine.compileTask == nil
        }
        // While a compile is still winding down the UI is reset by that load.
        guard idle else { return }
        Task { await self.showNotLoaded() }
    }

    @MainActor
    private func showNotLoaded() {
        state.isReady = false
        state.isLoading = false
        state.loadingSeconds = 0
        state.status = L10n.t("Model not loaded")
        state.modelTitle = "—"
    }

    // MARK: - Recognition

    struct Word: Sendable {
        let text: String
        let start: Double
        let end: Double
        let probability: Float
    }

    struct Output: Sendable {
        let text: String
        let seconds: Double
        let detectedLanguage: String
        let words: [Word]
        let avgLogProb: Float
    }

    /// - Parameter language: nil or "auto" — auto-detect.
    func transcribe(
        samples: [Float],
        language: String?,
        prompt: String?,
        wordTimestamps: Bool = false
    ) async throws -> Output {
        guard let kit = currentKit else { throw TranscriberError.modelNotLoaded }
        guard !samples.isEmpty else { throw TranscriberError.emptyAudio }

        var options = decodingOptions(kit: kit, language: language, prompt: prompt)
        options.wordTimestamps = wordTimestamps
        if wordTimestamps {
            // Without timestamp tokens WhisperKit returns degenerate word timings
            // (all words at one point). They are needed for phrase-by-phrase freezing.
            options.withoutTimestamps = false
        }
        let started = Date()
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let seconds = Date().timeIntervalSince(started)
        await MainActor.run { self.state.lastLatency = seconds }
        return makeOutput(results, seconds: seconds, language: language)
    }

    /// Transcription of a ready-made file (used by the model test).
    func transcribeFile(path: String, language: String?, prompt: String?) async throws -> Output {
        guard let kit = currentKit else { throw TranscriberError.modelNotLoaded }

        let options = decodingOptions(kit: kit, language: language, prompt: prompt)
        let started = Date()
        let results = try await kit.transcribe(audioPath: path, decodeOptions: options)
        let seconds = Date().timeIntervalSince(started)
        await MainActor.run { self.state.lastLatency = seconds }
        return makeOutput(results, seconds: seconds, language: language)
    }

    private func decodingOptions(kit: WhisperKit, language: String?, prompt: String?) -> DecodingOptions {
        let isAuto = (language == nil || language == "auto")
        var options = DecodingOptions(
            language: isAuto ? nil : language,
            usePrefillPrompt: true,
            detectLanguage: isAuto,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )

        // initial_prompt: the main quality lever for mixed RU/EN speech.
        if let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let tokenizer = kit.tokenizer {
            var tokens = tokenizer.encode(text: " " + prompt)
            if tokens.count > 200 {
                tokens = Array(tokens.suffix(200))
            }
            options.promptTokens = tokens
        }
        return options
    }

    private func makeOutput(
        _ results: [TranscriptionResult],
        seconds: Double,
        language: String?
    ) -> Output {
        let isAuto = (language == nil || language == "auto")
        let text = results.map(\.text).joined(separator: " ")
        let detected = results.first?.language ?? (isAuto ? "?" : (language ?? "?"))
        let words: [Word] = results
            .flatMap { $0.segments }
            .flatMap { $0.words ?? [] }
            .map { Word(text: $0.word, start: Double($0.start), end: Double($0.end), probability: $0.probability) }
        let logProb = results.first?.segments.first?.avgLogprob ?? 0
        return Output(
            text: text,
            seconds: seconds,
            detectedLanguage: detected,
            words: words,
            avgLogProb: logProb
        )
    }
}

/// Minimal synchronous mutex wrapper.
///
/// Swift 6 rejects `NSLock.lock()`/`unlock()` inside async functions, so the
/// engine state is only touched through these synchronous closures. Nothing
/// awaits inside them, so the lock is never held across a suspension point.
private final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
