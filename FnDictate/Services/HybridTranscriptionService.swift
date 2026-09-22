import AVFoundation
import FluidAudio
import Foundation

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
        let samples = pcmSamples
        pcmSamples.removeAll(keepingCapacity: true)

        let appleText = await apple.finish(timeout: timeout)

        guard mode == .parakeet else {
            return appleText
        }

        // Too little audio for Parakeet — keep Apple.
        guard samples.count >= 3_200 else { // ~0.2s at 16 kHz
            return appleText
        }

        if let refined = await parakeet.transcribe(samples, timeout: timeout),
           !refined.isEmpty
        {
            return refined
        }
        return appleText
    }

    func cancel() async {
        pcmSamples.removeAll(keepingCapacity: true)
        await apple.cancel()
    }
}
