import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import DictationCore
import DictationSystem
import DictationModels

struct LocalDictationApp: App {
    @StateObject private var model = DictationModel.shared
    @NSApplicationDelegateAdaptor(DictationAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Froggy Talkie", id: "dictation") {
            DictationView(model: model)
                .frame(minWidth: 440, minHeight: 440)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 500, height: 492)
        .windowResizability(.contentMinSize)

        Settings {
            DictationSettingsView(model: model)
        }

        MenuBarExtra("Froggy Talkie", systemImage: "waveform") {
            MenuContent(model: model)
        }
    }
}

@MainActor
final class DictationAppDelegate: NSObject, NSApplicationDelegate {
    weak var model: DictationModel?
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}

private struct MenuContent: View {
    @ObservedObject var model: DictationModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.status)
        Text(model.hotKeyStatus)
        Button("Открыть диктовку") {
            openWindow(id: "dictation")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text("Настройки…") }
        Divider()
        Button("Завершить") { model.shutdown(); NSApp.terminate(nil) }
    }
}

private struct DictationView: View {
    @ObservedObject var model: DictationModel
    @AppStorage("appearance") private var appearance: DictationAppearance = .system
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        DictationScreen(
            transcript: $model.transcript,
            state: DictationViewState(
                status: model.status, statusTone: model.statusTone, shortcut: model.shortcut, hotKeyError: model.hotKeyError,
                isRecording: model.isRecording, isWorking: model.isWorking,
                isCancelling: model.isCancelling, canRecord: model.canRecord,
                modelReady: model.ready, insertionAllowed: model.insertionAllowed,
                recordingTime: model.recordingTime, microphoneLevel: model.microphoneLevel),
            start: model.startRecording, stop: model.stopRecording, cancel: model.cancel,
            importAudio: model.chooseAudio, settings: { openSettings() },
            allowInsertion: model.requestInsertionPermission)
        .onChange(of: appearance, initial: true) { _, value in value.apply() }
        .background(CompactWindowMigration())
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshInsertionPermission()
        }
        .onDisappear { model.windowClosed() }
    }
}

/// Apply the new compact size once to windows restored from the old prototype.
/// Subsequent launches preserve the user's own window size.
private struct CompactWindowMigration: NSViewRepresentable {
    func makeNSView(context: Context) -> SizingView { SizingView() }
    func updateNSView(_ view: SizingView, context: Context) {}

    final class SizingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [weak window] in
                guard let window, !UserDefaults.standard.bool(forKey: "compactWindowLayoutApplied") else { return }
                window.setContentSize(NSSize(width: 500, height: 492))
                UserDefaults.standard.set(true, forKey: "compactWindowLayoutApplied")
            }
        }
    }
}

private struct DictationSettingsView: View {
    @ObservedObject var model: DictationModel
    @AppStorage("appearance") private var appearance: DictationAppearance = .system
    @State private var editingShortcut = false

    var body: some View {
        DictationSettingsScreen(appearance: $appearance, modelsPath: model.modelsRoot.path,
            modelReady: model.ready, isBusy: model.isBusy, status: model.status,
            hotKeyStatus: model.hotKeyStatus, hotKeyWarning: model.hotKeyError != nil,
            statusTone: model.statusTone, insertionAllowed: model.insertionAllowed,
            downloadProgress: model.downloadProgress, isCancelling: model.isCancelling,
            changeShortcut: {
                if model.beginShortcutEditing() { editingShortcut = true }
            },
            chooseModels: model.chooseModels, prepare: model.prepare,
            download: model.downloadModel, cancelDownload: model.cancel,
            allowInsertion: model.requestInsertionPermission)
        .onChange(of: appearance, initial: true) { _, value in value.apply() }
        .sheet(isPresented: $editingShortcut, onDismiss: model.finishShortcutEditing) {
            ShortcutEditor(shortcut: model.shortcut, save: model.saveShortcut,
                close: { editingShortcut = false })
        }
        .onDisappear { model.finishShortcutEditing() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshInsertionPermission()
        }
    }
}

