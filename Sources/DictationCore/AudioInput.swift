import FluidAudio
import Foundation

public enum AudioInput {
    public static func samples16kMono(file: URL) throws -> [Float] {
        try AudioConverter().resampleAudioFile(file)
    }
}
