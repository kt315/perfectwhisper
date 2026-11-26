import Foundation

/// File log for debugging.
///
/// Release builds have no logging at all: all writing code is compiled
/// only with the `PERFECTWHISPER_LOGGING` flag, which is enabled in Debug.
/// This also applies to dictation texts — in production they are never written anywhere.
enum Log {
    #if PERFECTWHISPER_LOGGING
    private static let queue = DispatchQueue(label: "com.kt315.perfectwhisper.log", qos: .utility)
    private static let maxBytes = 1_000_000

    static var fileURL: URL { Defaults.logsDirectory.appendingPathComponent("app.log") }

    static var isEnabled: Bool { true }

    static func info(_ message: String) { write("INFO", message) }
    static func error(_ message: String) { write("ERROR", message) }

    static func tail(lines: Int) -> String {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return "" }
        return text.split(separator: "\n").suffix(lines).joined(separator: "\n")
    }

    private static func write(_ level: String, _ message: String) {
        NSLog("PerfectWhisper: %@", message)
        queue.async {
            let directory = Defaults.logsDirectory
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = fileURL
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let line = "\(formatter.string(from: Date())) \(level) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? Int, size > maxBytes {
                try? FileManager.default.removeItem(at: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    #else

    static var isEnabled: Bool { false }

    static func info(_ message: String) {}
    static func error(_ message: String) {}
    static func tail(lines: Int) -> String { "" }

    #endif
}

#if PERFECTWHISPER_LOGGING
/// Debug-only: keeps the captured audio next to the log so the recognized text
/// can be compared with what the microphone actually heard. This type is not
/// compiled into release builds — audio is never written to disk there.
enum DebugAudio {
    static func save(_ samples: [Float], at date: Date = Date()) {
        guard !samples.isEmpty else { return }

        let directory = Defaults.logsDirectory.appendingPathComponent("recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = directory.appendingPathComponent("dictation-\(formatter.string(from: date)).wav")

        DispatchQueue.global(qos: .utility).async {
            var data = Data()
            func append<T: FixedWidthInteger>(_ value: T) {
                withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
            }

            let sampleRate = UInt32(AudioCaptureEngine.targetSampleRate)
            let channels: UInt16 = 1
            let bits: UInt16 = 16
            let dataSize = UInt32(samples.count * 2)

            data.append(contentsOf: Array("RIFF".utf8))
            append(UInt32(36) + dataSize)
            data.append(contentsOf: Array("WAVE".utf8))
            data.append(contentsOf: Array("fmt ".utf8))
            append(UInt32(16))
            append(UInt16(1)) // PCM
            append(channels)
            append(sampleRate)
            append(sampleRate * UInt32(channels) * UInt32(bits / 8))
            append(channels * bits / 8)
            append(bits)
            data.append(contentsOf: Array("data".utf8))
            append(dataSize)
            for sample in samples {
                append(Int16(clamping: Int((sample * 32767).rounded())))
            }

            do {
                try data.write(to: url)
                Log.info("audio saved: \(url.path) (\(samples.count) samples)")
            } catch {
                Log.error("failed to save debug audio: \(error.localizedDescription)")
            }
        }
    }
}
#endif
