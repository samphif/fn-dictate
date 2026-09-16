import AVFoundation
import Foundation

/// Captures microphone PCM buffers and yields them as AnalyzerInput-compatible buffers.
final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var isRunning = false

    var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    /// Normalized 0...1 peak level for UI waveform animation.
    var onLevel: ((Float) -> Void)?

    var inputFormat: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func start() throws {
        guard !isRunning else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.invalidInputFormat
        }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.onBuffer?(buffer)
            if let level = Self.normalizedLevel(from: buffer) {
                self?.onLevel?(level)
            }
        }

        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        onLevel?(0)
    }

    private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Float? {
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

    enum CaptureError: Error {
        case invalidInputFormat
    }
}
