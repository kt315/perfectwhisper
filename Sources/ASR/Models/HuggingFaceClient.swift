import Foundation

struct RemoteFile: Sendable {
    let remotePath: String
    let relativePath: String
    let size: Int64
    /// sha256 from Hugging Face LFS metadata; nil for small files without LFS.
    let sha256: String?
}

/// Client for the Hugging Face model repository: file list and sizes.
enum HuggingFaceClient {
    private static let repo = "argmaxinc/whisperkit-coreml"

    static func files(variantID: String) async throws -> [RemoteFile] {
        let folder = "openai_whisper-\(variantID)"
        guard let url = URL(string:
            "https://huggingface.co/api/models/\(repo)/tree/main/\(folder)?recursive=true"
        ) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }

        var result: [RemoteFile] = []
        for item in items where (item["type"] as? String) == "file" {
            guard let path = item["path"] as? String else { continue }
            let size = (item["size"] as? NSNumber)?.int64Value ?? 0
            let relative = path.hasPrefix(folder + "/")
                ? String(path.dropFirst(folder.count + 1))
                : path
            let checksum = (item["lfs"] as? [String: Any])?["oid"] as? String
            result.append(RemoteFile(
                remotePath: path,
                relativePath: relative,
                size: size,
                sha256: checksum?.count == 64 ? checksum : nil
            ))
        }
        return result.sorted { $0.relativePath < $1.relativePath }
    }

    static func totalSize(variantID: String) async throws -> Int64 {
        try await files(variantID: variantID).reduce(Int64(0)) { $0 + $1.size }
    }

    static func downloadURL(for file: RemoteFile) -> URL? {
        URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file.remotePath)")
    }
}
