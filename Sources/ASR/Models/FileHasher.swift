import CryptoKit
import Foundation

/// Streaming sha256 of a file — without loading gigabytes into memory.
enum FileHasher {
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
