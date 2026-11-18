import Foundation

enum ModelSource: String, Sendable {
    case huggingFace
    case custom
}

struct InstalledModel: Identifiable, Hashable, Sendable {
    var id: String { folder.path }
    let folder: URL
    let title: String
    let source: ModelSource
    var bytes: Int64?
}

struct ModelVariantInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let noteKey: String
    var approximateBytes: Int64
    var remoteBytes: Int64?
    var installedFolder: URL?

    var displayBytes: Int64? { remoteBytes ?? approximateBytes }
    var repositoryFolderName: String { "openai_whisper-\(id)" }
}

/// A row in the model list: either a Hugging Face variant (possibly already downloaded),
/// or a model from a user folder that isn't in the catalog.
enum ModelListEntry: Identifiable {
    case variant(ModelVariantInfo)
    case installed(InstalledModel)

    var id: String {
        switch self {
        case .variant(let info): return "hf:" + info.id
        case .installed(let model): return "installed:" + model.folder.path
        }
    }
}

enum ModelFormat {
    static func size(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "—" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }
}
