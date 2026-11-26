#if DEBUG
import AVFoundation
import Foundation
import WhisperKit

/// Debug mode without UI: transcribe an audio file and print the result with timings.
/// Usage: `PerfectWhisper.app/Contents/MacOS/PerfectWhisper --transcribe /path/audio.wav`
enum TranscribeHarness {
    static func run(path: String) async {
        await run(paths: [path])
    }

    /// Several files in one process: the app keeps the model resident across
    /// dictations, so stale state has to be reproducible here as well.
    static func run(paths: [String]) async {
        Defaults.registerDefaults()
        for path in paths where !FileManager.default.fileExists(atPath: path) {
            print("File not found: \(path)")
            return
        }
        guard let folder = ModelResolver.currentFolder() else {
            print("Model not found — download it in the Model tab.")
            return
        }

        print("Model: \(folder.lastPathComponent)")
        do {
            let loadStart = Date()
            let config = WhisperKitConfig(
                modelFolder: folder.path,
                verbose: false,
                logLevel: .error,
                prewarm: false,
                load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            print(String(format: "Model load: %.1f s", Date().timeIntervalSince(loadStart)))

            var options = DecodingOptions(
                language: nil,
                usePrefillPrompt: true,
                detectLanguage: true,
                skipSpecialTokens: true,
                withoutTimestamps: false
            )
            let prompt = CommandLine.arguments.contains("--no-prompt")
                ? ""
                : UserDefaults.standard.string(forKey: PrefKey.initialPrompt) ?? ""
            if !prompt.isEmpty, let tokenizer = kit.tokenizer {
                options.promptTokens = tokenizer.encode(text: " " + prompt)
            }

            if CommandLine.arguments.contains("--no-timestamps") {
                options.withoutTimestamps = true
            }
            if CommandLine.arguments.contains("--words") {
                options.wordTimestamps = true
                options.withoutTimestamps = false
            }

            for path in paths {
                print("\n=== \(URL(fileURLWithPath: path).lastPathComponent) ===")
                let start = Date()
                let results: [TranscriptionResult]
                if CommandLine.arguments.contains("--samples") {
                    // Same path as in the app: an array of samples rather than a file.
                    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
                    let format = file.processingFormat
                    guard let buffer = AVAudioPCMBuffer(
                        pcmFormat: format,
                        frameCapacity: AVAudioFrameCount(file.length)
                    ) else { throw TranscriberError.emptyAudio }
                    try file.read(into: buffer)
                    var samples = Array(UnsafeBufferPointer(
                        start: buffer.floatChannelData![0],
                        count: Int(buffer.frameLength)
                    ))
                    let seconds = Double(samples.count) / format.sampleRate
                    print("samples: \(samples.count), \(String(format: "%.2f", seconds)) s")
                    if CommandLine.arguments.contains("--trim") {
                        samples = SilenceTrimmer.trim(samples)
                        print(String(format: "trimmed: %.2f s", Double(samples.count) / format.sampleRate))
                    }
                    results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
                } else {
                    results = try await kit.transcribe(audioPath: path, decodeOptions: options)
                }
                let elapsed = Date().timeIntervalSince(start)

                let text = results.map(\.text).joined(separator: " ")
                print(String(format: "Transcription: %.2f s", elapsed))
                print("Language: \(results.first?.language ?? "?")")
                if CommandLine.arguments.contains("--words") {
                    for (index, segment) in results.flatMap({ $0.segments }).enumerated() {
                        print(String(format: "segment %d: %.2f–%.2f  %@", index, segment.start, segment.end, segment.text))
                        for word in segment.words ?? [] {
                            print(String(format: "   %@  %.2f–%.2f", word.word, word.start, word.end))
                        }
                    }
                }
                print("Text: \(TextPostprocessor.clean(text))")
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
}
#endif
