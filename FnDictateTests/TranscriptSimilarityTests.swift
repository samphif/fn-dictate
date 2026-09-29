import Foundation
import Testing
@testable import FnDictate

struct TranscriptSimilarityTests {
    @Test func tokensIgnoreCaseAndPunctuation() {
        #expect(TranscriptSimilarity.tokens("Hey, Sam! It's 5pm.") == ["hey", "sam", "it", "s", "5pm"])
        #expect(TranscriptSimilarity.tokenCount("   ") == 0)
    }

    @Test func similarityIsSharedWordsOverLongerLine() {
        #expect(TranscriptSimilarity.similarity("ship it friday", "ship it on friday") == 0.75)
        #expect(TranscriptSimilarity.similarity("", "anything") == 0)
    }

    @Test func nearDuplicateToleratesSmallAsrDifferences() {
        #expect(TranscriptSimilarity.isNearDuplicate(
            "we should ship the build on friday",
            "We should ship the bill on Friday"
        ))
    }

    @Test func shortRepliesNeedAClosematch() {
        #expect(!TranscriptSimilarity.isNearDuplicate("sounds good", "sounds great"))
        #expect(TranscriptSimilarity.isNearDuplicate("sounds good", "Sounds good."))
        #expect(!TranscriptSimilarity.isNearDuplicate("ok", "ok"))
    }

    @Test func collapsingEchoesPrefersTheNonYouCopyWithLongerText() {
        let voice = UUID()
        let segments = [
            MeetingTranscriptSegment(startOffset: 2, text: "we should ship the build on friday", speaker: "You"),
            MeetingTranscriptSegment(
                startOffset: 2.4,
                text: "we should ship the build",
                speaker: "Jodi",
                voiceID: voice
            ),
            MeetingTranscriptSegment(startOffset: 30, text: "we should ship the build on friday", speaker: "You"),
        ]
        let collapsed = TranscriptSimilarity.collapsingChannelEchoes(segments)
        #expect(collapsed.count == 2)
        #expect(collapsed[0].speaker == "Jodi")
        #expect(collapsed[0].text == "we should ship the build on friday")
        #expect(collapsed[0].voiceID == voice)
        #expect(collapsed[0].startOffset == 2)
        #expect(collapsed[1].speaker == "You")
    }
}

struct CalendarMeetingContextTests {
    private func context(_ attendees: [String]) -> CalendarMeetingContext {
        CalendarMeetingContext(
            eventIdentifier: "id",
            title: "Sync",
            startDate: .now,
            endDate: .now,
            attendees: attendees,
            location: nil,
            notes: nil
        )
    }

    @Test func singleAttendeeIsTheOneOnOneName() {
        #expect(context(["Jodi"]).remoteOneOnOneName == "Jodi")
        #expect(context([" Jodi ", "Jodi", "  "]).remoteOneOnOneName == "Jodi")
    }

    @Test func groupOrEmptyInviteHasNoOneOnOneName() {
        #expect(context([]).remoteOneOnOneName == nil)
        #expect(context(["Jodi", "Virginia"]).remoteOneOnOneName == nil)
    }
}
