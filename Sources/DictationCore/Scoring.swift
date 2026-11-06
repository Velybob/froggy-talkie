import Foundation

public enum Scoring {
    /// Shared normalization; deliberately does not turn numbers into spoken words.
    public static func words(_ text: String) -> [String] {
        let normalized = text.precomposedStringWithCompatibilityMapping.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .replacingOccurrences(of: "’", with: "'")
        let regex = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}]+(?:'[\\p{L}\\p{N}]+)*")
        let range = NSRange(normalized.startIndex..., in: normalized)
        return regex.matches(in: normalized, range: range).compactMap {
            Range($0.range, in: normalized).map { String(normalized[$0]) }
        }
    }

    public static func edits(reference: [String], hypothesis: [String]) -> Int {
        var previous = Array(0...hypothesis.count)
        for (i, referenceWord) in reference.enumerated() {
            var current = [i + 1]
            for (j, hypothesisWord) in hypothesis.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1,
                    previous[j] + (referenceWord == hypothesisWord ? 0 : 1)))
            }
            previous = current
        }
        return previous[hypothesis.count]
    }

    public static func percentile(_ values: [Double], fraction: Double) -> Double? {
        guard !values.isEmpty, (0...1).contains(fraction) else { return nil }
        let sorted = values.sorted()
        return sorted[max(0, Int(ceil(fraction * Double(sorted.count))) - 1)]
    }
}
