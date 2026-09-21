import AVFoundation
import CoreMedia
import Foundation
import Speech

struct SendablePCMBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
}

@available(macOS 26, *)
actor SpeechTranscriptionService {
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var preparedFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    private(set) var partialTranscript = ""
    private var finalizedSegments: [String] = []
    private var sessionStartedAt: ContinuousClock.Instant?

    private var onPartialUpdate: (@Sendable (String) -> Void)?
    /// Fired when a segment is finalized: text, seconds from session start, voice fingerprint.
    private var onFinalSegment: (@Sendable (String, TimeInterval, [Float]?) -> Void)?
    private var audioTimeline = VoiceAudioTimeline()

    func setPartialHandler(_ handler: (@Sendable (String) -> Void)?) {
        onPartialUpdate = handler
    }

    func setFinalSegmentHandler(_ handler: (@Sendable (String, TimeInterval, [Float]?) -> Void)?) {
        onFinalSegment = handler
    }

    func prewarm() async throws {
        let locale = await preferredLocale()
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        try await ensureAssets(for: module)

        let analyzer = SpeechAnalyzer(modules: [module])
        if let format = await module.availableCompatibleAudioFormats.first {
            try await analyzer.prepareToAnalyze(in: format)
            preparedFormat = format
        }
        self.transcriber = module
        self.analyzer = analyzer
    }

    func startSession(contextualStrings: [String] = []) async throws {
        partialTranscript = ""
        finalizedSegments = []
        sessionStartedAt = ContinuousClock.now
        audioTimeline.reset()

        let locale = await preferredLocale()
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        try await ensureAssets(for: module)

        let (stream, continuation) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        inputContinuation = continuation

        let context = AnalysisContext()
        let hints = Array(contextualStrings.prefix(100))
        if !hints.isEmpty {
            context.contextualStrings[.general] = hints
        }

        let analyzer = SpeechAnalyzer(modules: [module])
        if !hints.isEmpty {
            try await analyzer.setContext(context)
        }
        let format: AVAudioFormat?
        if let preparedFormat {
            format = preparedFormat
        } else {
            format = await module.availableCompatibleAudioFormats.first
        }
        if let format {
            try await analyzer.prepareToAnalyze(in: format)
            preparedFormat = format
        }

        self.transcriber = module
        self.analyzer = analyzer

        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in module.results {
                    await self.handleResult(result)
                }
            } catch {
                // Session ended or cancelled.
            }
        }

        Task {
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                // Analyzer finished.
            }
        }
    }

    func append(_ sendable: SendablePCMBuffer) {
        let buffer = sendable.buffer
        guard let continuation = inputContinuation else { return }

        if let preparedFormat, buffer.format != preparedFormat {
            guard let converted = convert(buffer, to: preparedFormat) else { return }
            audioTimeline.append(converted)
            continuation.yield(AnalyzerInput(buffer: converted))
            return
        }

        audioTimeline.append(buffer)
        continuation.yield(AnalyzerInput(buffer: buffer))
    }

    func finish() async -> String {
        inputContinuation?.finish()
        inputContinuation = nil

        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }

        // Allow a brief drain for final results.
        try? await Task.sleep(nanoseconds: 250_000_000)
        resultsTask?.cancel()
        resultsTask = nil

        let combined = (finalizedSegments + [partialTranscript])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        analyzer = nil
        transcriber = nil
        partialTranscript = ""
        finalizedSegments = []
        audioTimeline.reset()
        return combined
    }

    func cancel() async {
        inputContinuation?.finish()
        inputContinuation = nil
        if let analyzer {
            await analyzer.cancelAndFinishNow()
        }
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        partialTranscript = ""
        finalizedSegments = []
        audioTimeline.reset()
    }

    private func handleResult(_ result: SpeechTranscriber.Result) {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if result.isFinal {
            finalizedSegments.append(text)
            partialTranscript = ""
            let start = speechStart(of: result)
            onFinalSegment?(text, start, voiceprint(for: result, text: text))
        } else {
            partialTranscript = text
        }

        let combined = (finalizedSegments + [partialTranscript])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        onPartialUpdate?(combined)
    }

    private func speechStart(of result: SpeechTranscriber.Result) -> TimeInterval {
        let start = CMTimeGetSeconds(result.range.start)
        if start.isFinite, start >= 0 {
            return start
        }
        return elapsedSinceStart()
    }

    private func voiceprint(for result: SpeechTranscriber.Result, text: String) -> [Float]? {
        let start = CMTimeGetSeconds(result.range.start)
        let duration = CMTimeGetSeconds(result.range.duration)
        if start.isFinite, duration.isFinite, duration > 0 {
            let capped = min(duration, 4)
            let sliceStart = start + max(0, duration - capped)
            if let slice = audioTimeline.slice(start: sliceStart, duration: capped),
               let print = Voiceprint.make(samples: slice.samples, sampleRate: slice.sampleRate) {
                return print
            }
        }
        let words = max(1, text.split(whereSeparator: \.isWhitespace).count)
        let seconds = min(8, max(0.8, Double(words) * 0.45))
        guard let tail = audioTimeline.tail(seconds: seconds) else { return nil }
        return Voiceprint.make(samples: tail.samples, sampleRate: tail.sampleRate)
    }

    private func elapsedSinceStart() -> TimeInterval {
        guard let started = sessionStartedAt else { return 0 }
        let duration = ContinuousClock.now - started
        return Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
    }

    private func preferredLocale() async -> Locale {
        if let match = await SpeechTranscriber.supportedLocale(equivalentTo: .current) {
            return match
        }
        return Locale(identifier: "en-US")
    }

    private func ensureAssets(for module: SpeechTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            try await request.downloadAndInstall()
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if converter?.inputFormat != buffer.format || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil else { return nil }
        return output
    }
}

