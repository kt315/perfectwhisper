import Foundation

// MARK: - Model variant catalog

struct ModelVariant: Identifiable, Hashable, Sendable {
    let id: String              // identifier in the argmaxinc/whisperkit-coreml repository
    let title: String
    let approximateBytes: Int64
    /// English key string; translation happens at render time.
    let noteKey: String

    /// Folder name in the Hugging Face repository.
    var repositoryFolderName: String { "openai_whisper-\(id)" }
}

enum ModelCatalog {
    static let variants: [ModelVariant] = [
        ModelVariant(
            id: "large-v3-v20240930_turbo",
            title: "large-v3-turbo",
            approximateBytes: 1_570_000_000,
            noteKey: "Recommended. Same model as in whisper.cpp, fastest on macOS"
        ),
        ModelVariant(
            id: "large-v3-v20240930_626MB",
            title: "large-v3-turbo (compressed)",
            approximateBytes: 630_000_000,
            noteKey: "Less memory, slightly lower accuracy"
        ),
        ModelVariant(
            id: "large-v3",
            title: "large-v3",
            approximateBytes: 3_100_000_000,
            noteKey: "Maximum accuracy, noticeably slower"
        ),
        ModelVariant(
            id: "small",
            title: "small",
            approximateBytes: 500_000_000,
            noteKey: "Compromise for slower Macs"
        ),
        ModelVariant(
            id: "base",
            title: "base",
            approximateBytes: 150_000_000,
            noteKey: "Debug only, low quality"
        ),
    ]

    static func variant(id: String) -> ModelVariant? {
        variants.first { $0.id == id }
    }
}

// MARK: - Locating the installed model

enum ModelResolver {
    /// Model folder: either explicitly chosen by the user or found among the downloaded ones.
    static func currentFolder() -> URL? {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: PrefKey.modelFolder), !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if isModelFolder(url) { return url }
        }
        return findDownloadedModel(in: Defaults.modelsDirectory)
    }

    static func isModelFolder(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        let contents = (try? fm.contentsOfDirectory(atPath: url.path)) ?? []
        let hasEncoder = contents.contains { $0.hasSuffix(".mlmodelc") }
        let hasConfig = contents.contains { $0 == "config.json" }
        return hasEncoder || hasConfig
    }

    /// whisper.cpp model folder: it contains ggml-*.bin rather than CoreML.
    static func looksLikeGGML(_ url: URL) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return contents.contains { $0.hasPrefix("ggml") && $0.hasSuffix(".bin") }
    }

    static func findDownloadedModel(in base: URL) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if url.lastPathComponent.hasSuffix(".mlmodelc") {
                enumerator.skipDescendants()
                let parent = url.deletingLastPathComponent()
                if isModelFolder(parent) { return parent }
            }
        }
        return nil
    }
}
