import FluidAudio
import Foundation
import Testing
@testable import FnDictate

struct MeetingFinalizerTests {
    private func words(_ pairs: [(String, TimeInterval)]) -> [TimedWord] {
        pairs.map { TimedWord(text: $0.0, start: $0.1) }
    }

    @Test func parakeetWordsReplaceLiveTextPerSegment() {
        let segments = [
            Fixtures.segment("You", at: 0, "hey their"),
            Fixtures.segment("You", at: 4, "how r you"),
        ]
        let result = MeetingFinalizer.replacingText(
            of: .microphone,
            in: segments,
            with: words([("Hey", 0.1), ("there.", 0.5), ("How", 4.2), ("are", 4.4), ("you?", 4.6)])
        )
        #expect(result.map(\.text) == ["Hey there.", "How are you?"])
        #expect(result.map(\.id) == segments.map(\.id))
    }

    @Test func wordsOnlyReachTheirOwnChannel() {
        let segments = [
            Fixtures.segment("You", at: 0, "mic line"),
            Fixtures.segment("Others", at: 0, "remote line"),
        ]
        let result = MeetingFinalizer.replacingText(of: .system, in: segments, with: words([("Remote", 0.2)]))
        #expect(result.map(\.text) == ["mic line", "Remote"])
    }

    @Test func wordsJustBeforeASegmentStartBelongToIt() {
        let segments = [Fixtures.segment("You", at: 0, "a"), Fixtures.segment("You", at: 5, "b")]
        let result = MeetingFinalizer.replacingText(
            of: .microphone,
            in: segments,
            with: words([("first", 1), ("second", 4.9)])
        )
        #expect(result.map(\.text) == ["first", "second"])
    }

    @Test func segmentsWithoutWordsKeepLiveTextAndTransformAppliesToNewText() {
        let segments = [Fixtures.segment("You", at: 0, "keep"), Fixtures.segment("You", at: 10, "swap")]
        let result = MeetingFinalizer.replacingText(
            of: .microphone,
            in: segments,
            with: words([("new", 11)]),
            transform: { $0.uppercased() }
        )
        #expect(result.map(\.text) == ["keep", "NEW"])
    }

    @Test func emptyMeetingKeepsBothChannelsFinishedText() {
        let result = MeetingFinalizer.fillingSilentChannels([], micText: "mine", systemText: "theirs", remoteSpeaker: "Jodi")
        #expect(result.map(\.speaker) == ["You", "Jodi"])
        #expect(result.map(\.channel) == [.microphone, .system])
        #expect(result.map(\.text) == ["mine", "theirs"])
    }

    @Test func silentRemoteChannelGetsItsFinishedText() {
        let live = [Fixtures.segment("You", at: 3)]
        let result = MeetingFinalizer.fillingSilentChannels(live, micText: "echo", systemText: "theirs", remoteSpeaker: "Others")
        #expect(result.map(\.speaker) == ["You", "Others"])
        #expect(result.last?.startOffset == 3.1)
    }

    @Test func leftoverTextIsIgnoredWhenBothChannelsHaveLines() {
        let live = [Fixtures.segment("You", at: 0), Fixtures.segment("Others", at: 2)]
        #expect(MeetingFinalizer.fillingSilentChannels(live, micText: "a", systemText: "b", remoteSpeaker: "Others") == live)
    }
}

struct ParakeetWordTests {
    private func token(_ text: String, _ start: TimeInterval) -> TokenTiming {
        TokenTiming(token: text, tokenId: 0, startTime: start, endTime: start + 0.1, confidence: 1)
    }

    @Test func mergesSubwordTokensIntoWords() {
        let words = ParakeetASRClient.words(from: [
            token("▁H", 0), token("ello", 0.1), token(",", 0.2), token(" wor", 0.5), token("ld", 0.6),
        ])
        #expect(words == [TimedWord(text: "Hello,", start: 0), TimedWord(text: "world", start: 0.5)])
    }

    @Test func bareSpaceTokenStartsTheNextWord() {
        let words = ParakeetASRClient.words(from: [token("hi", 0), token("▁", 0.3), token("there", 0.4)])
        #expect(words.map(\.text) == ["hi", "there"])
        #expect(words.last?.start == 0.4)
    }
}

struct MeetingChannelActivityTests {
    private let start = Date(timeIntervalSince1970: 0)

    @Test func loudChannelLightsUp() {
        var activity = MeetingChannelActivity()
        activity.levelsChanged(you: 0.3, others: 0, at: start)
        #expect(activity.active == .you)
    }

    @Test func echoTieFavorsSystemAudioWhenNothingIsLit() {
        var activity = MeetingChannelActivity()
        activity.levelsChanged(you: 0.2, others: 0.22, at: start)
        #expect(activity.active == .others)
    }

    @Test func litSideHoldsUntilTheOtherIsLouderByAMargin() {
        var activity = MeetingChannelActivity()
        activity.heardLine(from: .you, at: start)
        activity.levelsChanged(you: 0.2, others: 0.25, at: start.addingTimeInterval(0.1))
        #expect(activity.active == .you)
        activity.levelsChanged(you: 0.2, others: 0.3, at: start.addingTimeInterval(0.2))
        #expect(activity.active == .others)
    }

    @Test func quietsDownAfterTheHold() {
        var activity = MeetingChannelActivity()
        activity.levelsChanged(you: 0.3, others: 0, at: start)
        activity.levelsChanged(you: 0, others: 0, at: start.addingTimeInterval(0.5))
        #expect(activity.active == .you)
        activity.levelsChanged(you: 0, others: 0, at: start.addingTimeInterval(1.3))
        #expect(activity.active == nil)
    }
}
