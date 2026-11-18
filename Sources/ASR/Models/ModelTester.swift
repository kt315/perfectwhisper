import Foundation

/// Model check on a live sample: synthesize a phrase with the system voice,
/// recognize it with the selected model and return the result.
enum ModelTester {
    struct Result: Sendable {
        let text: String
        let seconds: Double
    }

    static func run(
        model: InstalledModel,
        transcriber: WhisperKitTranscriber
    ) async throws -> Result {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("perfectwhisper-test-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: temporary) }

        try await synthesize(to: temporary)

        guard FileManager.default.fileExists(atPath: temporary.path) else {
            throw TranscriberError.emptyAudio
        }

        let output = try await transcriber.transcribeFile(
            path: temporary.path,
            language: Defaults.language,
            prompt: Defaults.initialPrompt
        )
        return Result(
            text: TextPostprocessor.clean(output.text),
            seconds: output.seconds
        )
    }

    /// `say` takes a couple of seconds — run it off the main thread.
    private static func synthesize(to url: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = [
            "-o", url.path,
            "Привет! Это проверка модели PerfectWhisper. Mixed English words: pull request, OpenCode, CoreML.",
        ]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
