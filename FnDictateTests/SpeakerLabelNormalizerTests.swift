import Foundation
import Testing
@testable import FnDictate

struct SpeakerLabelNormalizerTests {
    private func speakers(
        _ labels: [String],
        hints: SpeakerLabelNormalizer.IdentityHints = .init()
    ) -> [String] {
        let segments = labels.enumerated().map { index, label in
            Fixtures.segment(label, at: TimeInterval(index))
        }
        return SpeakerLabelNormalizer.normalize(segments: segments, hints: hints).map(\.speaker)
    }

    @Test func canonicalizesYouAndOthersSynonyms() {
        #expect(speakers(["you", "YOU", "them", "Other", "others"]) == ["You", "You", "Others", "Others", "Others"])
    }

    @Test func mergesCasingDuplicatesPreferringTitleCase() {
        #expect(speakers(["jodi", "Jodi", "jodi"]) == ["Jodi", "Jodi", "Jodi"])
    }

    @Test func mergesCasingDuplicatesTowardCalendarSpelling() {
        let hints = SpeakerLabelNormalizer.IdentityHints(calendarAttendees: ["McKenzie"])
        #expect(speakers(["mckenzie", "MCKENZIE"], hints: hints) == ["McKenzie", "McKenzie"])
    }

    @Test func collapsesLegacyVoiceLabelsButKeepsSortformerSpeakers() {
        #expect(
            speakers(["You", "Voice 1", "Voice 2", "Speaker 2", "Jodi"])
                == ["You", "Others", "Others", "Speaker 2", "Jodi"]
        )
    }

    @Test func oneOnOneNamesEveryAnonymousRemote() {
        let hints = SpeakerLabelNormalizer.IdentityHints(
            calendarAttendees: ["Jodi"],
            remoteOneOnOneName: "Jodi"
        )
        #expect(speakers(["You", "Voice 1", "Speaker 2"], hints: hints) == ["You", "Jodi", "Jodi"])
    }

    @Test func oneOnOneShortcutIsSkippedWhenMoreNamesAreKnown() {
        let hints = SpeakerLabelNormalizer.IdentityHints(
            calendarAttendees: ["Virginia"],
            remoteOneOnOneName: "Jodi"
        )
        #expect(speakers(["Speaker 2", "Voice 1"], hints: hints) == ["Speaker 2", "Others"])
    }

    @Test func lockedRenamesApplyLastAndIgnoreCase() {
        let hints = SpeakerLabelNormalizer.IdentityHints(
            lockedRenames: ["speaker 2": "Virginia", "Others": "Jodi", " ": "Ignored"],
            remoteOneOnOneName: nil
        )
        #expect(speakers(["You", "Speaker 2", "Voice 4"], hints: hints) == ["You", "Virginia", "Jodi"])
    }

    @Test func emptyInputStaysEmpty() {
        #expect(SpeakerLabelNormalizer.normalize(segments: [], hints: .init()).isEmpty)
    }

    @Test func normalizeNoteFieldsRebuildsTranscriptFromSegmentsInOffsetOrder() {
        let segments = [
            Fixtures.segment("voice 2", at: 5, "second"),
            Fixtures.segment("you", at: 1, "first"),
        ]
        let result = SpeakerLabelNormalizer.normalizeNoteFields(
            segments: segments,
            transcript: "ignored",
            hints: .init()
        )
        #expect(result.transcript == "[You] first\n[Others] second")
        #expect(result.segments.map(\.speaker) == ["Others", "You"])
    }

    @Test func normalizeNoteFieldsRewritesFlatTranscriptWithoutSegments() {
        let result = SpeakerLabelNormalizer.normalizeNoteFields(
            segments: [],
            transcript: "[you] hi\n[voice 2] hello\n[JODI] hey",
            hints: .init(rosterNames: ["Jodi"])
        )
        #expect(result.transcript == "[You] hi\n[Others] hello\n[Jodi] hey")
    }
}
