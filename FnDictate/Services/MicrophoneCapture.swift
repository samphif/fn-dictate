import AVFoundation
import Foundation

/// Captures microphone PCM buffers and yields them as AnalyzerInput-compatible buffers.
final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var isRunning = false

    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

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
        }

        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    enum CaptureError: Error {
        case invalidInputFormat
    }
}
