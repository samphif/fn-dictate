import AVFoundation
import Foundation

/// Shared peak/RMS meter for mic and system-audio UI levels.
enum AudioLevel {
    /// Normalized 0...1 peak-ish level for waveform animation.
    static func normalized(from buffer: AVAudioPCMBuffer) -> Float? {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sumSquares: Float = 0
        var peak: Float = 0

        if let channels = buffer.floatChannelData {
            let channelCount = Int(buffer.format.channelCount)
            for frame in 0..<frameLength {
                var mixed: Float = 0
                for channel in 0..<channelCount {
                    mixed += channels[channel][frame]
                }
                mixed /= Float(max(channelCount, 1))
                sumSquares += mixed * mixed
                peak = max(peak, abs(mixed))
            }
        } else if let channels = buffer.int16ChannelData {
            let channelCount = Int(buffer.format.channelCount)
            for frame in 0..<frameLength {
                var mixed: Float = 0
                for channel in 0..<channelCount {
                    mixed += Float(channels[channel][frame]) / Float(Int16.max)
                }
                mixed /= Float(max(channelCount, 1))
                sumSquares += mixed * mixed
                peak = max(peak, abs(mixed))
            }
        } else {
            return nil
        }

        let rms = sqrt(sumSquares / Float(frameLength))
        // Blend RMS + peak, then expand quiet speech into a usable UI range.
        let combined = min(1, max(rms * 3.2, peak * 1.6))
        return min(1, pow(combined, 0.65))
    }
}
