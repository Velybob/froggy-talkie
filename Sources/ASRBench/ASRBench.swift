import DictationCore
import WhisperEngine
import Foundation
import CryptoKit
import Darwin

@main
struct ASRBench {
    struct Sample: Codable {
        let id: String
        let language: String
        let path: String
        let reference: String
        let sha256: String
    }
    struct Manifest: Decodable {
        let dataset: String
        let revision: String
        let samples: [Sample]
    }
    struct Measurement: Codable {
        let sample: Sample
        let iteration: Int
        let result: Recognition
        let referenceWords: Int
        let edits: Int
    }
    struct LanguageSummary: Codable {
        let language: String
        let files: Int
        let wer: Double?
        let referenceWords: Int
        let edits: Int
        let p50Seconds: Double?
        let p95Seconds: Double?
        let realTimeSpeed: Double
    }
    struct Report: Codable {
        let date: Date
        let model: String
        let sdk: String
        let compute: String
        let operatingSystem: String
        let physicalMemoryBytes: UInt64
        let thermalStateAtEnd: Int
        let dataset: String
        let datasetRevision: String
        let prepareSeconds: Double
        let firstInference: Recognition
        let peakProcessRSSBytes: Int64
        let repeats: Int
        let summaries: [LanguageSummary]
        let measurements: [Measurement]
        let limitations: [String]
    }
    enum CLIError: LocalizedError {
        case usage(String)
        var errorDescription: String? { switch self { case .usage(let text): return text } }
    }
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        var options: [String: String] = [:]
        var download = false
        var index = 1
        let args = CommandLine.arguments
        while index < args.count {
            if args[index] == "--download" { download = true; index += 1; continue }
            if args[index] == "--help" {
                print("asr-bench --models DIR [--download] [--engine parakeet|whisper --manifest FILE --output FILE --repeats 2 --compute ane|gpu]")
                return
            }
            guard ["--models", "--manifest", "--output", "--repeats", "--compute", "--engine"].contains(args[index]), index + 1 < args.count else {
                throw CLIError.usage("Unknown or incomplete option: \(args[index])")
            }
            options[args[index]] = args[index + 1]
            index += 2
        }
        guard let models = options["--models"] else { throw CLIError.usage("--models DIR is required") }
        guard let compute = ParakeetRecognizer.Compute(rawValue: options["--compute"] ?? "ane"),
              let repeats = Int(options["--repeats"] ?? "2"), (1...10).contains(repeats) else {
            throw CLIError.usage("Use --compute ane|gpu and --repeats 1...10")
        }
        let selectedEngine = options["--engine"] ?? "parakeet"
        let recognizer: any SpeechRecognizer
        let modelName: String
        let sdkName: String
        let computeDescription: String
        switch selectedEngine {
        case "parakeet":
            recognizer = ParakeetRecognizer(modelsRoot: URL(fileURLWithPath: models), compute: compute, allowDownload: download)
            modelName = "moondream/parakeet-ultra via FluidInference/parakeet-ultra-coreml"
            sdkName = "FluidAudio 0.18.2"
            computeDescription = compute.rawValue
        case "whisper":
            guard !download, compute == .ane else { throw CLIError.usage("Whisper: stage whisper-turbo and whisper-tokenizer locally; use default compute options (see docs/DEVELOPMENT.md)") }
            recognizer = WhisperRecognizer(modelsRoot: URL(fileURLWithPath: models))
            modelName = "openai/whisper-large-v3-turbo via argmaxinc/whisperkit-coreml (FP16 turbo)"
            sdkName = "WhisperKit 1.1.1; greedy, detectLanguage=true, no temperature fallback, no timestamps"
            computeDescription = "SDK defaults: encoder/decoder CPU+ANE; mel CPU+GPU"
        default: throw CLIError.usage("--engine must be parakeet or whisper")
        }
        print("Preparing \(selectedEngine) (\(computeDescription)); downloads \(download ? "allowed" : "disabled")…")
        let preparationStart = ContinuousClock.now
        try await recognizer.prepare()
        let prepareSeconds = preparationStart.duration(to: .now).seconds
        print(String(format: "Prepared in %.3f seconds", prepareSeconds))
        guard let manifestPath = options["--manifest"] else {
            guard download else { throw CLIError.usage("Supply --manifest FILE or --download") }
            return
        }
        guard let output = options["--output"] else { throw CLIError.usage("--output FILE is required for benchmarks") }
        let manifestURL = URL(fileURLWithPath: manifestPath).standardizedFileURL
        let root = manifestURL.deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard let first = manifest.samples.first else { throw CLIError.usage("Manifest is empty") }
        func audioURL(_ sample: Sample) throws -> URL {
            let url = root.appendingPathComponent(sample.path).standardizedFileURL
            guard url.path.hasPrefix(root.path + "/") else { throw CLIError.usage("Invalid sample path") }
            return url
        }
        // Validate outside the timed region; no corrupt audio silently enters the comparison.
        for sample in manifest.samples {
            let digest = SHA256.hash(data: try Data(contentsOf: audioURL(sample)))
                .map { String(format: "%02x", $0) }.joined()
            guard digest == sample.sha256 else { throw CLIError.usage("SHA-256 mismatch: \(sample.id)") }
        }
        let firstInference = try await recognizer.transcribe(file: audioURL(first))
        var measurements: [Measurement] = []
        for iteration in 0..<repeats {
            // Alternate order to reduce language/order confounding over repeated passes.
            let samples = iteration.isMultiple(of: 2) ? manifest.samples : manifest.samples.reversed().map { $0 }
            for sample in samples {
                let result = try await recognizer.transcribe(file: audioURL(sample))
                let reference = Scoring.words(sample.reference)
                let edits = Scoring.edits(reference: reference, hypothesis: Scoring.words(result.text))
                measurements.append(Measurement(sample: sample, iteration: iteration, result: result,
                    referenceWords: reference.count, edits: edits))
                print(String(format: "[%d] %@ %.3fs / %.2fs audio", iteration + 1, sample.id,
                    result.processingSeconds, result.audioSeconds))
            }
        }
        let languages = Set(manifest.samples.map(\.language)).sorted()
        let summaries = languages.map { language -> LanguageSummary in
            let all = measurements.filter { $0.sample.language == language }
            let accuracy = all.filter { $0.iteration == 0 }
            let words = accuracy.reduce(0) { $0 + $1.referenceWords }
            let edits = accuracy.reduce(0) { $0 + $1.edits }
            let times = all.map { $0.result.processingSeconds }
            return LanguageSummary(language: language, files: accuracy.count,
                wer: words > 0 ? Double(edits) / Double(words) : nil, referenceWords: words, edits: edits,
                p50Seconds: Scoring.percentile(times, fraction: 0.5),
                p95Seconds: Scoring.percentile(times, fraction: 0.95),
                realTimeSpeed: all.reduce(0) { $0 + $1.result.audioSeconds } / times.reduce(0, +))
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let report = Report(date: Date(), model: modelName,
            sdk: sdkName, compute: computeDescription,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            thermalStateAtEnd: ProcessInfo.processInfo.thermalState.rawValue,
            dataset: manifest.dataset, datasetRevision: manifest.revision,
            prepareSeconds: prepareSeconds, firstInference: firstInference,
            peakProcessRSSBytes: Int64(usage.ru_maxrss), repeats: repeats, summaries: summaries,
            measurements: measurements, limitations: [
                "Preparation includes local model load; system Core ML compilation caches may already be warm.",
                "Latency includes file conversion and whole-utterance inference, not microphone/UI/paste latency.",
                "Peak RSS is this process only, not total system/ANE memory.",
                "Small read-speech sample; does not establish personal dictation or code-switch quality.",
                "WER ignores case/punctuation and е/ё; number spelling is not normalized."
            ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let destination = URL(fileURLWithPath: output)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(report).write(to: destination, options: .atomic)
        print("Saved: \(destination.path)")
    }
}
