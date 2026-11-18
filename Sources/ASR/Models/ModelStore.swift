import Foundation

/// Working with model folders on disk: scanning, sizes, deletion.
enum ModelStore {
    static func scan(huggingFaceRoot: URL, customRoots: [URL]) -> [InstalledModel] {
        var result: [InstalledModel] = []
        var seen = Set<String>()

        func scan(root: URL, source: ModelSource) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for case let url as URL in enumerator {
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                guard isDirectory else { continue }
                if url.lastPathComponent.hasSuffix(".mlmodelc") {
                    enumerator.skipDescendants()
                    continue
                }
                guard ModelResolver.isModelFolder(url) else { continue }

                enumerator.skipDescendants()
                let standardized = url.standardizedFileURL
                guard seen.insert(standardized.path).inserted else { continue }

                let title = url.lastPathComponent
                    .replacingOccurrences(of: "openai_whisper-", with: "")
                result.append(InstalledModel(
                    folder: url,
                    title: title,
                    source: source,
                    bytes: folderSize(url)
                ))
            }
        }

        scan(root: huggingFaceRoot, source: .huggingFace)
        for root in customRoots {
            scan(root: root, source: .custom)
        }

        return result.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func folderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    static func delete(_ folder: URL) throws {
        try FileManager.default.removeItem(at: folder)
    }
}
