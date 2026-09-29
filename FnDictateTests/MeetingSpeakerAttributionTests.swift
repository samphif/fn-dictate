import Foundation
import Testing
@testable import FnDictate

struct MeetingSpeakerAttributionTests {
    /// In-person meeting: every live line was You because both voices hit the mic.
    private let sharedMicSegments = [
        Fixtures.segment("You", at: 0),
        Fixtures.segment("You", at: 5),
        Fixtures.segment("You", at: 10),
        Fixtures.segment("You", at: 15),
    ]

    /// Slot 0 talks 8s total, slot 1 talks 5s total.
    private let twoSpeakerTurns = [
        Fixtures.turn(0, 0, 4),
        Fixtures.turn(1, 5, 9),
        Fixtures.turn(0, 10, 14),
        Fixtures.turn(1, 15, 16),
    ]

    private func sharedMic(
        _ segments: [MeetingTranscriptSegment],
        turns: [MeetingDiarizerTurn],
        hints: SpeakerLabelNormalizer.IdentityHints = .init()
    ) -> [String] {
        MeetingSpeakerAttribution.apply(
            segments: segments,
            turns: turns,
            channel: .microphone,
            hints: hints
        ).map(\.speaker)
    }

    @Test func sharedMicSplitsTheLongestTalkerAsYou() {
        #expect(sharedMic(sharedMicSegments, turns: twoSpeakerTurns) == ["You", "Speaker 2", "You", "Speaker 2"])
    }

    @Test func sharedMicYouFollowsTalkTimeNotSlotNumber() {
        let turns = [
            Fixtures.turn(0, 0, 1),
            Fixtures.turn(1, 5, 14),
        ]
        let segments = [Fixtures.segment("You", at: 0), Fixtures.segment("You", at: 6)]
        #expect(sharedMic(segments, turns: turns) == ["Speaker 1", "You"])
    }

    @Test func sharedMicWithOneSlotLeavesSegmentsUntouched() {
        let turns = [Fixtures.turn(0, 0, 4), Fixtures.turn(0, 5, 20)]
        let result = MeetingSpeakerAttribution.apply(
            segments: sharedMicSegments,
            turns: turns,
            channel: .microphone,
            hints: .init(calendarAttendees: ["Jodi"])
        )
        #expect(result == sharedMicSegments)
    }

    @Test func sharedMicOneOnOneNamesTheOtherVoice() {
        let hints = SpeakerLabelNormalizer.IdentityHints(remoteOneOnOneName: "Jodi")
        #expect(sharedMic(sharedMicSegments, turns: twoSpeakerTurns, hints: hints) == ["You", "Jodi", "You", "Jodi"])
    }

    @Test func attendeesNameSlotsInOrderOfFirstAppearance() {
        let segments = [
            Fixtures.segment("You", at: 0),
            Fixtures.segment("You", at: 10),
            Fixtures.segment("You", at: 20),
            Fixtures.segment("You", at: 30),
        ]
        let turns = [
            Fixtures.turn(0, 0, 9),
            Fixtures.turn(2, 10, 12),
            Fixtures.turn(1, 20, 22),
            Fixtures.turn(2, 30, 31),
        ]
        let hints = SpeakerLabelNormalizer.IdentityHints(
            calendarAttendees: ["Jodi", " ", "Voice 3"],
            rosterNames: ["jodi", "Virginia"]
        )
        #expect(sharedMic(segments, turns: turns, hints: hints) == ["You", "Jodi", "Virginia", "Jodi"])
    }

    @Test func extraSlotsBeyondKnownNamesStayAnonymous() {
        let segments = [
            Fixtures.segment("You", at: 0),
            Fixtures.segment("You", at: 10),
            Fixtures.segment("You", at: 20),
        ]
        let turns = [
            Fixtures.turn(0, 0, 9),
            Fixtures.turn(1, 10, 12),
            Fixtures.turn(2, 20, 22),
        ]
        let hints = SpeakerLabelNormalizer.IdentityHints(calendarAttendees: ["Jodi"])
        #expect(sharedMic(segments, turns: turns, hints: hints) == ["You", "Jodi", "Speaker 3"])
    }

