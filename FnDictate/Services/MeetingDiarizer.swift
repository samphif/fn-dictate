import FluidAudio
import Foundation
import os

/// One Sortformer speaker activity interval (anonymous slot index).
struct MeetingDiarizerTurn: Sendable, Equatable {
    var speakerIndex: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
}

/// Post-meeting acoustic diarization via FluidAudio Offline Sortformer (Core ML).
/// Live path stays You/Others; this runs after stop on buffered 16 kHz PCM.
actor MeetingDiarizer {
    private static let log = Logger(subsystem: "com.samuelphifer.FnDictate", category: "diarization")

    private var diarizer: OfflineSortformerDiarizer?
    private var loadingTask: Task<Void, Never>?
    private(set) var isReady = false

    func prewarm() async {
        if isReady { return }
        if let loadingTask {
            await loadingTask.value
            return
        }
        let task = Task {
            do {
                let engine = OfflineSortformerDiarizer()
                try await engine.initializeFromHuggingFace(computeUnits: .all)
                diarizer = engine
                isReady = true
            } catch {
                Self.log.error("Sortformer failed to load: \(error.localizedDescription, privacy: .public)")
                isReady = false
                diarizer = nil
            }
        }
        loadingTask = task
        await task.value
        loadingTask = nil
    }

    /// Diarize 16 kHz mono float samples. Returns empty on short audio / failure.
    func diarize(_ samples: [Float], sampleRate: Double = 16_000) async -> [MeetingDiarizerTurn] {
        // ~2s minimum — Sortformer needs real speech to form slots.
        guard samples.count >= Int(sampleRate * 2) else { return [] }
        if !isReady {
            await prewarm()
        }
        guard isReady, let diarizer else { return [] }

        do {
            let timeline = try diarizer.processComplete(samples, sourceSampleRate: sampleRate)
            return timeline.speakers.values
                .flatMap(\.finalizedSegments)
                .filter { $0.endTime > $0.startTime }
                .map {
                    MeetingDiarizerTurn(
                        speakerIndex: $0.speakerIndex,
                        startTime: TimeInterval($0.startTime),
                        endTime: TimeInterval($0.endTime)
                    )
                }
                .sorted { $0.startTime < $1.startTime }
        } catch {
            Self.log.error("Sortformer failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
