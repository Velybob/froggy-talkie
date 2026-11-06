import Foundation
import CoreML
import DictationCore
@preconcurrency import WhisperKit

/// Benchmark-only engine. The application product does not link WhisperKit.
public actor WhisperRecognizer: SpeechRecognizer {
    private let modelsRoot: URL
    private var engine: WhisperKit?
    private var busy = false

    public init(modelsRoot: URL) { self.modelsRoot = modelsRoot }

    public func prepare() async throws {
        guard !busy else { throw RecognitionError.busy }
        guard engine == nil else { return }
        busy = true
        defer { busy = false }
        let modelFolder = modelsRoot.appendingPathComponent("whisper-turbo")
        let tokenizerFolder = modelsRoot.appendingPathComponent("whisper-tokenizer")
        let kit = try await WhisperKit(WhisperKitConfig(
            modelFolder: modelFolder.path, tokenizerFolder: tokenizerFolder,
            computeOptions: ModelComputeOptions(), verbose: false,
            prewarm: false, load: false, download: false))
        // Validate before loading: malformed/missing local tokenizers fail here.
        // The benchmark additionally denies network access at the process level.
        _ = try await AutoTokenizerWrapper.from(modelFolder: tokenizerFolder,
            hubApi: HubApiWrapper(downloadBase: modelsRoot))
        try await kit.loadModels()
        try Task.checkCancellation()
        engine = kit
    }

    public func transcribe(file: URL) async throws -> Recognition {
        guard !busy else { throw RecognitionError.busy }
        guard let engine else { throw RecognitionError.notPrepared }
        busy = true
        defer { busy = false }
        try Task.checkCancellation()
        let start = ContinuousClock.now
        let samples = try AudioInput.samples16kMono(file: file)
        guard !samples.isEmpty else { throw RecognitionError.emptyAudio }
        let options = DecodingOptions(temperature: 0, temperatureFallbackCount: 0,
            detectLanguage: true, skipSpecialTokens: true,
            withoutTimestamps: true, concurrentWorkerCount: 1)
        let results = try await engine.transcribe(audioArray: samples, decodeOptions: options)
        try Task.checkCancellation()
        return Recognition(text: results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines),
            audioSeconds: Double(samples.count) / 16_000,
            processingSeconds: start.duration(to: .now).seconds)
    }
}