/// Recent mono audio for the analyzer's own clock, so a finalized phrase can be fingerprinted.
private struct VoiceAudioTimeline {
    private var samples: [Float] = []
    private var sampleRate: Double = 16_000
    /// Session time of `samples[0]`.
    private var origin: TimeInterval = 0

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        origin = 0
    }

    mutating func append(_ buffer: AVAudioPCMBuffer) {
        let rate = buffer.format.sampleRate
        let frames = Int(buffer.frameLength)
        guard frames > 0, rate > 0 else { return }
        if !samples.isEmpty, abs(sampleRate - rate) > 1 {
            reset()
        }
        sampleRate = rate
        let mono = Self.monoFloats(buffer)
        guard mono.count == frames else { return }
        samples.append(contentsOf: mono)
        let maxCount = Int(rate * 25)
        if samples.count > maxCount {
            let drop = samples.count - maxCount
            samples.removeFirst(drop)
            origin += Double(drop) / rate
        }
    }

    func slice(start: TimeInterval, duration: TimeInterval) -> (samples: [Float], sampleRate: Double)? {
        guard sampleRate > 0, duration > 0.2 else { return nil }
        let from = Int((start - origin) * sampleRate)
        let to = Int((start + duration - origin) * sampleRate)
        let lower = max(0, from)
        let upper = min(samples.count, to)
        let requested = Int(duration * sampleRate)
        guard upper - lower >= max(Int(sampleRate * 0.35), requested / 2) else { return nil }
        return (Array(samples[lower..<upper]), sampleRate)
    }

    func tail(seconds: TimeInterval) -> (samples: [Float], sampleRate: Double)? {
        guard sampleRate > 0 else { return nil }
        let count = min(samples.count, Int(sampleRate * seconds))
        guard count >= Int(sampleRate * 0.35) else { return nil }
        return (Array(samples.suffix(count)), sampleRate)
    }

    private static func monoFloats(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return [] }
        if let channels = buffer.floatChannelData {
            return Array(UnsafeBufferPointer(start: channels[0], count: frames))
        }
        if let channels = buffer.int16ChannelData {
            let channel = channels[0]
            return (0..<frames).map { Float(channel[$0]) / 32_768 }
        }
        return []
    }
}
