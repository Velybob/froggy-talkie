import AppKit
import SwiftUI
import DictationSystem

enum DictationAppearance: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "Как в системе"
        case .light: "Светлая"
        case .dark: "Тёмная"
        }
    }

    /// Apply at the AppKit application level. SwiftUI's preferredColorScheme(nil)
    /// can clear window chrome while leaving hosted content in the previous scheme.
    /// A nil NSApp.appearance restores inheritance from macOS for all windows/panels.
    @MainActor func apply(to application: NSApplication = .shared) {
        switch self {
        case .system: application.appearance = nil
        case .light: application.appearance = NSAppearance(named: .aqua)
        case .dark: application.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum DictationStatusTone { case neutral, success, warning, error }

/// Value-only UI input also used by the offscreen visual checks. It cannot start audio or ASR.
struct DictationViewState {
    var status = "Готово. Можно записывать или открыть аудиофайл."
    var statusTone: DictationStatusTone = .neutral
    var shortcut = DictationShortcut.default
    var hotKeyError: String?
    var isRecording = false
    var isWorking = false
    var isCancelling = false
    var canRecord = true
    var modelReady = true
    var insertionAllowed = true
    var recordingTime = "00:00"
    var microphoneLevel = 0.0

    var isBusy: Bool { isRecording || isWorking }
    var displayStatus: String {
        if isRecording { return "Идёт запись" }
        if status == "Готово. Можно записывать или открыть аудиофайл." { return "Готово к записи" }
        return status
    }
}

/// Colors derived from AppIcon.png: pink #F9D1D9, frog #AED26B,
/// outline #264319 and cream #FEF3DB. Text shades are adjusted for contrast.
struct DictationPalette {
    let scheme: ColorScheme
    private var dark: Bool { scheme == .dark }
    private func color(_ light: UInt32, _ dark: UInt32) -> Color {
        let value = self.dark ? dark : light
        return Color(.sRGB, red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
    var background: Color { color(0xFAF5ED, 0x18241D) }
    var editor: Color { color(0xFFFCF5, 0x202F25) }
    var border: Color { color(0xD4DBCA, 0x43533F) }
    var text: Color { color(0x263F21, 0xF4F0DF) }
    var secondary: Color { color(0x5D6956, 0xB8C4AE) }
    var accent: Color { color(0x416B2C, 0xB2D773) }
    var accentSoft: Color { color(0xE9EFDC, 0x2D402B) }
    var pink: Color { color(0xF9D1D9, 0x48333D) }
    var recording: Color { color(0x913F59, 0xF1B9C7) }
    var warning: Color { color(0x805519, 0xE9C17D) }
    var error: Color { color(0xA13245, 0xFFADB8) }
    var errorSurface: Color { color(0xFBE9E8, 0x412C33) }
    var button: Color { color(0x355728, 0xB2D773) }
    var buttonText: Color { color(0xFFFAEB, 0x233B1C) }
    var recordingButton: Color { color(0xF9D1D9, 0xEAB2C1) }
    var recordingButtonText: Color { color(0x703348, 0x432534) }

    func status(_ tone: DictationStatusTone) -> Color {
        switch tone {
        case .neutral: secondary
        case .success: accent
        case .warning: warning
        case .error: error
        }
    }
}

struct DictationScreen: View {
    @Binding var transcript: String
    var state: DictationViewState
    var start: () -> Void = {}
    var stop: () -> Void = {}
    var cancel: () -> Void = {}
    var importAudio: () -> Void = {}
    var settings: () -> Void = {}
    var allowInsertion: () -> Void = {}
    @Environment(\.colorScheme) private var scheme
    @State private var copied = false

    private var palette: DictationPalette { DictationPalette(scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 18)
            shortcut
                .padding(.bottom, 18)
            editor
            status
                .padding(.vertical, 12)
            controls
        }
        .padding(20)
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .accentColor(palette.accent)
        .background(palette.background)
        .onChange(of: transcript) { copied = false }
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(2)); copied = false }
            catch { }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(palette.recording)
                .frame(width: 38, height: 38)
                .background(palette.pink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Froggy Talkie").font(.system(size: 20, weight: .semibold))
                Text("Русский и английский · на этом Mac")
                    .font(.system(size: 12)).foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Button(action: importAudio) {
                    Image(systemName: "doc").frame(width: 30, height: 30)
                }
                .disabled(!state.canRecord)
                .help("Открыть аудиофайл")
                .accessibilityLabel("Открыть аудиофайл")
                Button(action: settings) {
                    Image(systemName: "slider.horizontal.3").frame(width: 30, height: 30)
                }
                .help("Настройки · ⌘,")
                .accessibilityLabel("Настройки")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(palette.secondary)
            .font(.system(size: 15))
        }
    }

    private var shortcut: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Text("Удерживайте").padding(.trailing, 3)
                ForEach(state.shortcut.modifierSymbols, id: \.self) { key($0) }
                key(state.shortcut.keyLabel)
            }
            .font(.system(size: 12))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Удерживайте \(state.shortcut.accessibilityLabel) в редакторе")

            if let error = state.hotKeyError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.insertionAllowed {
                Text(state.hotKeyError == nil ? "Отпустите — текст вставится у курсора." : "Выберите свободное сочетание в настройках.")
                    .font(.system(size: 12)).foregroundStyle(palette.secondary)
                    .help("В поддерживаемом текстовом поле. Если вставка недоступна, текст останется в этом окне.")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Для вставки нужен Универсальный доступ.")
                        .font(.system(size: 12)).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Разрешить", action: allowInsertion)
                        .controlSize(.small)
                        .accessibilityLabel("Разрешить вставку")
                }
            }
        }
    }

    private func key(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 7)
            .frame(minWidth: 25, minHeight: 24)
            .foregroundStyle(palette.accent)
            .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.border))
    }

    private var editor: some View {
        VStack(spacing: 0) {
            HStack {
                Text("РАСШИФРОВКА").font(.system(size: 10, weight: .semibold)).tracking(0.8)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(transcript, forType: .string)
                } label: {
                    Label(copied ? "Скопировано" : "Копировать", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(transcript.isEmpty)
                .accessibilityLabel(copied ? "Текст скопирован" : "Копировать текст")
            }
            .font(.system(size: 11))
            .foregroundStyle(palette.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ZStack(alignment: .topLeading) {
                TextEditor(text: $transcript)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.text)
                    .scrollContentBackground(.hidden)
                    .disabled(state.isBusy)
                    .padding(.horizontal, 9)
                    .padding(.bottom, 10)
                    .accessibilityLabel("Распознанный текст")
                if transcript.isEmpty {
                    Text("Здесь появится расшифровка.\nЕё можно отредактировать и скопировать.")
                        .font(.system(size: 14)).lineSpacing(5)
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 14).padding(.top, 1)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 100)
        }
        .background(palette.editor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(palette.border))
    }

    private var statusColor: Color {
        state.isRecording ? palette.recording : (state.isWorking ? palette.accent : palette.status(state.statusTone))
    }

    private var status: some View {
        HStack(alignment: .center, spacing: 7) {
            if state.isWorking {
                ProgressView().controlSize(.mini).frame(width: 12, height: 12)
                    .accessibilityLabel("Выполняется операция")
            } else {
                Image(systemName: state.isRecording ? "record.circle" :
                    (state.statusTone == .error ? "exclamationmark.circle.fill" :
                    (state.statusTone == .warning ? "exclamationmark.triangle.fill" : "checkmark.circle")))
                    .font(.system(size: 12)).foregroundStyle(statusColor).accessibilityHidden(true)
            }
            Text(state.displayStatus)
                .font(.system(size: 12)).foregroundStyle(statusColor)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .help(state.status)
            Spacer(minLength: 0)
            if state.isRecording {
                GeometryReader { geometry in
                    Capsule().fill(palette.border)
                        .overlay(alignment: .leading) {
                            Capsule().fill(palette.accent)
                                .frame(width: geometry.size.width * min(1, max(0, state.microphoneLevel)))
                        }
                }
                .frame(width: 35, height: 4)
                .accessibilityLabel("Уровень микрофона")
                .accessibilityValue("\(Int(state.microphoneLevel * 100)) процентов шкалы")
                Text(state.recordingTime).font(.system(size: 12).monospacedDigit())
                    .accessibilityLabel("Длительность записи \(state.recordingTime)")
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if !state.modelReady && !state.isWorking {
                Button("Настроить модель", systemImage: "slider.horizontal.3", action: settings)
                    .buttonStyle(DictationPrimaryButtonStyle())
            } else {
                Button(state.isRecording ? "Завершить запись" : "Начать запись",
                       systemImage: state.isRecording ? "stop.fill" : "mic.fill",
                       action: state.isRecording ? stop : start)
                    .buttonStyle(DictationPrimaryButtonStyle(recording: state.isRecording))
                    .disabled(!state.isRecording && !state.canRecord)
            }
            if state.isBusy {
                Button("Отмена", action: cancel)
                    .buttonStyle(.borderless)
                    .disabled(state.isCancelling)
            }
            Spacer(minLength: 0)
            Text("До 3 минут").font(.system(size: 11)).foregroundStyle(palette.secondary)
        }
    }
}

struct DictationPrimaryButtonStyle: ButtonStyle {
    var recording = false
    var height: CGFloat = 38
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let palette = DictationPalette(scheme: scheme)
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .frame(height: height)
            .foregroundStyle(enabled ? (recording ? palette.recordingButtonText : palette.buttonText) : palette.secondary)
            .background(enabled ? (recording ? palette.recordingButton : palette.button) : palette.accentSoft,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed && enabled ? 0.8 : 1)
    }
}

