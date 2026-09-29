import Foundation

/// Which side of a meeting is talking right now, for the live You / Others indicator.
///
/// Remote audio played through speakers makes both channels hot at once, so a lit side
/// only flips when the other side is louder by a clear margin.
struct MeetingChannelActivity {
    enum Channel: Equatable, Sendable {
        case you
        case others
    }

    static let speechLevel: Float = 0.12
    static let hold: TimeInterval = 1.2
    static let louderMargin: Float = 0.08

    private(set) var active: Channel?
    private var lastSpeech: [Channel: Date] = [:]

    /// A transcribed line is the strongest signal of who's talking.
    mutating func heardLine(from channel: Channel, at now: Date) {
        lastSpeech[channel] = now
        active = channel
    }

    mutating func levelsChanged(you: Float, others: Float, at now: Date) {
        if you >= Self.speechLevel { lastSpeech[.you] = now }
        if others >= Self.speechLevel { lastSpeech[.others] = now }

        switch (isRecent(.you, now), isRecent(.others, now)) {
        case (true, true):
            if you >= others + Self.louderMargin {
                active = .you
            } else if others >= you + Self.louderMargin {
                active = .others
            } else {
                // Too close to call (usually echo): keep the lit side; system audio wins ties.
                active = active ?? .others
            }
        case (true, false):
            active = .you
        case (false, true):
            active = .others
        case (false, false):
            if you < Self.speechLevel, others < Self.speechLevel {
                active = nil
            }
        }
    }

    mutating func reset() {
        active = nil
        lastSpeech = [:]
    }

    private func isRecent(_ channel: Channel, _ now: Date) -> Bool {
        lastSpeech[channel].map { now.timeIntervalSince($0) < Self.hold } ?? false
    }
}
