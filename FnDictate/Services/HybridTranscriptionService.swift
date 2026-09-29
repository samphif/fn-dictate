import AVFoundation
import FluidAudio
import Foundation

/// Result of finishing a hybrid session: transcript, 16 kHz mono PCM for diarization, and
/// Parakeet word timings (empty when Apple's transcript was kept).
struct HybridFinishResult: Sendable {
    var text: String
    var samples: [Float]
    var words: [TimedWord] = []

    static let empty = HybridFinishResult(text: "", samples: [])
}

/// Apple Speech for live partials/segments + Parakeet v2 batch on the buffered PCM at finish.
@available(macOS 26, *)
actor HybridTranscriptionService: TranscriptionEngine {
    private let apple = SpeechTranscriptionService()
    private let parakeet: ParakeetASRClient
    private let audioConverter = AudioConverter()

    private var pcmSamples: [Float] = []
    private var mode: ASREngineMode = .parakeet

    init(parakeet: ParakeetASRClient) {
        self.parakeet = parakeet
    }

    func setMode(_ mode: ASREngineMode) {
        self.mode = mode
    }

    func setPartialHandler(_ handler: (@Sendable (String) -> Void)?) async {
        await apple.setPartialHandler(handler)
    }

    func setFinalSegmentHandler(_ handler: (@Sendable (String, TimeInterval, [Float]?) -> Void)?) async {
        await apple.setFinalSegmentHandler(handler)
    }

    func prewarm() async throws {
        try await apple.prewarm()
        await parakeet.prewarm()
    }

    func startSession(contextualStrings: [String] = []) async throws {
        pcmSamples.removeAll(keepingCapacity: true)
        try await apple.startSession(contextualStrings: contextualStrings)
    }

    func append(_ sendable: SendablePCMBuffer) async {
        await apple.append(sendable)
        if let chunk = try? audioConverter.resampleBuffer(sendable.buffer), !chunk.isEmpty {
            pcmSamples.append(contentsOf: chunk)
        }
    }

    func finish(timeout: Duration = .seconds(3)) async -> String {
        let result = await finishWithSamples(timeout: timeout)
        return result.text
    }

    /// Finalize ASR and return the buffered 16 kHz mono PCM for post-call diarization.
    func finishWithSamples(timeout: Duration = .seconds(3)) async -> HybridFinishResult {
        let samples = pcmSamples
        pcmSamples.removeAll(keepingCapacity: true)

        let appleText = await apple.finish(timeout: timeout)

        guard Self.shouldRefineWithParakeet(mode: mode, sampleCount: samples.count),
              let refined = await parakeet.transcribe(samples, timeout: timeout)
        else {
            return HybridFinishResult(text: appleText, samples: samples)
        }
        return HybridFinishResult(text: refined.text, samples: samples, words: refined.words)
    }

    /// Too little audio for Parakeet — keep Apple.
    static func shouldRefineWithParakeet(mode: ASREngineMode, sampleCount: Int) -> Bool {
        mode == .parakeet && sampleCount >= 3_200 // ~0.2s at 16 kHz
    }

    func cancel() async {
        pcmSamples.removeAll(keepingCapacity: true)
        await apple.cancel()
    }
}