struct DictationSettingsScreen: View {
    @Binding var appearance: DictationAppearance
    var modelsPath: String
    var modelReady: Bool
    var isBusy: Bool
    var status: String
    var hotKeyStatus: String
    var hotKeyWarning = false
    var statusTone: DictationStatusTone = .neutral
    var insertionAllowed: Bool
    var downloadProgress: Double?
    var isCancelling = false
    var changeShortcut: () -> Void = {}
    var chooseModels: () -> Void = {}
    var prepare: () -> Void = {}
    var download: () -> Void = {}
    var cancelDownload: () -> Void = {}
    var allowInsertion: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    private var palette: DictationPalette { DictationPalette(scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Настройки").font(.system(size: 20, weight: .semibold))
            VStack(alignment: .leading, spacing: 10) {
                heading("Оформление")
                Picker("Тема", selection: $appearance) {
                    ForEach(DictationAppearance.allCases, id: \.self) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            Rectangle().fill(palette.border).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                heading("Диктовка")
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(hotKeyStatus).font(.system(size: 13))
                        .foregroundStyle(hotKeyWarning ? palette.warning : palette.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("Изменить…", action: changeShortcut)
                        .controlSize(.small).disabled(isBusy)
                        .accessibilityLabel("Изменить сочетание клавиш")
                }
                HStack {
                    Text("Вставка у курсора")
                    Spacer()
                    if insertionAllowed {
                        Label("Разрешена", systemImage: "checkmark.circle.fill").foregroundStyle(palette.accent)
                    } else {
                        Button("Разрешить вставку", action: allowInsertion).controlSize(.small)
                    }
                }.font(.system(size: 12))
                Text("Ручная запись оставляет текст в главном окне. Горячая клавиша вставляет его в поддерживаемое поле; поля паролей исключены.")
                    .font(.system(size: 12)).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(palette.border).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    heading("Локальная модель")
                    Spacer()
                    Label(modelReady ? "Готова" : "Требует подготовки", systemImage: modelReady ? "checkmark.circle.fill" : "circle.dashed")
                        .font(.system(size: 12)).foregroundStyle(modelReady ? palette.accent : palette.warning)
                }
                Text("Parakeet Ultra").font(.system(size: 13))
                if let downloadProgress {
                    ProgressView(value: downloadProgress).accessibilityLabel("Загрузка модели")
                    Button(isCancelling ? "Отмена…" : "Отменить загрузку", action: cancelDownload)
                        .controlSize(.small).disabled(isCancelling)
                } else if !modelReady {
                    Button("Загрузить модель · 632 МБ", action: download)
                        .buttonStyle(DictationPrimaryButtonStyle()).disabled(isBusy)
                    Text("Один раз с Hugging Face. После загрузки диктовка работает без интернета.")
                        .font(.system(size: 12)).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(modelsPath).font(.system(size: 11)).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                HStack {
                    Button("Выбрать папку…", action: chooseModels).disabled(isBusy)
                    Button(modelReady ? "Модель готова" : "Подготовить", action: prepare)
                        .disabled(isBusy || modelReady)
                }.controlSize(.small)
                if !modelReady {
                    Text(status).font(.system(size: 12)).foregroundStyle(palette.status(statusTone))
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
            }
            Label("Аудио обрабатывается на этом Mac.\nИстория записей не сохраняется.", systemImage: "lock.shield")
                .font(.system(size: 12)).foregroundStyle(palette.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(24)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(palette.text)
        .tint(palette.accent)
        .accentColor(palette.accent)
        .background(palette.background)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.accent)
    }
}