@MainActor
final class DictationModel: ObservableObject {
    // Every scene must share one recorder and one Carbon registration, including
    // scene construction before SwiftUI installs the App's StateObject storage.
    static let shared = DictationModel()
    enum State: Equatable { case idle, downloading, loading, ready, recording, processing, cancelling }
    @Published private(set) var state: State = .idle
    @Published private(set) var status = "Открой настройки и загрузи модель для диктовки." {
        didSet { statusTone = .neutral }
    }
    @Published private(set) var statusTone: DictationStatusTone = .neutral
    @Published private(set) var modelsRoot: URL
    @Published var transcript = ""
    @Published private(set) var recordingTime = "00:00"
    @Published private(set) var microphoneLevel = 0.0
    @Published private(set) var hotKeyStatus = "Удерживай ⌃⌥Пробел для диктовки"
    @Published private(set) var shortcut = DictationShortcut.default
    @Published private(set) var hotKeyError: String?
    @Published private(set) var isEditingShortcut = false
    @Published private(set) var insertionAllowed = false
    @Published private(set) var downloadProgress: Double?
    private let modelDownloader = ModelDownloader()
    private var downloadSession: UUID?
    private var recognizer: ParakeetRecognizer?
    private var task: Task<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var temporaryAudio: URL?
    private var levelEnvelope = RecordingLevel()
    private var lastMeterTime: TimeInterval = 0
    private var recordingBeganAt: ContinuousClock.Instant?
    private var modelPrepared = false
    private var hotKey: GlobalHotKey?
    private var holdGate = HoldToTalkGate()
    private var holdSession: UUID?
    private var insertionTarget: TextInsertion.Target?
    private var insertionNotice: String?
    private var globalOperation = false
    private let insertion = TextInsertion()
    private let overlay = RecordingOverlay()
    private var recordingTicker: Task<Void, Never>?

    var isRecording: Bool { state == .recording }
    var isCancelling: Bool { state == .cancelling }
    var isWorking: Bool { [.downloading, .loading, .processing, .cancelling].contains(state) }
    var isBusy: Bool { isWorking || isRecording }
    var ready: Bool { modelPrepared }
    var canRecord: Bool { state == .ready && !isEditingShortcut }

    init() {
        modelsRoot = ModelManifest.initialRoot(storedPath: UserDefaults.standard.string(forKey: "modelsRoot"),
            bundleURL: Bundle.main.bundleURL)
        refreshInsertionPermission()
        if let data = UserDefaults.standard.data(forKey: "dictationShortcut"),
           let saved = try? JSONDecoder().decode(DictationShortcut.self, from: data), saved.isValid {
            shortcut = saved
        }
        hotKey = GlobalHotKey(pressed: { [weak self] in self?.hotKeyPressed() },
            released: { [weak self] in self?.hotKeyReleased() })
        registerHotKey()
        if FileManager.default.fileExists(atPath: modelsRoot.appendingPathComponent("parakeet-ultra-coreml").path) {
            prepare()
        }
    }

    func refreshInsertionPermission() { insertionAllowed = insertion.isTrusted }

    private func registerHotKey() {
        do {
            try hotKey?.register(shortcut: shortcut)
            hotKeyError = nil
            hotKeyStatus = "Удерживай \(shortcut.display) для диктовки"
        } catch {
            hotKeyError = error.localizedDescription
            hotKeyStatus = error.localizedDescription
        }
    }

    func beginShortcutEditing() -> Bool {
        guard !isBusy, !isEditingShortcut, !holdGate.isHeld else { return false }
        // Capture only inside our sheet. Releasing registration prevents the old
        // shortcut from starting a microphone session while the user edits it.
        isEditingShortcut = true
        hotKey?.unregister()
        return true
    }

    func saveShortcut(_ candidate: DictationShortcut) throws {
        guard isEditingShortcut, !isBusy else { return }
        let data = try JSONEncoder().encode(candidate)
        try hotKey?.register(shortcut: candidate)
        shortcut = candidate
        UserDefaults.standard.set(data, forKey: "dictationShortcut")
        hotKeyError = nil
        hotKeyStatus = "Удерживай \(shortcut.display) для диктовки"
    }

    func finishShortcutEditing() {
        guard isEditingShortcut else { return }
        isEditingShortcut = false
        registerHotKey()
    }

    func requestInsertionPermission() {
        insertion.requestPermission()
        refreshInsertionPermission()
    }

