import Foundation

/// Turns a meeting's live segments and finished channel audio into its saved transcript.
///
/// Live segments come from Apple Speech and carry turn timing; Parakeet's batch pass has
/// better words. Each segment's offset is relative to its own channel's audio, so words
/// and diarization are matched per channel and the two channels are never mixed.
enum MeetingFinalizer {
    @MainActor
    static func finalize(
        _ note: MeetingNote,
        mic: HybridFinishResult,
        system: HybridFinishResult,
        diarizer: MeetingDiarizer,
        applyDictionary: (String) -> String
    ) async -> MeetingNote {
        var note = note
        var segments = note.segments
        segments = replacingText(of: .microphone, in: segments, with: mic.words, transform: applyDictionary)
        segments = replacingText(of: .system, in: segments, with: system.words, transform: applyDictionary)
        segments = fillingSilentChannels(
            segments,
            micText: mic.text,
            systemText: system.text,
            remoteSpeaker: note.remoteOneOnOneName ?? SpeakerRole.others.label,
            transform: applyDictionary
        )

        let hints = SpeakerLabelNormalizer.IdentityHints(
            calendarAttendees: note.attendees,
            rosterNames: note.participantRoster,
            lockedRenames: note.lockedSpeakerRenames,
            remoteOneOnOneName: note.remoteOneOnOneName
        )
        if let plan = DiarizationPlan(segments: segments, micSamples: mic.samples, systemSamples: system.samples) {
            if plan.channel == .system, hints.remoteOneOnOneName?.isEmpty == false {
                // A calendar 1:1 already names every remote voice.
                segments = MeetingSpeakerAttribution.name(segments: segments, hints: hints)
            } else {
                let turns = await diarizer.diarize(plan.samples)
                segments = MeetingSpeakerAttribution.apply(
                    segments: segments,
                    turns: turns,
                    channel: plan.channel,
                    hints: hints
                )
            }
        }

        note.segments = segments
        return note
    }

    // MARK: - Words

    /// Words a line's start may precede and still belong to it; Apple's segment starts
    /// run slightly late.
    private static let wordLeadTolerance: TimeInterval = 0.25

    /// Replace `channel`'s live text with the Parakeet words spoken from each segment's
    /// start until the channel's next segment. Segments that get no words keep their text.
    static func replacingText(
        of channel: MeetingAudioChannel,
        in segments: [MeetingTranscriptSegment],
        with words: [TimedWord],
        transform: (String) -> String = { $0 }
    ) -> [MeetingTranscriptSegment] {
        let order = segments.indices
            .filter { segments[$0].channel == channel }
            .sorted { segments[$0].startOffset < segments[$1].startOffset }
        guard !order.isEmpty, !words.isEmpty else { return segments }

        var wordsBySegment: [Int: [String]] = [:]
        var cursor = 0
        for word in words.sorted(by: { $0.start < $1.start }) {
            while cursor + 1 < order.count,
                  segments[order[cursor + 1]].startOffset <= word.start + wordLeadTolerance
            {
                cursor += 1
            }
            wordsBySegment[order[cursor], default: []].append(word.text)
        }

        var result = segments
        for (index, texts) in wordsBySegment {
            result[index].text = transform(texts.joined(separator: " "))
        }
        return result
    }

    /// A meeting with no live lines, or no remote lines, still keeps its finished text.
    /// Leftover mic text is dropped once there are live lines; it's mostly speaker echo.
    static func fillingSilentChannels(
        _ segments: [MeetingTranscriptSegment],
        micText: String,
        systemText: String,
        remoteSpeaker: String,
        transform: (String) -> String = { $0 }
    ) -> [MeetingTranscriptSegment] {
        var result = segments
        if !micText.isEmpty, segments.isEmpty {
            result.append(MeetingTranscriptSegment(
                startOffset: 0,
                text: transform(micText),
                speaker: SpeakerRole.you.label,
                channel: .microphone
            ))
        }
        if !systemText.isEmpty, !segments.contains(where: { $0.role != .you }) {
            let lastOffset = segments.map(\.startOffset).max() ?? 0
            result.append(MeetingTranscriptSegment(
                startOffset: lastOffset + 0.1,
                text: transform(systemText),
                speaker: remoteSpeaker,
                channel: .system
            ))
        }
        return result
    }
}

/// Which channel's audio to diarize after a meeting.
struct DiarizationPlan: Equatable {
    var channel: MeetingAudioChannel
    var samples: [Float]

    /// A call with remote lines and real far-end audio diarizes system audio. Otherwise
    /// everyone was on the microphone (in person), so the mic is split instead.
    init?(segments: [MeetingTranscriptSegment], micSamples: [Float], systemSamples: [Float]) {
        let hasRemoteLines = segments.contains { $0.channel == .system && $0.role != .you }
        if hasRemoteLines, Self.hasMeaningfulSpeech(systemSamples, versusMic: micSamples) {
            self.init(channel: .system, samples: systemSamples)
        } else if !micSamples.isEmpty {
            self.init(channel: .microphone, samples: micSamples)
        } else {
            return nil
        }
    }

    init(channel: MeetingAudioChannel, samples: [Float]) {
        self.channel = channel
        self.samples = samples
    }

    /// Rough speech energy (mean abs), sampled across long buffers.
    static func meanAbsEnergy(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let step = max(1, samples.count / 50_000)
        let sampled = stride(from: 0, to: samples.count, by: step).map { abs(samples[$0]) }
        return sampled.reduce(0, +) / Float(sampled.count)
    }

    /// True when system audio looks like real far-end speech, not silence or noise.
    static func hasMeaningfulSpeech(_ samples: [Float], versusMic mic: [Float]) -> Bool {
        guard samples.count >= 16_000 else { return false } // ≥1s at 16 kHz
        let system = meanAbsEnergy(samples)
        guard system >= 0.008 else { return false }
        let micEnergy = meanAbsEnergy(mic)
        // A Zoom/Meet remote carries a real fraction of the mic's energy.
        return micEnergy <= 0.001 || system >= micEnergy * 0.12
    }
}
