import FluidAudio
import Foundation

/// One Sortformer speaker activity interval (anonymous slot index).
struct MeetingDiarizerTurn: Sendable, Equatable {
    var speakerIndex: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
}

/// Which audio to diarize after a meeting, and whether the mic channel is only the local user.
struct MeetingDiarizationInput: Sendable, Equatable {
    var samples: [Float]
    /// In person: everyone is on the mic, so mic lines can be relabeled away from You.
    var isSharedMic: Bool
}

/// Post-meeting acoustic diarization via FluidAudio Offline Sortformer (Core ML).
/// Live path stays You/Others; this runs after stop on buffered 16 kHz PCM.
actor MeetingDiarizer {
    private var diarizer: OfflineSortformerDiarizer?
    private var loadingTask: Task<Void, Never>?
    private(set) var isReady = false
    private(set) var lastError: String?

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
                lastError = nil
            } catch {
                isReady = false
                lastError = error.localizedDescription
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
            lastError = error.localizedDescription
            return []
        }
    }

    /// Mix two 16 kHz mono streams (pad the shorter) for a single conversation track.
    static func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        let count = max(a.count, b.count)
        guard count > 0 else { return [] }
        var out = [Float](repeating: 0, count: count)
        for index in 0..<count {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            out[index] = (left + right) * 0.5
        }
        return out
    }

    /// Rough speech energy (mean abs) — used to tell empty system-audio from real remote speech.
    static func meanAbsEnergy(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        // Stride for long buffers.
        let step = max(1, samples.count / 50_000)
        var count = 0
        var index = 0
        while index < samples.count {
            sum += abs(samples[index])
            count += 1
            index += step
        }
        return count > 0 ? sum / Float(count) : 0
    }

    /// True when the system-audio buffer looks like real far-end speech, not silence/noise.
    static func hasMeaningfulSpeech(_ samples: [Float], versusMic mic: [Float]) -> Bool {
        guard samples.count >= 16_000 else { return false } // ≥1s
        let system = meanAbsEnergy(samples)
        guard system >= 0.008 else { return false }
        let micEnergy = meanAbsEnergy(mic)
        // System should carry a non-trivial fraction of mic energy (Zoom/Meet remote).
        if micEnergy > 0.001 {
            return system >= micEnergy * 0.12
        }
        return true
    }

    /// In-person / shared mic: both people hit the same microphone, so live labels are
    /// all You. Dual-channel only helps when system audio actually has remote speech.
    static func input(
        youSamples: [Float],
        othersSamples: [Float],
        liveLabelsAllYou: Bool
    ) -> MeetingDiarizationInput? {
        let remoteSpeech = hasMeaningfulSpeech(othersSamples, versusMic: youSamples)
        if liveLabelsAllYou || !remoteSpeech {
            guard !youSamples.isEmpty else { return nil }
            // Prefer mic; mix in system only when it carries speech (speaker playback).
            let samples = remoteSpeech ? mix(youSamples, othersSamples) : youSamples
            return MeetingDiarizationInput(samples: samples, isSharedMic: true)
        }
        let samples = othersSamples.count >= youSamples.count
            ? othersSamples
            : mix(youSamples, othersSamples)
        return MeetingDiarizationInput(samples: samples, isSharedMic: false)
    }
}
