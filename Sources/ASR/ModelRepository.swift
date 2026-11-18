import Foundation
import Observation

/// Facade for model state used by the UI. Networking, disk access and downloading live in separate services.
@MainActor
@Observable
final class ModelRepository {
    private(set) var variants: [ModelVariantInfo]
    private(set) var installed: [InstalledModel] = []
    private(set) var customFolders: [URL] = []

    var currentFolder: URL?
    var downloadProgress: [String: Double] = [:]
    var downloadingVariant: String?
    var testingFolder: URL?
    var status: String?
    var isLoadingSizes = false
    private var downloadTask: Task<Void, Never>?

    /// Called when the current model has changed (or was deleted).
    var onSelectionChanged: (() -> Void)?

    init() {
        variants = ModelCatalog.variants.map {
            ModelVariantInfo(
                id: $0.id,
                title: $0.title,
                noteKey: $0.noteKey,
                approximateBytes: $0.approximateBytes,
                remoteBytes: nil,
                installedFolder: nil
            )
        }
        loadCustomFolders()
        refresh()
    }

    // MARK: - List

    func refresh() {
        // Remember the found model here rather than in the resolver, so the resolver stays pure.
        if UserDefaults.standard.string(forKey: PrefKey.modelFolder) == nil,
           let found = ModelResolver.findDownloadedModel(in: Defaults.modelsDirectory) {
            UserDefaults.standard.set(found.path, forKey: PrefKey.modelFolder)
        }
        currentFolder = ModelResolver.currentFolder()
        installed = ModelStore.scan(
            huggingFaceRoot: Defaults.modelsDirectory,
            customRoots: customFolders
        )

        Log.info("models on disk: \(installed.isEmpty ? "none" : installed.map(\.title).joined(separator: ", "))")

        for index in variants.indices {
            let folderName = "openai_whisper-" + variants[index].id
            variants[index].installedFolder = installed
                .first { $0.folder.lastPathComponent == folderName }?
                .folder
        }
    }

    var entries: [ModelListEntry] {
        var result: [ModelListEntry] = variants.map { .variant($0) }

        let knownFolders = Set(variants.compactMap { $0.installedFolder?.standardizedFileURL })
        let extra = installed.filter { !knownFolders.contains($0.folder.standardizedFileURL) }
        result.append(contentsOf: extra.map { .installed($0) })
        return result
    }

    func isCurrent(_ folder: URL) -> Bool {
        folder.standardizedFileURL == currentFolder?.standardizedFileURL
    }

    // MARK: - Selection

    func select(_ folder: URL) {
        UserDefaults.standard.set(folder.path, forKey: PrefKey.modelFolder)
        currentFolder = folder
        status = L10n.t("Selected: %@", folder.lastPathComponent)
        Log.info("selected model: \(folder.path)")
        onSelectionChanged?()
    }

    // MARK: - Download

    func download(variant: ModelVariantInfo) {
        guard downloadTask == nil else { return }
        downloadingVariant = variant.id
        downloadProgress[variant.id] = 0
        status = L10n.t("Downloading %@…", variant.title)
        Log.info("downloading model: \(variant.id)")

        downloadTask = Task { [weak self] in
            await self?.performDownload(variant: variant)
            self?.downloadTask = nil
        }
    }

    func cancelDownload() {
        guard let id = downloadingVariant else { return }
        downloadTask?.cancel()
        downloadTask = nil
        downloadingVariant = nil
        downloadProgress[id] = nil
        status = L10n.t("Download cancelled")
        Log.info("download cancelled by the user")
    }

    private func performDownload(variant: ModelVariantInfo) async {
        let folderName = variant.repositoryFolderName
        let destination = Defaults.modelsDirectory.appendingPathComponent(folderName, isDirectory: true)
        defer {
            downloadingVariant = nil
            downloadProgress[variant.id] = nil
        }

        do {
            let files = try await HuggingFaceClient.files(variantID: variant.id)
            try await DownloadService.download(files: files, to: destination) { fraction in
                Task { @MainActor in
                    self.downloadProgress[variant.id] = fraction
                }
            }

            UserDefaults.standard.set(destination.path, forKey: PrefKey.modelFolder)
            UserDefaults.standard.set(variant.id, forKey: PrefKey.modelVariant)
            status = L10n.t("Downloaded: %@", folderName)
            Log.info("model downloaded: \(destination.path)")
            refresh()
            onSelectionChanged?()
        } catch is CancellationError {
            try? FileManager.default.removeItem(at: destination)
            status = L10n.t("Download cancelled")
        } catch {
            try? FileManager.default.removeItem(at: destination)
            if (error as? URLError)?.code == .cancelled {
                status = L10n.t("Download cancelled")
                return
            }
            status = L10n.t("Download failed: %@", error.localizedDescription)
            Log.error("model download failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Deletion

    /// Deletes the model folder. The UI asks for confirmation.
    func delete(_ model: InstalledModel) {
        do {
            try ModelStore.delete(model.folder)
            Log.info("model deleted: \(model.folder.path)")
            if isCurrent(model.folder) {
                UserDefaults.standard.removeObject(forKey: PrefKey.modelFolder)
                currentFolder = nil
                onSelectionChanged?()
            }
            status = L10n.t("Deleted: %@", model.title)
            refresh()
        } catch {
            status = L10n.t("Delete failed: %@", error.localizedDescription)
            Log.error("failed to delete model: \(error.localizedDescription)")
        }
    }

    // MARK: - Custom folders

    func addCustomFolder(_ url: URL) {
        guard !customFolders.contains(url) else { return }
        customFolders.append(url)
        saveCustomFolders()
        refresh()
    }

    func removeCustomFolder(_ url: URL) {
        customFolders.removeAll { $0 == url }
        saveCustomFolders()
        refresh()
    }

    private func loadCustomFolders() {
        let paths = UserDefaults.standard.stringArray(forKey: PrefKey.customModelFolders) ?? []
        customFolders = paths.map { URL(fileURLWithPath: $0) }
    }

    private func saveCustomFolders() {
        UserDefaults.standard.set(customFolders.map(\.path), forKey: PrefKey.customModelFolders)
    }

    // MARK: - Weights from Hugging Face

    func loadRemoteSizes() async {
        guard !isLoadingSizes else { return }
        isLoadingSizes = true
        defer { isLoadingSizes = false }

        for index in variants.indices where variants[index].remoteBytes == nil {
            let variantID = variants[index].id
            if let total = try? await HuggingFaceClient.totalSize(variantID: variantID), total > 0 {
                variants[index].remoteBytes = total
            }
        }
    }

    // MARK: - Model test

    /// Returns the result, or nil if the test failed (the reason is in `status`).
    func test(
        _ model: InstalledModel,
        transcriber: WhisperKitTranscriber
    ) async -> ModelTester.Result? {
        testingFolder = model.folder
        status = L10n.t("Testing model…")
        defer { testingFolder = nil }

        do {
            if !transcriber.isLoaded || !isCurrent(model.folder) {
                try await transcriber.prepare(folder: model.folder)
            }
            let result = try await ModelTester.run(model: model, transcriber: transcriber)
            status = L10n.t("Test passed: %@", result.text)
            select(model.folder)
            return result
        } catch {
            status = L10n.t("Test failed: %@", error.localizedDescription)
            Log.error("model test failed: \(error.localizedDescription)")
            return nil
        }
    }
}
