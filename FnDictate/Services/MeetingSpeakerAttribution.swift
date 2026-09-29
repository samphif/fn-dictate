import Foundation

/// Maps Sortformer speaker slots onto one channel's transcript segments, then names them
/// from calendar / roster / 1:1 context (Wispr-style: diarize first, name from outside).
enum MeetingSpeakerAttribution {
    /// How much audio after a line starts is matched against Sortformer turns.
    private static let utteranceWindow: TimeInterval = 2.5
    /// Lines further than this from every turn keep their live label.
    private static let nearestTurnLimit: TimeInterval = 8

    /// Relabel `channel`'s segments by diarization slot, then resolve display names.
    /// On the microphone (in person) the longest talker is You; on system audio every
    /// remote line gets a slot while lines already matched to your voice stay You.
    static func apply(
        segments: [MeetingTranscriptSegment],
        turns: [MeetingDiarizerTurn],
        channel: MeetingAudioChannel,
        hints: SpeakerLabelNormalizer.IdentityHints
    ) -> [MeetingTranscriptSegment] {
        guard let labelForSlot = slotLabeler(turns: turns, channel: channel) else { return segments }
        let labeled = segments.map { seg in
            guard seg.channel == channel,
                  channel == .microphone || seg.role != .you,
                  let slot = dominantSlot(at: seg.startOffset, turns: turns)
            else { return seg }
            var copy = seg
            copy.speaker = labelForSlot(slot)
            copy.voiceID = nil
            return copy
        }
        return name(segments: labeled, hints: hints)
    }

    /// Replace remote labels with calendar / roster names, then normalize spellings.
    static func name(
        segments: [MeetingTranscriptSegment],
        hints: SpeakerLabelNormalizer.IdentityHints
    ) -> [MeetingTranscriptSegment] {
        SpeakerLabelNormalizer.normalize(segments: nameRemoteLabels(segments, hints: hints), hints: hints)
    }

    // MARK: - Slot assignment

    private static func slotLabeler(
        turns: [MeetingDiarizerTurn],
        channel: MeetingAudioChannel
    ) -> ((Int) -> String)? {
        guard !turns.isEmpty else { return nil }
        switch channel {
        case .system:
            return { SpeakerRole.slot($0 + 1).label }
        case .microphone:
            // One voice on a shared mic means there's nothing to split.
            guard Set(turns.map(\.speakerIndex)).count >= 2 else { return nil }
            let youSlot = primarySlot(in: turns)
            return { $0 == youSlot ? SpeakerRole.you.label : SpeakerRole.slot($0 + 1).label }
        }
    }

    /// The turn overlapping the start of the line most, else the nearest turn.
    private static func dominantSlot(at offset: TimeInterval, turns: [MeetingDiarizerTurn]) -> Int? {
        func overlap(_ turn: MeetingDiarizerTurn) -> TimeInterval {
            min(turn.endTime, offset + utteranceWindow) - max(turn.startTime, offset)
        }
        if let best = turns.max(by: { overlap($0) < overlap($1) }), overlap(best) > 0 {
            return best.speakerIndex
        }
        func distance(_ turn: MeetingDiarizerTurn) -> TimeInterval {
            abs((turn.startTime + turn.endTime) / 2 - offset)
        }
        guard let nearest = turns.min(by: { distance($0) < distance($1) }),
              distance(nearest) < nearestTurnLimit
        else { return nil }
        return nearest.speakerIndex
    }

    private static func primarySlot(in turns: [MeetingDiarizerTurn]) -> Int {
        var durations: [Int: TimeInterval] = [:]
        for turn in turns {
            durations[turn.speakerIndex, default: 0] += turn.endTime - turn.startTime
        }
        return durations.max(by: { $0.value < $1.value })?.key ?? 0
    }

    // MARK: - Naming

    /// A calendar 1:1 names every remote line; otherwise known names are handed out to
    /// remote labels in order of first appearance.
    private static func nameRemoteLabels(
        _ segments: [MeetingTranscriptSegment],
        hints: SpeakerLabelNormalizer.IdentityHints
    ) -> [MeetingTranscriptSegment] {
        let mapping: (MeetingTranscriptSegment) -> String?
        if let remote = hints.remoteOneOnOneName?.trimmingCharacters(in: .whitespacesAndNewlines), !remote.isEmpty {
            mapping = { _ in remote }
        } else {
            var remaining = knownNames(hints: hints)[...]
            var assigned: [String: String] = [:]
            for seg in segments where seg.role != .you {
                let key = seg.speaker.lowercased()
                if assigned[key] == nil, let name = remaining.popFirst() {
                    assigned[key] = name
                }
            }
            mapping = { assigned[$0.speaker.lowercased()] }
        }

        return segments.map { seg in
            guard seg.role != .you, let name = mapping(seg) else { return seg }
            var copy = seg
            copy.speaker = name
            return copy
        }
    }

    private static func knownNames(hints: SpeakerLabelNormalizer.IdentityHints) -> [String] {
        var seen = Set<String>()
        return (hints.calendarAttendees + hints.rosterNames).compactMap { name in
            guard case .named(let trimmed) = SpeakerRole(name),
                  !trimmed.isEmpty,
                  seen.insert(trimmed.lowercased()).inserted
            else { return nil }
            return trimmed
        }
    }
}
