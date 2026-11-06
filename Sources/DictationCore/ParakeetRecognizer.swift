import CoreML
import FluidAudio
import Foundation

/// Owns a single engine; rejects overlapping work instead of mixing decoder sessions.
public actor ParakeetRecognizer: SpeechRecognizer {
    public enum Compute: String, Sendable { case ane, gpu }

    private let modelDirectory: URL
    private let compute: Compute
    private let allowDownload: Bool
    private let manager = AsrManager()
    private var prepared = false
    private var busy = false

    public init(modelsRoot: URL, compute: Compute = .ane, allowDownload: Bool = false) {
        // The SDK's default cache leaf (parakeet-ultra) differs from its repository
        // folder (parakeet-ultra-coreml). Our pinned downloader uses the latter.
        self.modelDirectory = modelsRoot.appendingPathComponent("parakeet-ultra-coreml")
        self.compute = compute
        self.allowDownload = allowDownload
    }

    public func prepare() async throws {
        guard !busy else { throw RecognitionError.busy }
        guard !prepared else { return }
        busy = true
        defer { busy = false }
        try Task.checkCancellation()
        let units: MLComputeUnits = compute == .ane ? .cpuAndNeuralEngine : .cpuAndGPU
        if allowDownload {
            try await AsrModels.download(to: modelDirectory, version: .ultra, encoderComputeUnits: units)
        }
        // Missing weights fail locally; inference never silently starts a download.
        let models = try AsrModels.loadLocal(from: modelDirectory, version: .ultra, encoderComputeUnits: units)
        try await manager.loadModels(models)
        try Task.checkCancellation()
        prepared = true
    }

    public func transcribe(file: URL) async throws -> Recognition {
        guard !busy else { throw RecognitionError.busy }
        guard prepared else { throw RecognitionError.notPrepared }
        busy = true
        defer { busy = false }
        try Task.checkCancellation()
        let start = ContinuousClock.now
        let samples = try AudioInput.samples16kMono(file: file)
        guard !samples.isEmpty else { throw RecognitionError.emptyAudio }
        var decoder = try TdtDecoderState()
        // No language filter: Russian and English may share an utterance.
        let result = try await manager.transcribe(samples, decoderState: &decoder)
        try Task.checkCancellation()
        return Recognition(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            audioSeconds: Double(samples.count) / 16_000,
            processingSeconds: start.duration(to: .now).seconds)
    }
}

public extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
