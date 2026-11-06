import AppKit
import Carbon
import DictationSystem
import SwiftUI

struct ShortcutEditor: View {
    let shortcut: DictationShortcut
    var save: (DictationShortcut) throws -> Void
    var close: () -> Void
    @State private var candidate: DictationShortcut?
    @State private var listening = true
    @State private var error: String?
    @Environment(\.colorScheme) private var scheme

    private var palette: DictationPalette { DictationPalette(scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Сочетание клавиш").font(.system(size: 19, weight: .semibold))
            Text("Нажмите клавишу вместе с Control, Option или Command. Можно добавить Shift.")
                .font(.system(size: 12)).foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(palette.accentSoft)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.border))
                Text(listening ? "Нажмите сочетание…" : (candidate?.display ?? shortcut.display))
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(palette.accent)
                ShortcutCapture(active: listening, receive: receive)
                    .accessibilityHidden(true)
            }
            .frame(height: 64)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(listening ? "Ожидается новое сочетание клавиш" : "Новое сочетание: \(candidate?.accessibilityLabel ?? shortcut.accessibilityLabel)")
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12)).foregroundStyle(palette.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text("Сейчас: \(shortcut.display)").font(.system(size: 12)).foregroundStyle(palette.secondary)
                Spacer()
                Button("Ввести заново") { listening = true; candidate = nil; error = nil }
                    .disabled(listening).controlSize(.small)
            }
            Text("Во время настройки диктовка приостановлена. Esc — отмена. Буквенные клавиши обозначены по английской раскладке; сочетание работает и в русской.")
                .font(.system(size: 11)).foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Отмена", action: close).keyboardShortcut(.cancelAction)
                Button("Сохранить") {
                    guard let candidate else { return }
                    do { try save(candidate); close() }
                    catch { self.error = error.localizedDescription }
                }
                .buttonStyle(DictationPrimaryButtonStyle(height: 30))
                .keyboardShortcut(.defaultAction)
                .disabled(candidate == nil || listening)
            }
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .accentColor(palette.accent)
        .background(palette.background)
    }

    private func receive(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        if event.keyCode == UInt16(kVK_Escape), flags.isEmpty { close(); return }
        let value = DictationShortcut(keyCode: UInt32(event.keyCode), modifiers:
            (flags.contains(.control) ? UInt32(controlKey) : 0)
            | (flags.contains(.option) ? UInt32(optionKey) : 0)
            | (flags.contains(.shift) ? UInt32(shiftKey) : 0)
            | (flags.contains(.command) ? UInt32(cmdKey) : 0))
        guard value.isValid else {
            error = "Добавьте Control, Option или Command к обычной клавише."
            return
        }
        candidate = value
        listening = false
        error = nil
    }
}

/// A local monitor exists only while the sheet is attached. It never watches other apps.
private struct ShortcutCapture: NSViewRepresentable {
    var active: Bool
    var receive: (NSEvent) -> Void

    func makeNSView(context: Context) -> CaptureView { CaptureView() }
    func updateNSView(_ view: CaptureView, context: Context) {
        view.active = active
        view.receive = receive
    }
    static func dismantleNSView(_ view: CaptureView, coordinator: ()) { view.removeMonitor() }

    final class CaptureView: NSView {
        var active = false
        var receive: ((NSEvent) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, self.active, self.window?.isKeyWindow == true,
                          event.window === self.window else { return false }
                    if !event.isARepeat { self.receive?(event) }
                    return true
                }
                return consumed ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
