import Foundation

/// What a stored speaker label means. Segments persist the label as a string; parse it
/// here instead of comparing against "You" / "Others" / "Speaker N" at each call site.
enum SpeakerRole: Equatable, Sendable {
    case you
    case others
    /// "Speaker N" from post-call diarization, awaiting a real name.
    case slot(Int)
    /// "Voice N" from the retired live voice clustering.
    case legacyVoice(Int)
    case named(String)

    init(_ label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "you":
            self = .you
        case "others", "other", "them":
            self = .others
        default:
            self = Self.anonymous(trimmed) ?? .named(trimmed)
        }
    }

    var label: String {
        switch self {
        case .you: "You"
        case .others: "Others"
        case .slot(let number): "Speaker \(number)"
        case .legacyVoice(let number): "Voice \(number)"
        case .named(let name): name
        }
    }

    var isAnonymous: Bool {
        switch self {
        case .slot, .legacyVoice: true
        case .you, .others, .named: false
        }
    }

    /// Matches "Speaker 2", "voice-3", "SPEAKER_4".
    private static func anonymous(_ label: String) -> SpeakerRole? {
        guard let match = label.wholeMatch(of: /(?i)(voice|speaker)\s*[-_]?\s*(\d+)/),
              let number = Int(match.2)
        else { return nil }
        return match.1.lowercased() == "speaker" ? .slot(number) : .legacyVoice(number)
    }
}
