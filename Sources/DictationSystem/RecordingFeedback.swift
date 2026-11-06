import Foundation

/// Display-only envelope. It never changes the recorded audio or drives ASR.
public struct RecordingLevel: Sendable {
    public private(set) var value = 0.0
    /// Oldest to newest, covering about 300 ms at the recorder's 30 Hz update rate.
    public private(set) var history = Array(repeating: 0.0, count: 9)
    public init() {}

    public mutating func update(decibels: Float, elapsed: TimeInterval) {
        let power = decibels.isFinite ? Double(decibels) : -160
        // Give speech dynamics most of the display's travel. Keep fixed quiet
        // and loud tails, so background noise stays small and loud input still
        // has headroom. This changes the display only, not microphone gain.
        let target: Double
        if power < -48 {
            target = max(0, (power + 60) / 12) * 0.05
        } else if power < -24 {
            let speech = (power + 48) / 24
            target = 0.05 + 0.8 * speech * speech * (3 - 2 * speech)
        } else {
            target = 0.85 + 0.15 * min(1, (power + 24) / 24)
        }
        let interval = elapsed.isFinite ? min(0.25, max(0, elapsed)) : 0
        guard interval > 0 else { return }
        let response = target > value ? 0.012 : 0.045
        value += (target - value) * (1 - exp(-interval / response))
        history.removeFirst()
        history.append(value)
    }
}

public enum RecordingClock {
    public static func display(seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? Int(min(86_399, max(0, seconds))) : 0
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
