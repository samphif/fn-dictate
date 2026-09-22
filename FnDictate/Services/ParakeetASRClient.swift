import AVFoundation
import FluidAudio
import Foundation

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
    func transcribe(_ samples: [Float], timeout: Duration) async -> String? {
        if !isReady {
            await prewarm()
        }
        guard isReady, let manager, !samples.isEmpty else { return nil }

        return await withTaskGroup(of: String?.self) { group in
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
                    return text.isEmpty ? nil : text
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            // First completed child wins: success text, or nil (timeout / failure).
            var winner: String?
            for await value in group {
                group.cancelAll()
                winner = value
                break
            }
            return winner
        }
    }
}
