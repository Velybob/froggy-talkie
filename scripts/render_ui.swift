// Offscreen snapshots of the actual views. No DictationModel, microphone, ASR,
// global hotkey, pasteboard mutation or visible windows are created here.
import AppKit
import SwiftUI
import DictationSystem

@main
struct RenderDictationUI {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sample = "Давайте перенесём встречу на завтра.\nI’ll send you the updated notes this evening."
        let scenarios: [(String, DictationViewState, String)] = [
            ("empty", .init(), ""),
            ("manual-recording", .init(isRecording: true, manualRecording: true, recordingTime: "00:12", microphoneLevel: 0.4), sample),
            ("text", .init(status: "Готово за 0.12 с · запись 8.4 с", statusTone: .success), sample),
            ("recording", .init(status: "Идёт запись. Нажми «Завершить», когда закончишь.",
                isRecording: true, canRecord: false, recordingTime: "02:59", microphoneLevel: 0.72), sample),
            ("processing", .init(status: "Распознавание на Mac…", isWorking: true, canRecord: false), sample),
            ("cancelling", .init(status: "Отмена…", isWorking: true, isCancelling: true, canRecord: false), sample),
            ("permissions", .init(insertionAllowed: false), ""),
            ("error", .init(status: "Не удалось подтвердить текстовое поле. Распознано; текст доступен в окне. Фокус или курсор изменился — скопируйте результат вручную.",
                statusTone: .warning, hotKeyError: "Не удалось зарегистрировать ⌃⌥Пробел (код -9878). Возможно, сочетание занято.",
                insertionAllowed: false), String(repeating: sample + "\n\n", count: 14)),
            ("failure", .init(status: "Не удалось открыть аудиофайл. Проверьте формат и попробуйте ещё раз.", statusTone: .error), sample),
            ("model", .init(status: "Выбери папку с моделью и нажми «Подготовить».", canRecord: false, modelReady: false), ""),
        ]
        for scheme in [ColorScheme.light, .dark] {
            let theme = scheme == .dark ? "dark" : "light"
            for (name, state, transcript) in scenarios {
                let view = DictationScreen(transcript: .constant(transcript), state: state)
                    .environment(\.colorScheme, scheme)
                try render(view, size: NSSize(width: 500, height: 492), scheme: scheme,
                    to: directory.appendingPathComponent("\(theme)-\(name).png"))
                if name == "error" || name == "recording" || name == "empty" || name == "manual-recording" {
                    try render(view, size: NSSize(width: 440, height: 440), scheme: scheme,
                        to: directory.appendingPathComponent("\(theme)-\(name)-minimum.png"))
                }
            }
            let settings = DictationSettingsScreen(appearance: .constant(scheme == .dark ? .dark : .light),
                modelsPath: "/Users/example/Library/Application Support/Froggy Talkie/Models",
                modelReady: true, isBusy: false, status: "Готово к записи",
                hotKeyStatus: "Удерживай ⌃⌥Пробел для диктовки", insertionAllowed: true)
                .environment(\.colorScheme, scheme)
            try render(settings, size: nil, scheme: scheme,
                to: directory.appendingPathComponent("\(theme)-settings.png"))
            let missingModel = DictationSettingsScreen(appearance: .constant(.system),
                modelsPath: "/Users/example/Models", modelReady: false, isBusy: false,
                status: "Не удалось подготовить модель. Проверьте выбранную папку.",
                hotKeyStatus: "Сочетание занято. Выберите другое.", hotKeyWarning: true,
                statusTone: .error, insertionAllowed: false)
                .environment(\.colorScheme, scheme)
            try render(missingModel, size: nil, scheme: scheme,
                to: directory.appendingPathComponent("\(theme)-settings-error.png"))
            for cancelling in [false, true] {
                let downloading = DictationSettingsScreen(appearance: .constant(.system),
                    modelsPath: "/Users/example/Library/Application Support/Froggy Talkie/Models",
                    modelReady: false, isBusy: true,
                    status: cancelling ? "Отмена…" : "Загрузка модели: 284 из 632 МБ",
                    hotKeyStatus: "Удерживай ⌃⌥Пробел для диктовки", insertionAllowed: true,
                    downloadProgress: 0.45, isCancelling: cancelling)
                    .environment(\.colorScheme, scheme)
                try render(downloading, size: nil, scheme: scheme,
                    to: directory.appendingPathComponent("\(theme)-model-\(cancelling ? "cancelling" : "downloading").png"))
            }
            let overlayStates: [(String, RecordingOverlayState)] = [
                ("manual-recording", .init(recording: true, canFinish: true, elapsed: "00:12", levels: [0.1, 0.3, 0.6, 0.9, 0.6, 0.3, 0.1, 0.4, 0.6], cancellable: true)),
                ("quiet", .init(recording: true, elapsed: "00:02", levels: Array(repeating: 0, count: 9), cancellable: true)),
                ("voice", .init(recording: true, elapsed: "01:24", levels: [0.1, 0.28, 0.65, 0.95, 0.72, 0.36, 0.15, 0.45, 0.8], cancellable: true)),
                ("peak", .init(recording: true, elapsed: "02:59", levels: Array(repeating: 1, count: 9), cancellable: true)),
                ("preparing", .init(title: "Подготовка", cancellable: true)),
                ("processing", .init(title: "Распознавание", cancellable: true)),
                ("warning", .init(title: "Текст в окне", warning: true)),
                ("error", .init(title: "Ошибка записи", error: true)),
                ("notice", .init(title: "Froggy Talkie")),
            ]
            for (name, state) in overlayStates {
                let overlay = RecordingOverlayView(state: state)
                    .environment(\.colorScheme, scheme)
                try render(overlay, size: RecordingOverlayView.size(for: state), scheme: scheme,
                    to: directory.appendingPathComponent("\(theme)-overlay-\(name).png"))
            }
            let custom = DictationScreen(transcript: .constant(sample), state: .init(
                shortcut: DictationShortcut(keyCode: 49, modifiers: DictationShortcut.allowedModifiers)))
                .environment(\.colorScheme, scheme)
            try render(custom, size: NSSize(width: 440, height: 440), scheme: scheme,
                to: directory.appendingPathComponent("\(theme)-custom-shortcut.png"))
            let shortcutEditor = ShortcutEditor(shortcut: .default, save: { _ in }, close: {})
                .environment(\.colorScheme, scheme)
            try render(shortcutEditor, size: nil, scheme: scheme,
                to: directory.appendingPathComponent("\(theme)-shortcut-editor.png"))
        }
        print("Rendered 58 SwiftUI snapshots: \(directory.path)")
    }

    @MainActor private static func render<V: View>(_ view: V, size: NSSize?, scheme: ColorScheme, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: size ?? host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
    }
}
