import AppKit
import DictationSystem
import SwiftUI

/// Value-only panel content, shared with the renderer. No audio or timers are started by this view.
struct RecordingOverlayState {
    var title = "Froggy Talkie"
    var message = ""
    var recording = false
    var elapsed = "00:00"
    var levels = RecordingLevel().history
    var cancellable = false
    var warning = false
    var error = false
}

struct RecordingOverlayView: View {
    static let size = NSSize(width: 184, height: 36)
    var state: RecordingOverlayState
    var cancel: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    private var palette: DictationPalette { DictationPalette(scheme: scheme) }
    private var noticeColor: Color {
        state.error ? palette.error : (state.warning ? palette.warning : palette.accent)
    }

    var body: some View {
        Group {
            if state.recording {
                HStack(spacing: 10) {
                    Circle().fill(palette.recording).frame(width: 5, height: 5)
                        .accessibilityLabel("Идёт запись")
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(state.levels.indices, id: \.self) { index in
                            let level = state.levels[index]
                            Capsule()
                                .fill(palette.accent.opacity(0.65 + 0.35 * level))
                                .frame(width: 3.5, height: 2 + 26 * level)
                        }
                    }
                    .frame(width: 56, height: 28)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Уровень микрофона")
                    .accessibilityValue("\(Int((state.levels.last ?? 0) * 100)) процентов шкалы")
                    .animation(reduceMotion ? nil : .linear(duration: 0.025), value: state.levels)
                    Text(state.elapsed).font(.system(size: 12, weight: .medium, design: .monospaced))
                        .monospacedDigit().fixedSize()
                        .accessibilityLabel("Длительность записи")
                        .accessibilityValue(state.elapsed)
                    cancelButton
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: state.error ? "exclamationmark.circle.fill" :
                        (state.warning ? "exclamationmark.triangle.fill" :
                        (state.cancellable ? "ellipsis" : "checkmark.circle.fill")))
                        .foregroundStyle(noticeColor)
                    Text(state.title).font(.system(size: 11, weight: .medium))
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    cancelButton
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(palette.text)
        .background(state.error ? palette.errorSurface : palette.editor, in: Capsule())
        .overlay(Capsule().stroke(contrast == .increased ? palette.secondary : palette.border, lineWidth: 1))
        .help(state.message)
        .accessibilityHint(state.message)
    }

    private var cancelButton: some View {
        Button(action: cancel) {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                .frame(width: 20, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.secondary)
        .accessibilityLabel(state.cancellable ? "Отменить диктовку" : "Скрыть уведомление")
    }
}

@MainActor
final class RecordingOverlay {
    private static let size = RecordingOverlayView.size
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private final class Content: ObservableObject {
        @Published var state = RecordingOverlayState()
        var cancel: () -> Void = {}
    }

    private struct ThemedContent: View {
        @ObservedObject var content: Content

        var body: some View {
            RecordingOverlayView(state: content.state, cancel: content.cancel)
        }
    }

    private let content = Content()
    private let panel: NSPanel
    private var dismissTask: Task<Void, Never>?

    init() {
        panel = Panel(contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: ThemedContent(content: content))
    }

    func showRecording(elapsed: String, levels: [Double], hint: String, cancel: @escaping () -> Void) {
        dismissTask?.cancel()
        dismissTask = nil
        content.cancel = cancel
        content.state = RecordingOverlayState(message: hint, recording: true,
            elapsed: elapsed, levels: levels, cancellable: true)
        present()
    }

    func show(_ message: String, title: String = "Froggy Talkie", warning: Bool = false,
              error: Bool = false, cancel: (() -> Void)? = nil, dismissAfter seconds: Double? = nil) {
        dismissTask?.cancel()
        dismissTask = nil
        content.cancel = cancel ?? { [weak self] in self?.hide() }
        content.state = RecordingOverlayState(title: title, message: message,
            cancellable: cancel != nil, warning: warning, error: error)
        present()
        if let seconds {
            dismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    private func present() {
        guard !panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - Self.size.width / 2, y: area.minY + 8))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        panel.orderOut(nil)
        content.cancel = {}
        content.state = RecordingOverlayState()
    }
}
