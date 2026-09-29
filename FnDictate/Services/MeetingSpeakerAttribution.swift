import Foundation

/// Maps Sortformer speaker slots onto transcript segments, then names them from
/// calendar / roster / 1:1 context (Wispr-style: diarize first, name from outside).
enum MeetingSpeakerAttribution {
    struct Hints: Sendable {
        var calendarAttendees: [String] = []
        var rosterNames: [String] = []
        var remoteOneOnOneName: String? = nil
        var lockedRenames: [String: String] = [:]
    }

    /// Apply diarization turns to segments, then resolve display names.
    static func apply(
        segments: [MeetingTranscriptSegment],
        turns: [MeetingDiarizerTurn],
        hints: Hints,
        treatMicrophoneAsYou: Bool = true
    ) -> [MeetingTranscriptSegment] {
        guard !segments.isEmpty else { return segments }
        // Shared mic with only one Sortformer slot → nothing to split.
        if !treatMicrophoneAsYou, Set(turns.map(\.speakerIndex)).count < 2 {
            return segments
        }

        var labeled = assignSlots(
            segments: segments,
            turns: turns,
            treatMicrophoneAsYou: treatMicrophoneAsYou
        )
        labeled = nameSlots(segments: labeled, hints: hints)
        labeled = SpeakerLabelNormalizer.normalize(
            segments: labeled,
            hints: SpeakerLabelNormalizer.IdentityHints(
                calendarAttendees: hints.calendarAttendees,
                rosterNames: hints.rosterNames,
                lockedRenames: hints.lockedRenames,
                remoteOneOnOneName: hints.remoteOneOnOneName
            )
        )
        return labeled
    }

    // MARK: - Slot assignment

    private static func assignSlots(
        segments: [MeetingTranscriptSegment],
        turns: [MeetingDiarizerTurn],
        treatMicrophoneAsYou: Bool
    ) -> [MeetingTranscriptSegment] {
        guard !turns.isEmpty else { return segments }

        // Mic-channel "You" stays You when dual-channel capture already separated them.
        if treatMicrophoneAsYou {
            return segments.map { seg in
                if seg.speaker.caseInsensitiveCompare("You") == .orderedSame {
                    return seg
                }
                var copy = seg
                if let index = dominantSpeaker(at: seg.startOffset, turns: turns) {
                    copy.speaker = "Speaker \(index + 1)"
                    copy.voiceID = nil
                }
                return copy
            }
        }

        // Mic-only: longest talker → You; others → Speaker N.
        let youIndex = primarySpeakerIndex(in: turns)
        return segments.map { seg in
            var copy = seg
            guard let index = dominantSpeaker(at: seg.startOffset, turns: turns) else {
                return copy
            }
            if index == youIndex {
                copy.speaker = "You"
                copy.voiceID = nil
            } else {
                copy.speaker = "Speaker \(index + 1)"
                copy.voiceID = nil
            }
            return copy
        }
    }

    private static func dominantSpeaker(
        at offset: TimeInterval,
        turns: [MeetingDiarizerTurn]
    ) -> Int? {
        var best: MeetingDiarizerTurn?
        var bestOverlap: TimeInterval = 0
        // Prefer a turn that contains the utterance start; fall back to nearest.
        for turn in turns {
            let overlapStart = max(turn.startTime, offset)
            let overlapEnd = min(turn.endTime, offset + 2.5)
            let overlap = overlapEnd - overlapStart
            if overlap > bestOverlap {
                bestOverlap = overlap
                best = turn
            }
        }
        if let best, bestOverlap > 0 {
            return best.speakerIndex
        }
        // Nearest turn by midpoint distance.
        var nearest: MeetingDiarizerTurn?
        var nearestDistance = TimeInterval.greatestFiniteMagnitude
        for turn in turns {
            let mid = (turn.startTime + turn.endTime) / 2
            let distance = abs(mid - offset)
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = turn
            }
        }
        guard let nearest, nearestDistance < 8 else { return nil }
        return nearest.speakerIndex
    }

    private static func primarySpeakerIndex(in turns: [MeetingDiarizerTurn]) -> Int {
        var durations: [Int: TimeInterval] = [:]
        for turn in turns {
            durations[turn.speakerIndex, default: 0] += turn.endTime - turn.startTime
        }
        return durations.max(by: { $0.value < $1.value })?.key ?? 0
    }

    // MARK: - Naming

    private static func nameSlots(
        segments: [MeetingTranscriptSegment],
        hints: Hints
    ) -> [MeetingTranscriptSegment] {
        if let remote = hints.remoteOneOnOneName?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !remote.isEmpty
        {
            return segments.map { seg in
                guard seg.speaker.caseInsensitiveCompare("You") != .orderedSame else { return seg }
                var copy = seg
                copy.speaker = remote
                return copy
            }
        }

        let candidates = nameCandidates(hints: hints)
        guard !candidates.isEmpty else { return segments }

        // Stable order of first appearance of each Speaker N / Others.
        var slotOrder: [String] = []
        var seen = Set<String>()
        for seg in segments {
            let key = fold(seg.speaker)
            if key == "you" { continue }
            if seen.insert(key).inserted {
                slotOrder.append(seg.speaker)
            }
        }

        var mapping: [String: String] = [:]
        var candidateIndex = 0
        for slot in slotOrder {
            if candidateIndex < candidates.count {
                mapping[fold(slot)] = candidates[candidateIndex]
                candidateIndex += 1
            }
        }

        return segments.map { seg in
            let key = fold(seg.speaker)
            if key == "you" { return seg }
            guard let name = mapping[key] else { return seg }
            var copy = seg
            copy.speaker = name
            return copy
        }
    }

    private static func nameCandidates(hints: Hints) -> [String] {
        var list: [String] = []
        var seen = Set<String>()
        for name in hints.calendarAttendees + hints.rosterNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if key == "you" || key == "others" { continue }
            if SpeakerLabelNormalizer.isAnonymousVoiceLabel(trimmed) { continue }
            if seen.insert(key).inserted {
                list.append(trimmed)
            }
        }
        return list
    }

    private static func fold(_ speaker: String) -> String {
        speaker.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
