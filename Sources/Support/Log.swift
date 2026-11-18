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