    private func hotKeyPressed() {
        guard !holdGate.isHeld else { return }
        let session = UUID()
        guard holdGate.press(canStart: canRecord, session: session) else {
            if !canRecord { overlay.show(modelPrepared ? "Дождись окончания текущей операции." : "Подготовь модель в окне диктовки.", title: "Нет записи", warning: true, dismissAfter: 5) }
            return
        }
        do {
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                throw AppError.message("Сначала разреши микрофон кнопкой «Начать запись» в окне диктовки.")
            }
            refreshInsertionPermission()
            insertionTarget = nil
            insertionNotice = nil
            do { insertionTarget = try insertion.captureTarget() }
            catch { insertionNotice = error.localizedDescription }
            holdSession = session
            globalOperation = true
            beginRecording(session: session)
        } catch {
            holdGate.cancelSession()
            status = error.localizedDescription
            statusTone = .error
            overlay.show(status, title: "Нет записи", warning: true, dismissAfter: 6)
        }
    }

    private func hotKeyReleased() {
        switch holdGate.release() {
        case .none: break
        case .cancelPending(let id):
            if holdSession == id { cancel() }
        case .finish(let id):
            if holdSession == id { stopRecording() }
        }
    }

    func chooseModels() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Выбери папку Models, содержащую parakeet-ultra-coreml."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        modelsRoot = url
        UserDefaults.standard.set(url.path, forKey: "modelsRoot")
        recognizer = nil
        modelPrepared = false
        state = .idle
        status = "Папка выбрана. Подготовь модель."
    }

    func prepare() {
        guard !isBusy, !modelPrepared else { return }
        let engine = ParakeetRecognizer(modelsRoot: modelsRoot)
        recognizer = engine
        state = .loading
        status = "Подготовка модели на этом Mac…"
        task = Task {
            do {
                try await engine.prepare()
                try Task.checkCancellation()
                modelPrepared = true
                status = "Готово. Можно записывать или открыть аудиофайл."
                statusTone = .success
            } catch { report(error) }
            state = modelPrepared ? .ready : .idle
            task = nil
        }
    }

    func downloadModel() {
        guard !isBusy, !modelPrepared else { return }
        let session = UUID()
        downloadSession = session
        state = .downloading
        downloadProgress = 0
        status = "Загрузка модели с Hugging Face…"
        task = Task {
            do {
                let manifest = try ModelManifest.bundled()
                let root = ModelManifest.applicationSupportRoot
                try await modelDownloader.install(to: root, manifest: manifest) { [weak self] done, total in
                    Task { @MainActor [weak self] in
                        guard let self, self.downloadSession == session, self.state == .downloading else { return }
                        self.downloadProgress = Double(done) / Double(total)
                        self.status = "Загрузка модели: \(Int(done / 1_000_000)) из \(Int(total / 1_000_000)) МБ"
                    }
                }
                try Task.checkCancellation()
                downloadSession = nil
                downloadProgress = nil
                modelsRoot = root
                UserDefaults.standard.set(root.path, forKey: "modelsRoot")
                state = .idle
                task = nil
                prepare()
            } catch {
                downloadSession = nil
                downloadProgress = nil
                report(error)
                state = modelPrepared ? .ready : .idle
                task = nil
            }
        }
    }

    func startRecording() {
        guard canRecord else { return }
        globalOperation = false
        insertionTarget = nil
        insertionNotice = nil
        holdSession = nil
        beginRecording(session: nil)
    }

    private func beginRecording(session: UUID?) {
        state = .loading
        status = "Проверка доступа к микрофону…"
        if session != nil { overlay.show("Можно говорить после появления таймера.", title: "Подготовка", cancel: { [weak self] in self?.cancel() }) }
        task = Task {
            let granted: Bool
            if session != nil {
                granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            } else {
                granted = await AVCaptureDevice.requestAccess(for: .audio)
            }
            do {
                try Task.checkCancellation()
                guard granted else { throw AppError.message("Нет доступа к микрофону. Разреши его в настройках конфиденциальности macOS.") }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("LocalDictation-\(UUID().uuidString).caf")
                temporaryAudio = url
                let capture = try AVAudioRecorder(url: url, settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                ])
                capture.isMeteringEnabled = true
                if let session {
                    guard holdSession == session, holdGate.recorderReady(session: session) else { throw CancellationError() }
                }
                try Task.checkCancellation()
                guard capture.record() else { throw AppError.message("Не удалось начать запись.") }
                recorder = capture
                recordingBeganAt = .now
                levelEnvelope = RecordingLevel()
                lastMeterTime = 0
                microphoneLevel = 0
                recordingTime = "00:00"
                state = .recording
                status = session == nil ? "Идёт запись. Нажми «Завершить», когда закончишь." :
                    (insertionTarget == nil ? "Идёт запись. Текст появится в окне диктовки: автовставка недоступна." : "Идёт запись. Отпусти \(shortcut.display) для вставки.")
                startRecordingTicker()
                updateRecordingTime()
            } catch {
                discardRecording()
                holdGate.cancelSession()
                holdSession = nil
                insertionTarget = nil
                insertionNotice = nil
                state = .ready
                report(error)
                overlay.show(status, title: "Нет записи", warning: true, dismissAfter: 5)
                globalOperation = false
            }
            task = nil
        }
    }

    private func startRecordingTicker() {
        recordingTicker?.cancel()
        recordingTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))
                guard !Task.isCancelled, let self, self.isRecording else { return }
                self.updateRecordingTime()
            }
        }
    }

    func updateRecordingTime() {
        guard isRecording, let recorder else { return }
        let elapsed = recorder.currentTime
        recordingTime = RecordingClock.display(seconds: elapsed)
        recorder.updateMeters()
        levelEnvelope.update(decibels: recorder.averagePower(forChannel: 0), elapsed: elapsed - lastMeterTime)
        lastMeterTime = elapsed
        microphoneLevel = levelEnvelope.value
        let hint = globalOperation ? (insertionTarget == nil ? "Текст появится в окне диктовки" : "Отпусти \(shortcut.display) для вставки") : "Нажми «Завершить запись» в окне"
        overlay.showRecording(elapsed: recordingTime, levels: levelEnvelope.history, hint: hint,
            cancel: { [weak self] in self?.cancel() })
        if elapsed >= 180 || (recordingBeganAt?.duration(to: .now) ?? .zero) >= .seconds(180) { stopRecording() }
    }

    func stopRecording() {
        guard isRecording, let url = temporaryAudio else { return }
        recorder?.stop()
        recorder = nil
        recordingBeganAt = nil
        microphoneLevel = 0
        recordingTicker?.cancel()
        recordingTicker = nil
        let target = insertionTarget
        let notice = insertionNotice
        insertionTarget = nil
        insertionNotice = nil
        holdSession = nil
        holdGate.cancelSession()
        state = .ready
        transcribe(url, removeAfter: true, target: target, insertionNotice: notice)
    }

    func chooseAudio() {
        guard canRecord else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        transcribe(url, removeAfter: false)
    }

    private func transcribe(_ url: URL, removeAfter: Bool, target: TextInsertion.Target? = nil, insertionNotice: String? = nil) {
        guard let recognizer, canRecord else { return }
        state = .processing
        status = "Распознавание на Mac…"
        if removeAfter { overlay.show(status, title: "Распознавание", cancel: { [weak self] in self?.cancel() }) }
        task = Task {
            defer {
                if removeAfter { try? FileManager.default.removeItem(at: url); temporaryAudio = nil }
                state = .ready
                task = nil
                globalOperation = false
            }
            do {
                let audio = try AVAudioFile(forReading: url)
                guard Double(audio.length) / audio.processingFormat.sampleRate <= 180.5 else {
                    throw AppError.message("Поддерживаются записи до 3 минут.")
                }
                let result = try await recognizer.transcribe(file: url)
                try Task.checkCancellation()
                transcript = result.text
                status = result.text.isEmpty ? "Речь не распознана." : String(format: "Готово за %.2f с · запись %.1f с", result.processingSeconds, result.audioSeconds)
                statusTone = result.text.isEmpty ? .warning : .success
                // Clear the overlay before inserting so it never covers the result.
                if removeAfter { overlay.hide() }
                if let target, !result.text.isEmpty {
                    switch await insertion.insert(result.text, into: target) {
                    case .sent(let app):
                        status = String(format: "Передан в %@ · распознавание %.2f с", app, result.processingSeconds)
                        statusTone = .success
                    case .retained(let reason):
                        status = reason
                        statusTone = .warning
                        if removeAfter { overlay.show(status, title: "Текст в окне", warning: true, dismissAfter: 2) }
                    }
                } else if !result.text.isEmpty, let insertionNotice {
                    status = insertionNotice + " Распознано; текст доступен в окне."
                    statusTone = .warning
                    if removeAfter { overlay.show(status, title: "Текст в окне", warning: true, dismissAfter: 2) }
                }
            } catch {
                report(error)
                if removeAfter {
                    if error is CancellationError { overlay.hide() }
                    else { overlay.show(status, title: "Ошибка записи", error: true, dismissAfter: 3) }
                }
            }
        }
    }

    func cancel() {
        holdGate.cancelSession()
        holdSession = nil
        insertionTarget = nil
        insertionNotice = nil
        overlay.hide()
        if isRecording {
            discardRecording()
            state = modelPrepared ? .ready : .idle
            status = "Запись отменена."
            globalOperation = false
        } else if isWorking {
            task?.cancel()
            state = .cancelling
            status = "Отмена…"
        }
    }

    func windowClosed() {
        // Closing during a manual permission request must prevent a later hidden recording.
        // Global dictation continues when the main window is closed.
        if !globalOperation { cancel() }
    }

    func shutdown() {
        task?.cancel()
        discardRecording()
        hotKey?.unregister()
        insertion.restorePendingClipboard()
        overlay.hide()
    }

    private func discardRecording() {
        recorder?.stop()
        recorder = nil
        recordingBeganAt = nil
        microphoneLevel = 0
        levelEnvelope = RecordingLevel()
        lastMeterTime = 0
        recordingTicker?.cancel()
        recordingTicker = nil
        if let temporaryAudio { try? FileManager.default.removeItem(at: temporaryAudio) }
        temporaryAudio = nil
    }

    private func report(_ error: Error) {
        status = error is CancellationError ? "Операция отменена." : error.localizedDescription
        statusTone = error is CancellationError ? .neutral : .error
    }

    private enum AppError: LocalizedError {
        case message(String)
        var errorDescription: String? { switch self { case .message(let text): return text } }
    }
}
