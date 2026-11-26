import AppKit
import SwiftUI

// MARK: - HUD state

enum HUDPhase: Equatable {
    case loading(String)
    case recording
    case transcribing
    case message(String)
    case notice(title: String, body: String)
    case error(String)

    var title: String {
        switch self {
        case .loading(let text): return text
        case .recording: return L10n.t("Listening…")
        case .transcribing: return L10n.t("Transcribing…")
        case .message(let text): return text
        case .notice(let title, _): return title
        case .error(let text): return text
        }
    }

    var symbol: String {
        switch self {
        case .loading: return "hourglass"
        case .recording: return "mic.fill"
        case .transcribing: return "waveform"
        case .message: return "checkmark"
        case .notice: return "doc.on.clipboard"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

@MainActor
@Observable
final class HUDModel {
    var phase: HUDPhase = .recording
    var level: Float = 0
    var elapsedSeconds: Int = 0

    var title: String {
        guard case .recording = phase else { return phase.title }
        return L10n.t("Listening… %@", Self.format(elapsedSeconds))
    }

    static func format(_ seconds: Int) -> String {
        guard seconds >= 60 else { return L10n.t("%d s", Int32(clamping: seconds)) }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - SwiftUI content

struct HUDView: View {
    var model: HUDModel
    var onCancel: () -> Void = {}
    var onCopy: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: model.phase.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: isAnimated)

            titleText
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .layoutPriority(1)

            if model.phase == .recording {
                LevelMeter(level: model.level)
                    .frame(width: 46, height: 18)
                    .layoutPriority(2)

                pillButton(
                    "doc.on.doc",
                    size: 14,
                    help: L10n.t("Copy to clipboard"),
                    action: onCopy
                )
                pillButton(
                    "xmark.circle.fill",
                    size: 16,
                    help: L10n.t("Cancel dictation"),
                    action: onCancel
                )
            } else if model.phase == .transcribing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.8)
                    .frame(width: 46, height: 18)
                    .layoutPriority(2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(minHeight: 40, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// "Listening…" and "Transcribing…" are always a single line.
    /// Messages and recognized text use a wide multiline column.
    @ViewBuilder
    private var titleText: some View {
        switch model.phase {
        case .recording, .transcribing, .loading:
            Text(model.title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

        case .notice(let title, let body):
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 560, alignment: .leading)

        default:
            Text(model.title)
                .lineLimit(6)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560, alignment: .leading)
        }
    }

    /// Small round action inside the recording pill. The glyph is larger than
    /// the row height, so the pill keeps its height while the target grows.
    private func pillButton(
        _ systemName: String,
        size: CGFloat,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .layoutPriority(3)
    }

    private var tint: Color {
        switch model.phase {
        case .error: return .orange
        case .recording: return .red
        case .message: return .green
        case .notice: return .accentColor
        default: return .primary
        }
    }

    private var isAnimated: Bool {
        switch model.phase {
        case .recording, .transcribing, .loading, .notice: return true
        default: return false
        }
    }
}

private struct LevelMeter: View {
    var level: Float

    var body: some View {
        GeometryReader { geometry in
            let barCount = 5
            let spacing: CGFloat = 3
            let barWidth = max(2, (geometry.size.width - spacing * CGFloat(barCount - 1)) / CGFloat(barCount))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let weight = 0.45 + 0.55 * abs(sin(Double(index) * 1.7 + 0.6))
                    let height = max(3, Double(geometry.size.height) * (0.15 + 0.85 * weight * Double(level)))
                    Capsule()
                        .fill(Color.red.opacity(0.85))
                        .frame(width: barWidth, height: CGFloat(height))
                        .animation(.easeOut(duration: 0.08), value: level)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
    }
}

// MARK: - Panel

/// Floating panel: does not steal focus and stays visible on all Spaces and
/// above full-screen apps. This is critical — otherwise ⌘V goes to the wrong place.
@MainActor
final class HUDController {
    /// Called when the user clicks the close button in the recording pill.
    var onCancel: () -> Void = {}
    /// Called when the user wants the text on the clipboard without insertion.
    var onCopy: () -> Void = {}

    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var recordingStartedAt: Date?

    func show(phase: HUDPhase) {
        hideTask?.cancel()
        model.phase = phase
        model.level = 0
        if case .recording = phase {
            startTicker()
        } else {
            stopTicker()
        }
        present()
        Log.info("HUD shown: \(phase.title)")
    }

    /// Puts the panel on screen, moving it to the active display when it was
    /// hidden before. A visible panel is never moved, so a notice does not make
    /// the HUD jump across monitors.
    private func present() {
        ensurePanel()
        guard let panel else { return }
        panel.ignoresMouseEvents = !isRecordingPhase
        let target = panelSize(for: model.phase)
        let resized = panel.frame.size != target
        if resized {
            panel.setContentSize(target)
        }
        if resized || !panel.isVisible {
            position(panel, on: panel.isVisible ? panel.screen : nil)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    /// Only the recording pill is clickable (it has the close button), and only
    /// it needs a small hit area. Everything else is a pass-through overlay.
    private var isRecordingPhase: Bool {
        if case .recording = model.phase { return true }
        return false
    }

    private func panelSize(for phase: HUDPhase) -> NSSize {
        if case .recording = phase {
            return NSSize(width: 380, height: 64)
        }
        return NSSize(width: 640, height: 300)
    }

    func setLevel(_ level: Float) {
        model.level = level
    }

    func update(phase: HUDPhase) {
        model.phase = phase
        if case .recording = phase {
            if recordingStartedAt == nil { startTicker() }
            present()
        } else {
            stopTicker()
        }
    }

    /// Short auto-hiding message (success or error).
    func flash(_ text: String, isError: Bool = false, duration: Duration = .milliseconds(1400)) {
        Log.info("HUD message: \(text)")
        stopTicker()
        model.phase = isError ? .error(text) : .message(text)
        present()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    /// Notice card with a title and body (for example, "copied to clipboard").
    func showNotice(title: String, body: String, isError: Bool = false, duration: Duration = .milliseconds(2600)) {
        Log.info("HUD notice: \(title)")
        stopTicker()
        model.phase = .notice(title: title, body: body)
        present()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        hideTask?.cancel()
        stopTicker()
        guard let panel else { return }
        Log.info("HUD hidden")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        }
    }

    private func startTicker() {
        stopTicker()
        recordingStartedAt = Date()
        model.elapsedSeconds = 0
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled, let start = self.recordingStartedAt else { return }
                self.model.elapsedSeconds = Int(Date().timeIntervalSince(start))
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
        recordingStartedAt = nil
    }

    private func ensurePanel() {
        if panel != nil { return }

        let size = NSSize(width: 640, height: 300)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        // `.stationary` must not be combined with `.canJoinAllSpaces`: it keeps
        // the panel tied to the Space it was created on, so it disappears when
        // the user switches desktops.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: HUDView(
            model: model,
            onCancel: { [weak self] in self?.onCancel() },
            onCopy: { [weak self] in self?.onCopy() }
        ))
        panel.setContentSize(size)
        panel.alphaValue = 0
        self.panel = panel
        position(panel, on: nil)
        startObserving()
    }

    /// Some macOS builds still drop a panel that was ordered in on another
    /// Space, so the panel is re-asserted on space changes and screen changes.
    private func startObserving() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                panel.orderFrontRegardless()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let panel = self.panel, panel.isVisible else { return }
                self.position(panel, on: nil)
                panel.orderFrontRegardless()
            }
        }
    }

    /// The display the user is working on: the one under the pointer, else the
    /// main one (the app itself has no key window, so `NSScreen.main` alone is
    /// not enough with several monitors).
    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func position(_ panel: NSPanel, on screen: NSScreen?) {
        guard let screen = screen ?? activeScreen() else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let x = min(max(visible.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: visible.minY + 90))
    }
}
