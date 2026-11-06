import Foundation

public struct Recognition: Sendable, Codable {
    public let text: String
    public let audioSeconds: Double
    public let processingSeconds: Double

    public init(text: String, audioSeconds: Double, processingSeconds: Double) {
        self.text = text
        self.audioSeconds = audioSeconds
        self.processingSeconds = processingSeconds
    }
}

public enum RecognitionError: LocalizedError {
    case busy
    case notPrepared
    case emptyAudio

    public var errorDescription: String? {
        switch self {
        case .busy: "Распознавание уже выполняется."
        case .notPrepared: "Сначала загрузите модель."
        case .emptyAudio: "В записи нет звука."
        }
    }
}

public protocol SpeechRecognizer: Sendable {
    func prepare() async throws
    func transcribe(file: URL) async throws -> Recognition
}
