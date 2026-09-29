import AVFoundation
import FluidAudio
import Foundation

struct TimedWord: Sendable, Equatable {
    var text: String
    /// Seconds from the start of the transcribed audio.
    var start: TimeInterval
}

struct ParakeetTranscript: Sendable {
    var text: String
    var words: [TimedWord]
}

/// Shared Parakeet TDT v2 (English) batch ASR — one model load for mic + system-audio channels.
actor ParakeetASRClient {
    private var manager: AsrManager?
    private(set) var isReady = false
    private(set) var lastError: String?
    private var loadingTask: Task<Void, Never>?

    func prewarm() async {
        if isReady { return }
        if let loadingTask {
            await loadingTask.value
            return
        }
        let task = Task {
            do {
                let models = try await AsrModels.downloadAndLoad(version: .v2)
                let asr = AsrManager(config: .default)
                try await asr.loadModels(models)
                manager = asr
                isReady = true
                lastError = nil
            } catch {
                isReady = false
                lastError = error.localizedDescription
            }
        }
        loadingTask = task
        await task.value
        loadingTask = nil
    }

    /// Transcribe 16 kHz mono float samples. Returns nil on failure / empty / timeout.
    func transcribe(_ samples: [Float], timeout: Duration) async -> ParakeetTranscript? {
        if !isReady {
            await prewarm()
        }
        guard isReady, let manager, !samples.isEmpty else { return nil }

        return await withTaskGroup(of: ParakeetTranscript?.self) { group in
            group.addTask { [manager] in
                do {
                    var decoderState = TdtDecoderState.make(
                        decoderLayers: await manager.decoderLayerCount
                    )
                    let result = try await manager.transcribe(
                        samples,
                        decoderState: &decoderState
                    )
                    let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }
                    return ParakeetTranscript(text: text, words: Self.words(from: result.tokenTimings ?? []))
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            // First completed child wins: success text, or nil (timeout / failure).
            var winner: ParakeetTranscript?
            for await value in group {
                group.cancelAll()
                winner = value
                break
            }
            return winner
        }
    }

    /// Subword tokens that begin with a space (or SentencePiece's ▁) start a new word.
    static func words(from tokens: [TokenTiming]) -> [TimedWord] {
        var words: [TimedWord] = []
        var startsWord = true
        for token in tokens {
            if token.token.hasPrefix(" ") || token.token.hasPrefix("▁") {
                startsWord = true
            }
            let piece = token.token.trimmingCharacters(in: CharacterSet(charactersIn: " ▁"))
            guard !piece.isEmpty else { continue }
            if startsWord {
                words.append(TimedWord(text: piece, start: token.startTime))
            } else {
                words[words.count - 1].text += piece
            }
            startsWord = false
        }
        return words
    }
}
