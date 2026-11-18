import AppKit
import Observation
import SwiftUI

// MARK: - Model

struct ModelSettingsView: View {
    var env: AppEnvironment

    var body: some View {
        Form {
            Section(L10n.t("Current model")) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(env.asr.isReady ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(env.asr.modelTitle)
                            .font(.system(size: 13, weight: .semibold))
                        Text(env.asr.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let path = env.asr.loadedFolder {
                        let folder = URL(fileURLWithPath: path)
                        if let model = installedModel(for: folder) {
                            Button(L10n.t("Test")) { test(model) }
                                .controlSize(.small)
                        }
                    }
                    Button(L10n.t("Reload")) { env.reloadModel() }
                        .controlSize(.small)
                }
                if let status = env.repository.status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if env.asr.isLoading {
                    Text(L10n.t("The first launch after install or update compiles the model for this Mac and may take a few minutes."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(L10n.t("Custom folders")) {
                ForEach(env.repository.customFolders, id: \.self) { folder in
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(folder.path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            env.repository.removeCustomFolder(folder)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help(L10n.t("Delete"))
                    }
                }
                Button(L10n.t("Add folder…")) { chooseFolders() }
                Text(L10n.t("Models from these folders appear in the list below."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.t("Models")) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(env.repository.entries) { entry in
                            row(entry)
                            Divider()
                        }
                    }
                }
                .frame(height: 300)
            }
        }
        .formStyle(.grouped)
        .padding(.top, 4)
        .task {
            env.repository.refresh()
            await env.repository.loadRemoteSizes()
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ entry: ModelListEntry) -> some View {
        switch entry {
        case .variant(let info):
            rowContent(
                title: info.title,
                subtitle: L10n.t(info.noteKey),
                size: info.displayBytes,
                badge: nil,
                folder: info.installedFolder,
                isCurrent: info.installedFolder.map { env.repository.isCurrent($0) } ?? false,
                progress: env.repository.downloadingVariant == info.id
                    ? env.repository.downloadProgress[info.id]
                    : nil,
                variant: info
            )
        case .installed(let model):
            rowContent(
                title: model.title,
                subtitle: "",
                size: model.bytes,
                badge: L10n.t("Custom"),
                folder: model.folder,
                isCurrent: env.repository.isCurrent(model.folder),
                progress: nil,
                variant: nil
            )
        }
    }

    private func rowContent(
        title: String,
        subtitle: String,
        size: Int64?,
        badge: String?,
        folder: URL?,
        isCurrent: Bool,
        progress: Double?,
        variant: ModelVariantInfo?
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isCurrent
                  ? "checkmark.circle.fill"
                  : (folder != nil ? "circle" : "arrow.down.circle"))
                .font(.system(size: 15))
                .foregroundStyle(isCurrent ? Color.green : (folder != nil ? Color.secondary : Color.accentColor))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
                HStack(spacing: 5) {
                    Text(ModelFormat.size(size))
                    if !subtitle.isEmpty {
                        Text("·")
                        Text(subtitle)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let progress {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.20), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: max(0.02, progress))
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(progress * 100))")
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                    }
                    .frame(width: 30, height: 30)
                    .animation(.easeOut(duration: 0.2), value: progress)

                    Button {
                        env.repository.cancelDownload()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.t("Cancel download"))
                }
            } else if let folder {
                HStack(spacing: 6) {
                    if !isCurrent {
                        Button(L10n.t("Select")) { env.repository.select(folder) }
                            .controlSize(.small)
                    }
                    Button(L10n.t("Test")) {
                        if let model = installedModel(for: folder) { test(model) }
                    }
                    .controlSize(.small)
                    .disabled(env.repository.testingFolder != nil)

                    Button {
                        if let model = installedModel(for: folder) { confirmDelete(model) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                    .help(L10n.t("Delete"))
                }
            } else if let variant {
                Button(L10n.t("Download")) {
                    env.repository.download(variant: variant)
                }
                .controlSize(.small)
                .disabled(env.repository.downloadingVariant != nil)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture {
            // Do not allow selecting a partially downloaded model.
            if let folder, progress == nil { env.repository.select(folder) }
        }
    }

    // MARK: Actions

    private func installedModel(for folder: URL) -> InstalledModel? {
        env.repository.installed.first { $0.folder.standardizedFileURL == folder.standardizedFileURL }
            ?? (ModelResolver.isModelFolder(folder)
                ? InstalledModel(
                    folder: folder,
                    title: folder.lastPathComponent.replacingOccurrences(of: "openai_whisper-", with: ""),
                    source: .huggingFace,
                    bytes: ModelStore.folderSize(folder)
                )
                : nil)
    }

    private func test(_ model: InstalledModel) {
        Task {
            guard let result = await env.repository.test(model, transcriber: env.transcriber) else {
                let alert = NSAlert()
                alert.messageText = L10n.t("Test failed: %@", "")
                alert.informativeText = env.repository.status ?? ""
                alert.runModal()
                return
            }

            let alert = NSAlert()
            alert.messageText = L10n.t("Model test")
            alert.informativeText = result.text.isEmpty
                ? L10n.t("Model loaded but returned no text")
                : result.text + "\n\n" + L10n.t("Recognition time: %.1f s", result.seconds)
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    private func confirmDelete(_ model: InstalledModel) {
        let alert = NSAlert()
        alert.messageText = L10n.t("Delete model?")
        alert.informativeText = L10n.t(
            "This removes %@ from disk. You can download it again later.",
            model.title
        )
        alert.addButton(withTitle: L10n.t("Delete"))
        alert.addButton(withTitle: L10n.t("Cancel"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        env.repository.delete(model)
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.t("Add folder")
        panel.message = L10n.t("Choose folders that contain CoreML Whisper models")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            env.repository.addCustomFolder(url)
        }
    }
}