    @Test func lockedRenamesWinOverAutomaticNames() {
        let hints = SpeakerLabelNormalizer.IdentityHints(lockedRenames: ["Speaker 2": "Virginia"])
        #expect(sharedMic(sharedMicSegments, turns: twoSpeakerTurns, hints: hints) == ["You", "Virginia", "You", "Virginia"])
    }

    @Test func segmentsFarFromAnyTurnKeepTheirLabel() {
        let segments = sharedMicSegments + [Fixtures.segment("You", at: 40)]
        #expect(sharedMic(segments, turns: twoSpeakerTurns).last == "You")
    }

    @Test func segmentBetweenTurnsUsesNearestTurn() {
        let segments = [Fixtures.segment("You", at: 0), Fixtures.segment("You", at: 20)]
        let turns = [Fixtures.turn(0, 0, 10), Fixtures.turn(1, 14, 16)]
        #expect(sharedMic(segments, turns: turns) == ["You", "Speaker 2"])
    }

    @Test func dualChannelKeepsMicLinesAsYouAndSplitsRemote() {
        let segments = [
            Fixtures.segment("You", at: 0),
            MeetingTranscriptSegment(startOffset: 5, text: "hi", speaker: "Others", voiceID: UUID(), channel: .system),
            Fixtures.segment("Others", at: 12),
        ]
        let turns = [
            Fixtures.turn(0, 0, 3),
            Fixtures.turn(0, 5, 8),
            Fixtures.turn(1, 12, 14),
        ]
        let result = MeetingSpeakerAttribution.apply(
            segments: segments,
            turns: turns,
            channel: .system,
            hints: .init()
        )
        #expect(result.map(\.speaker) == ["You", "Speaker 1", "Speaker 2"])
        #expect(result.allSatisfy { $0.voiceID == nil })
        #expect(result.map(\.id) == segments.map(\.id))
    }

    @Test func dualChannelOneOnOneNamesAllRemoteLines() {
        let segments = [
            Fixtures.segment("You", at: 0),
            Fixtures.segment("Others", at: 5),
            Fixtures.segment("Others", at: 12),
        ]
        let turns = [Fixtures.turn(0, 5, 8), Fixtures.turn(1, 12, 14)]
        let result = MeetingSpeakerAttribution.apply(
            segments: segments,
            turns: turns,
            channel: .system,
            hints: .init(remoteOneOnOneName: "Jodi")
        )
        #expect(result.map(\.speaker) == ["You", "Jodi", "Jodi"])
    }

    @Test func dualChannelKeepsSystemLinesMatchedToYourVoice() {
        let segments = [
            Fixtures.segment("You", at: 0, channel: .system),
            Fixtures.segment("Others", at: 5),
        ]
        let turns = [Fixtures.turn(0, 0, 3), Fixtures.turn(1, 5, 8)]
        let result = MeetingSpeakerAttribution.apply(segments: segments, turns: turns, channel: .system, hints: .init())
        #expect(result.map(\.speaker) == ["You", "Speaker 2"])
    }

    @Test func onlyTheDiarizedChannelIsRelabeled() {
        let segments = sharedMicSegments + [Fixtures.segment("You", at: 5, channel: .system)]
        #expect(sharedMic(segments, turns: twoSpeakerTurns) == ["You", "Speaker 2", "You", "Speaker 2", "You"])
    }

    @Test func nameWithoutDiarizationAppliesOneOnOneName() {
        let segments = [Fixtures.segment("You", at: 0), Fixtures.segment("Others", at: 5)]
        let result = MeetingSpeakerAttribution.name(segments: segments, hints: .init(remoteOneOnOneName: "Jodi"))
        #expect(result.map(\.speaker) == ["You", "Jodi"])
    }

    @Test func emptySegmentsReturnEmpty() {
        #expect(MeetingSpeakerAttribution.apply(segments: [], turns: twoSpeakerTurns, channel: .microphone, hints: .init()).isEmpty)
    }
}
