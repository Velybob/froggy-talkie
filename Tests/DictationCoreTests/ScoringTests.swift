import Testing
import Foundation
@testable import DictationCore

@Test func bilingualNormalization() {
    #expect(Scoring.words("Ёлка, тест: SwiftUI — doesn’t STOP!") == ["елка", "тест", "swiftui", "doesn't", "stop"])
    #expect(Scoring.words("42, 3.5 и сорок два") == ["42", "3", "5", "и", "сорок", "два"])
}

@Test func wordErrorDistance() {
    #expect(Scoring.edits(reference: ["один", "два"], hypothesis: ["один", "три"]) == 1)
    #expect(Scoring.edits(reference: ["go", "go", "home"], hypothesis: ["go", "home", "now"]) == 2)
    #expect(Scoring.edits(reference: [], hypothesis: ["hallucination"]) == 1)
    #expect(Scoring.edits(reference: ["one", "two"], hypothesis: []) == 2)
    #expect(Scoring.edits(reference: [], hypothesis: []) == 0)
}

@Test func nearestRankPercentiles() {
    #expect(Scoring.percentile([], fraction: 0.95) == nil)
    #expect(Scoring.percentile([3, 1, 2, 4], fraction: 0.5) == 2)
    #expect(Scoring.percentile(Array(1...20).map(Double.init), fraction: 0.95) == 19)
}

@Test func missingPreparationFailsWithoutLoadingModel() async {
    let recognizer = ParakeetRecognizer(modelsRoot: URL(fileURLWithPath: "/nonexistent"))
    await #expect(throws: RecognitionError.self) {
        try await recognizer.transcribe(file: URL(fileURLWithPath: "/nonexistent.wav"))
    }
}
