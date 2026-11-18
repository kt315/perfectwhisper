import Foundation

/// Downloads model files with byte-level progress and cancellation support.
enum DownloadService {
    enum DownloadError: LocalizedError {
        case emptyFileList
        case badResponse
        case checksumMismatch(String)

        var errorDescription: String? {
            switch self {
            case .emptyFileList: return L10n.t("The repository returned no file list")
            case .badResponse: return L10n.t("The server returned an invalid response")
            case .checksumMismatch(let file): return L10n.t("Model file is corrupted: %@", file)
            }
        }
    }

    /// Downloads files into `destination`. Progress goes from 0 to 1.
    /// Throws `CancellationError` on cancel; the caller cleans up the folder.
    static func download(
        files: [RemoteFile],
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard !files.isEmpty else { throw DownloadError.emptyFileList }

        let total = max(files.reduce(Int64(0)) { $0 + $1.size }, 1)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let done = AtomicBytes()
        let throttle = ProgressThrottle()

        for file in files {
            try Task.checkCancellation()

            let target = destination.appendingPathComponent(file.relativePath)
            if let attributes = try? FileManager.default.attributesOfItem(atPath: target.path),
               let existing = attributes[.size] as? Int64,
               existing == file.size {
                done.add(file.size)
                progress(Double(done.value) / Double(total))
                continue
            }

            try? FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let url = HuggingFaceClient.downloadURL(for: file) else { continue }

            // Downloaded into a sibling file first: a crash or a checksum
            // mismatch must never leave a half-written model in place.
            let part = target.deletingLastPathComponent()
                .appendingPathComponent(".\(target.lastPathComponent).part")
            try? FileManager.default.removeItem(at: part)

            let downloaded = try await FileDownloader().download(url, to: part) { written in
                let fraction = min(1, (Double(done.value) + Double(written)) / Double(total))
                if throttle.shouldReport(fraction) {
                    progress(fraction)
                }
            }

            try Task.checkCancellation()
            guard (downloaded as? HTTPURLResponse)?.statusCode == 200 else {
                try? FileManager.default.removeItem(at: part)
                throw DownloadError.badResponse
            }

            if let expected = file.sha256 {
                let actual = try FileHasher.sha256(of: part)
                guard actual == expected else {
                    try? FileManager.default.removeItem(at: part)
                    Log.error("sha256 mismatch: \(file.relativePath)")
                    throw DownloadError.checksumMismatch(file.relativePath)
                }
            }

            if FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.removeItem(at: target)
            }
            try FileManager.default.moveItem(at: part, to: target)

            done.add(file.size)
            progress(Double(done.value) / Double(total))
        }
    }
}

// MARK: - Helpers

/// Total bytes of completed files. Written from the download queue, read from
/// the same queue and from the async loop.
private final class AtomicBytes: @unchecked Sendable {
    private var bytes: Int64 = 0
    private let lock = NSLock()

    var value: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return bytes
    }

    func add(_ delta: Int64) {
        lock.lock()
        bytes += delta
        lock.unlock()
    }
}

/// URLSession reports progress per chunk; the UI only needs ~10 updates a second.
private final class ProgressThrottle: @unchecked Sendable {
    private var lastFraction = -1.0
    private var lastTime = Date.distantPast
    private let lock = NSLock()

    func shouldReport(_ fraction: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        let changedEnough = fraction - lastFraction >= 0.005
        let timePassed = now.timeIntervalSince(lastTime) >= 0.1
        guard changedEnough || timePassed || fraction >= 1 else { return false }
        lastFraction = fraction
        lastTime = now
        return true
    }
}

/// One file at a time, with `didWriteData` mapped to a byte counter.
private final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<(URL, URLResponse), Error>?
        var destination: URL?
        var onProgress: (@Sendable (Int64) -> Void)?
        var session: URLSession?
    }

    /// Swift 6 forbids `NSLock.lock()` inside async functions, so the state is
    /// only touched through this synchronous box. Nothing awaits inside it.
    private final class Box: @unchecked Sendable {
        private var value = State()
        private let lock = NSLock()

        func withLock<Result>(_ body: (inout State) -> Result) -> Result {
            lock.lock()
            defer { lock.unlock() }
            return body(&value)
        }
    }

    private let box = Box()

    func download(
        _ url: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws -> URLResponse {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        box.withLock { state in
            state.destination = destination
            state.onProgress = onProgress
            state.session = session
        }

        let task = session.downloadTask(with: url)
        let result: (URL, URLResponse) = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), Error>) in
                box.withLock { $0.continuation = continuation }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
        return result.1
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let onProgress = box.withLock { $0.onProgress }
        onProgress?(totalBytesWritten)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let destination = box.withLock({ $0.destination }) else { return }
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
            return
        }
        let destination = box.withLock { $0.destination }
        guard let destination, let response = task.response,
              FileManager.default.fileExists(atPath: destination.path) else {
            finish(.failure(DownloadService.DownloadError.badResponse))
            return
        }
        finish(.success((destination, response)))
    }

    // MARK: Completion

    private func finish(_ result: Result<(URL, URLResponse), Error>) {
        let (continuation, session) = box.withLock { state -> (CheckedContinuation<(URL, URLResponse), Error>?, URLSession?) in
            let continuation = state.continuation
            let session = state.session
            state.continuation = nil
            state.session = nil
            return (continuation, session)
        }

        continuation?.resume(with: result)
        session?.finishTasksAndInvalidate()
    }
}
