import Foundation

enum MeetingTurnDecision: Sendable {
    case drop
    case append(MeetingTranscriptSegment)
    case update(segmentID: UUID, text: String, speaker: String, voiceID: UUID?)
}

/// Collapses mic/system-audio echoes and assigns each other person a stable voice.
///
/// Remote audio plays out of the speakers and the microphone hears it again, so the
/// same sentence shows up as both You and Others. When the text matches, the system-audio
/// line wins — unless that audio matches your saved voice, in which case it was you.
@MainActor
final class MeetingSpeakerTracker {
    let voices = VoiceProfileStore()

    private struct Turn {
        var segmentID: UUID
        var text: String
        var speaker: String
        var voiceID: UUID?
        var channel: MeetingAudioChannel
        var offset: TimeInterval
        var embedding: [Float]?
    }

    private struct PendingUserSample {
        var segmentID: UUID
        var embedding: [Float]
        var offset: TimeInterval
    }

    private var recent: [Turn] = []
    private var pendingUserSamples: [PendingUserSample] = []

    var lastRemoteLabel: String {
        recent.reversed().first(where: {
            $0.channel == .system && $0.speaker.caseInsensitiveCompare("You") != .orderedSame
        })?.speaker ?? "Others"
    }

    func begin() {
        recent.removeAll()
        pendingUserSamples.removeAll()
        voices.beginSession()
    }

    func end(keepingWeakVoices: Bool) {
        for sample in pendingUserSamples {
            voices.observeUser(sample.embedding)
        }
        pendingUserSamples.removeAll()
        recent.removeAll()
        voices.endSession(keepingWeakVoices: keepingWeakVoices)
    }

    func noteRename(id: UUID, to name: String) {
        for index in recent.indices where recent[index].voiceID == id {
            recent[index].speaker = name
        }
    }

    func resolve(
        text: String,
        offset: TimeInterval,
        channel: MeetingAudioChannel,
        embedding: [Float]?
    ) -> MeetingTurnDecision {
        flushPendingUserSamples(now: offset)
        if let index = duplicateIndex(of: text, at: offset) {
            return mergeDuplicate(
                at: index,
                text: text,
                channel: channel,
                embedding: embedding
            )
        }
        return appendNew(text: text, offset: offset, channel: channel, embedding: embedding)
    }

    private func appendNew(
        text: String,
        offset: TimeInterval,
        channel: MeetingAudioChannel,
        embedding: [Float]?
    ) -> MeetingTurnDecision {
        let label = label(for: channel, embedding: embedding, offset: offset)
        let segment = MeetingTranscriptSegment(
            startOffset: offset,
            text: text,
            speaker: label.name,
            voiceID: label.isUser ? nil : label.id
        )
        if channel == .microphone, let embedding, label.isUser {
            pendingUserSamples.append(
                PendingUserSample(segmentID: segment.id, embedding: embedding, offset: offset)
            )
        }
        remember(
            Turn(
                segmentID: segment.id,
                text: text,
                speaker: label.name,
                voiceID: segment.voiceID,
                channel: channel,
                offset: offset,
                embedding: embedding
            )
        )
        return .append(segment)
    }

    private func mergeDuplicate(
        at index: Int,
        text: String,
        channel: MeetingAudioChannel,
        embedding: [Float]?
    ) -> MeetingTurnDecision {
        if channel == .system, recent[index].channel == .microphone {
            if let embedding, voices.matchesUser(embedding) {
                return lengthen(index, to: text)
            }
            if let embedding, let remote = voices.matchCommittedRemote(embedding) {
                pendingUserSamples.removeAll { $0.segmentID == recent[index].segmentID }
                recent[index].speaker = remote.name
                recent[index].voiceID = remote.id
                recent[index].channel = .system
                recent[index].embedding = embedding
                recent[index].text = preferredText(existing: recent[index].text, incoming: text)
                let turn = recent[index]
                return .update(
                    segmentID: turn.segmentID,
                    text: turn.text,
                    speaker: turn.speaker,
                    voiceID: turn.voiceID
                )
            }
            // Don't invent a person from an echo of you. Keep the mic line.
            return lengthen(index, to: text)
        }

        // Mic heard a line the system-audio channel already has: speaker bleed.
        return lengthen(index, to: text)
    }

    private func label(
        for channel: MeetingAudioChannel,
        embedding: [Float]?,
        offset: TimeInterval
    ) -> VoiceLabel {
        switch channel {
        case .microphone:
            return voices.userLabel
        case .system:
            if voices.matchesUser(embedding) {
                return voices.userLabel
            }
            if embedding == nil, let sticky = stickyRemoteLabel(at: offset) {
                return sticky
            }
            return voices.labelRemote(embedding: embedding)
        }
    }

    private func stickyRemoteLabel(at offset: TimeInterval) -> VoiceLabel? {
        guard let last = recent.last(where: { $0.channel == .system && $0.voiceID != nil }) else {
            return nil
        }
        let gap = offset - last.offset
        guard gap >= 0, gap < 2.5 else { return nil }
        return VoiceLabel(name: last.speaker, id: last.voiceID, isUser: false)
    }

    private func lengthen(_ index: Int, to text: String) -> MeetingTurnDecision {
        let combined = preferredText(existing: recent[index].text, incoming: text)
        guard combined != recent[index].text else { return .drop }
        recent[index].text = combined
        let turn = recent[index]
        return .update(
            segmentID: turn.segmentID,
            text: turn.text,
            speaker: turn.speaker,
            voiceID: turn.voiceID
        )
    }

    private func preferredText(existing: String, incoming: String) -> String {
        TranscriptSimilarity.tokenCount(incoming) > TranscriptSimilarity.tokenCount(existing)
            ? incoming
            : existing
    }

    private func duplicateIndex(of text: String, at offset: TimeInterval) -> Int? {
        var best: Int?
        var bestScore = 0.0
        for (index, turn) in recent.enumerated() {
            let tokens = max(
                TranscriptSimilarity.tokenCount(text),
                TranscriptSimilarity.tokenCount(turn.text)
            )
            let limit: TimeInterval = tokens < 5 ? 6 : 12
            guard abs(turn.offset - offset) <= limit else { continue }
            guard TranscriptSimilarity.isNearDuplicate(text, turn.text) else { continue }
            let score = TranscriptSimilarity.similarity(text, turn.text)
            if score > bestScore {
                bestScore = score
                best = index
            }
        }
        return best
    }

    private func remember(_ turn: Turn) {
        recent.append(turn)
        if recent.count > 40 {
            recent.removeFirst(recent.count - 40)
        }
    }

    private func flushPendingUserSamples(now: TimeInterval) {
        let due = pendingUserSamples.filter { now - $0.offset >= 12 }
        guard !due.isEmpty else { return }
        for sample in due {
            voices.observeUser(sample.embedding)
        }
        pendingUserSamples.removeAll { now - $0.offset >= 12 }
    }
}
