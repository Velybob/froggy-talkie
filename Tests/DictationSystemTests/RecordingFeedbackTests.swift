import Foundation
import Testing
@testable import DictationSystem

@Test func silenceDoesNotAnimateThePanel() {
    var meter = RecordingLevel()
    for _ in 0..<40 { meter.update(decibels: -80, elapsed: 0.05) }
    #expect(meter.value == 0)
    #expect(meter.history.allSatisfy { $0 == 0 })
}

@Test func microphoneLevelRisesAndSettlesWithoutLeavingItsBounds() {
    var meter = RecordingLevel()
    meter.update(decibels: -12, elapsed: 0.05)
    let first = meter.value
    #expect(first > 0 && first < 1)
    for _ in 0..<20 { meter.update(decibels: -12, elapsed: 0.05) }
    let voiced = meter.value
    #expect(voiced > first && voiced <= 1)
    meter.update(decibels: -160, elapsed: 0.05)
    #expect(meter.value > 0 && meter.value < voiced)
    for _ in 0..<40 { meter.update(decibels: -160, elapsed: 0.05) }
    #expect(meter.value < 0.001)
}

@Test func invalidMeterInputsCannotCorruptTheLayout() {
    var meter = RecordingLevel()
    for power: Float in [.nan, -.infinity, .infinity, 100, -1_000] {
        for delta: Double in [.nan, .infinity, -1, 0, 1_000] {
            meter.update(decibels: power, elapsed: delta)
            #expect(meter.value.isFinite && (0...1).contains(meter.value))
            #expect(meter.history.allSatisfy { $0.isFinite && (0...1).contains($0) })
        }
    }
}

@Test func quietNormalAndLoudInputsRemainDistinctWithHeadroom() {
    func settled(_ decibels: Float) -> Double {
        var meter = RecordingLevel()
        for _ in 0..<20 { meter.update(decibels: decibels, elapsed: 0.05) }
        return meter.value
    }
    let quiet = settled(-45)
    let normal = settled(-30)
    let loud = settled(-12)
    let nearClipping = settled(-3)
    #expect(quiet > 0.02 && quiet < 0.15)
    #expect(normal > quiet + 0.5 && normal < 0.8)
    #expect(loud > normal + 0.15)
    #expect(nearClipping > loud + 0.04)
    #expect(nearClipping < 1)
}

@Test func smallSpeechChangesProduceVisibleContrastWithoutSaturation() {
    func settled(_ power: Float) -> Double {
        var meter = RecordingLevel()
        for _ in 0..<20 { meter.update(decibels: power, elapsed: 0.033) }
        return meter.value
    }
    let softer = settled(-42)
    let middle = settled(-36)
    let stronger = settled(-30)
    // Each 6 dB step should move more than a quarter of the waveform's height.
    #expect(middle - softer > 0.25)
    #expect(stronger - middle > 0.25)
    #expect(stronger < 0.8)
    #expect(settled(-54) < 0.03)
    #expect(settled(-18) < settled(-6))
}

@Test func syllableAttackAndPauseAreVisibleWithinOneTenthOfASecond() {
    var meter = RecordingLevel()
    meter.update(decibels: -30, elapsed: 0.033)
    #expect(meter.value > 0.65)
    for _ in 0..<3 { meter.update(decibels: -80, elapsed: 0.033) }
    #expect(meter.value < 0.08)
}

@Test func levelFollowsSpeechAndFallsWhenTheVoiceGetsQuieter() {
    var meter = RecordingLevel()
    for _ in 0..<10 { meter.update(decibels: -60, elapsed: 0.05) }
    #expect(meter.value == 0)
    meter.update(decibels: -12, elapsed: 0.05)
    #expect(meter.value > 0.5)
    for _ in 0..<6 { meter.update(decibels: -45, elapsed: 0.05) }
    #expect(meter.value > 0 && meter.value < 0.3)
    for _ in 0..<5 { meter.update(decibels: -80, elapsed: 0.05) }
    #expect(meter.value < 0.02)
}

@Test func waveformShowsMeasuredHistoryAndClearsAfterSilence() {
    var meter = RecordingLevel()
    var measurements: [Double] = []
    for power: Float in [-60, -45, -30, -12, -24, -42, -35, -16, -28, -48, -60] {
        meter.update(decibels: power, elapsed: 0.05)
        measurements.append(meter.value)
    }
    #expect(meter.history == Array(measurements.suffix(9)))
    #expect(Set(meter.history).count > 5)
    let previous = meter.history
    for invalidInterval: Double in [0, -1, .nan, .infinity] {
        meter.update(decibels: 0, elapsed: invalidInterval)
        #expect(meter.history == previous)
    }
    for _ in 0..<40 { meter.update(decibels: -80, elapsed: 0.05) }
    #expect(meter.history.allSatisfy { $0 < 0.001 })
    #expect(RecordingLevel().history.allSatisfy { $0 == 0 })
}

@Test func recordingTimerHandlesMinuteBoundariesAndInvalidTime() {
    #expect(RecordingClock.display(seconds: 0) == "00:00")
    #expect(RecordingClock.display(seconds: 59.99) == "00:59")
    #expect(RecordingClock.display(seconds: 60) == "01:00")
    #expect(RecordingClock.display(seconds: 180) == "03:00")
    #expect(RecordingClock.display(seconds: -1) == "00:00")
    #expect(RecordingClock.display(seconds: .nan) == "00:00")
    #expect(RecordingClock.display(seconds: .infinity) == "00:00")
}

@Test func editorsWithoutSelectionStillRequireTheSameTextField() {
    #expect(InsertionGuard.permits(originalPID: 1, currentPID: 1, sameElement: true,
        originalSelection: nil, currentSelection: nil, secure: false, editableTextField: true))
    #expect(!InsertionGuard.permits(originalPID: 1, currentPID: 1, sameElement: true,
        originalSelection: nil, currentSelection: nil, secure: false, editableTextField: false))
    #expect(!InsertionGuard.permits(originalPID: 1, currentPID: 1, sameElement: false,
        originalSelection: nil, currentSelection: nil, secure: false, editableTextField: true))
    #expect(!InsertionGuard.permits(originalPID: 1, currentPID: 2, sameElement: true,
        originalSelection: nil, currentSelection: nil, secure: false, editableTextField: true))
    #expect(!InsertionGuard.permits(originalPID: 1, currentPID: 1, sameElement: true,
        originalSelection: nil, currentSelection: nil, secure: true, editableTextField: true))
    #expect(!InsertionGuard.permits(originalPID: 1, currentPID: 1, sameElement: true,
        originalSelection: TextSelection(location: 2, length: 0), currentSelection: nil,
        secure: false, editableTextField: true))
}
