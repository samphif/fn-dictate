import Foundation

/// Speech engine preference for final transcripts.
/// Live partials always use Apple Speech when available; Parakeet runs on the buffered PCM at finish.
enum ASREngineMode: String, CaseIterable, Sendable, Identifiable {
    case parakeet
    case apple

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .parakeet: return "Parakeet"
        case .apple: return "Apple"
        }
    }

    var help: String {
        switch self {
        case .parakeet:
            return "More accurate English words (names, accents). Slightly longer wait after you release Fn."
        case .apple:
            return "System SpeechAnalyzer only — fastest, current behavior."
        }
    }
}

/// Shared surface for dictation and meeting transcription actors.
@available(macOS 26, *)
protocol TranscriptionEngine: Sendable {
    func setPartialHandler(_ handler: (@Sendable (String) -> Void)?) async
    func setFinalSegmentHandler(_ handler: (@Sendable (String, TimeInterval, [Float]?) -> Void)?) async
    func prewarm() async throws
    func startSession(contextualStrings: [String]) async throws
    func append(_ sendable: SendablePCMBuffer) async
    /// Finalize the session. `timeout` caps how long Parakeet may run before falling back to Apple.
    func finish(timeout: Duration) async -> String
    func cancel() async
}
