import AVFoundation
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

    private var onPartialUpdate: (@Sendable (String) -> Void)?

    func setPartialHandler(_ handler: (@Sendable (String) -> Void)?) {
        onPartialUpdate = handler
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

    func startSession() async throws {
        partialTranscript = ""
        finalizedSegments = []

        let locale = await preferredLocale()
        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        try await ensureAssets(for: module)

        let (stream, continuation) = AsyncStream.makeStream(
            of: AnalyzerInput.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        inputContinuation = continuation

        let analyzer = SpeechAnalyzer(modules: [module])
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
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }
                    await self.handleResult(text: text, isFinal: result.isFinal)
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
            continuation.yield(AnalyzerInput(buffer: converted))
            return
        }

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
    }

    private func handleResult(text: String, isFinal: Bool) {
        if isFinal {
            finalizedSegments.append(text)
            partialTranscript = ""
        } else {
            partialTranscript = text
        }

        let combined = (finalizedSegments + [partialTranscript])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        onPartialUpdate?(combined)
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
