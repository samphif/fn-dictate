import Foundation
import Testing
@testable import FnDictate

@MainActor
struct MeetingSpeakerTrackerTests {
    private let userVoice = Fixtures.voiceprint(axis: 0)
    private let jodiVoice = Fixtures.voiceprint(axis: 1)
    private let jodi = Fixtures.profile(name: "Jodi", axis: 1)

    private func makeTracker(_ temp: TemporaryDirectory) throws -> MeetingSpeakerTracker {
        try temp.writeProfiles([
            Fixtures.profile(name: "You", axis: 0, sampleCount: 5, isUser: true),
            jodi,
        ])
        let tracker = MeetingSpeakerTracker(voices: VoiceProfileStore(directory: temp.url))
        tracker.begin()
        return tracker
    }

    private func appended(_ decision: MeetingTurnDecision) -> MeetingTranscriptSegment? {
        if case .append(let segment) = decision { return segment }
        return nil
    }

    @Test func micLinesAreYou() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tracker = try makeTracker(temp)

        let segment = try #require(appended(
            tracker.resolve(text: "let's get started", offset: 1, channel: .microphone, embedding: nil)
        ))
        #expect(segment.speaker == "You")
        #expect(segment.voiceID == nil)
        #expect(segment.startOffset == 1)
    }

    @Test func unknownSystemVoiceIsOthers() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tracker = try makeTracker(temp)

        let segment = try #require(appended(
            tracker.resolve(text: "sounds good to me", offset: 1, channel: .system, embedding: Fixtures.voiceprint(axis: 8))
        ))
        #expect(segment.speaker == "Others")
        #expect(tracker.lastRemoteLabel == "Others")
    }

    @Test func calendarOneOnOneNameLabelsUnknownRemote() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tracker = try makeTracker(temp)
        tracker.preferredRemoteName = "  Virginia "

        let segment = try #require(appended(
            tracker.resolve(text: "sounds good to me", offset: 1, channel: .system, embedding: nil)
        ))
        #expect(segment.speaker == "Virginia")
    }

    @Test func beginClearsPreferredRemoteName() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tracker = try makeTracker(temp)
        tracker.preferredRemoteName = "Virginia"
        tracker.begin()

        #expect(tracker.preferredRemoteName == nil)
    }

    @Test func rememberedRemoteVoiceIsNamed() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tracker = try makeTracker(temp)

        let segment = try #require(appended(
            tracker.resolve(text: "I pushed the fix", offset: 2, channel: .system, embedding: jodiVoice)
        ))
        #expect(segment.speaker == "Jodi")
        #expect(segment.voiceID == jodi.id)
        #expect(tracker.lastRemoteLabel == "Jodi")
    }

    @Test func systemAudioInYourVoiceIsYou() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tracker = try makeTracker(temp)

        let segment = try #require(appended(
            tracker.resolve(text: "I can take that", offset: 2, channel: .system, embedding: userVoice)
        ))
        #expect(segment.speaker == "You")
    }

    @Test func namedRemoteStaysStickyForShortGaps() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tracker = try makeTracker(temp)
        _ = tracker.resolve(text: "I pushed the fix", offset: 10, channel: .system, embedding: jodiVoice)

        let soon = try #require(appended(
            tracker.resolve(text: "and updated the docs", offset: 13, channel: .system, embedding: nil)
        ))
        #expect(soon.speaker == "Jodi")

        let later = try #require(appended(
            tracker.resolve(text: "anything else before we wrap", offset: 30, channel: .system, embedding: nil)
        ))
        #expect(later.speaker == "Others")
    }

    @Test func echoOfMicLineOnSystemAudioIsDropped() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tracker = try makeTracker(temp)
        let text = "we should ship the build on friday"
        _ = tracker.resolve(text: text, offset: 1, channel: .microphone, embedding: nil)

        let decision = tracker.resolve(text: text, offset: 1.5, channel: .system, embedding: nil)
        guard case .drop = decision else {
            Issue.record("Expected echo to be dropped, got \(decision)")
            return
        }
    }

    @Test func longerEchoLengthensTheMicLineButKeepsYou() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tracker = try makeTracker(temp)
        let original = try #require(appended(
            tracker.resolve(text: "we should ship the build on friday", offset: 1, channel: .microphone, embedding: nil)
        ))

        let decision = tracker.resolve(
            text: "we should ship the build on friday morning",
            offset: 1.5,
            channel: .system,
            embedding: Fixtures.voiceprint(axis: 8)
        )
        guard case .update(let id, let text, let speaker, let voiceID) = decision else {
            Issue.record("Expected update, got \(decision)")
            return
        }
        #expect(id == original.id)
        #expect(text == "we should ship the build on friday morning")
        #expect(speaker == "You")
        #expect(voiceID == nil)
    }

    @Test func echoInARememberedRemoteVoiceMovesTheLineToThem() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tracker = try makeTracker(temp)
        let original = try #require(appended(
            tracker.resolve(text: "we should ship the build on friday", offset: 1, channel: .microphone, embedding: nil)
        ))

        let decision = tracker.resolve(
            text: "we should ship the build on friday",
            offset: 1.5,
            channel: .system,
            embedding: jodiVoice
        )
        guard case .update(let id, _, let speaker, let voiceID) = decision else {
            Issue.record("Expected update, got \(decision)")
            return
        }
        #expect(id == original.id)
        #expect(speaker == "Jodi")
        #expect(voiceID == jodi.id)
    }

    @Test func distantRepeatIsANewLine() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tracker = try makeTracker(temp)
        let text = "we should ship the build on friday"
        _ = tracker.resolve(text: text, offset: 1, channel: .microphone, embedding: nil)

        #expect(appended(tracker.resolve(text: text, offset: 40, channel: .system, embedding: nil)) != nil)
    }

    @Test func renameUpdatesStickyLabel() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tracker = try makeTracker(temp)
        _ = tracker.resolve(text: "I pushed the fix", offset: 10, channel: .system, embedding: jodiVoice)
        tracker.noteRename(id: jodi.id, to: "Jodi Smith")

        #expect(tracker.lastRemoteLabel == "Jodi Smith")
    }

    @Test func endLearnsYourVoiceFromMicLines() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let tracker = try makeTracker(temp)
        _ = tracker.resolve(text: "let's get started", offset: 1, channel: .microphone, embedding: userVoice)
        tracker.end()

        let user = try #require(try temp.readProfiles().first(where: \.isUser))
        #expect(user.sampleCount == 6)
    }
}

struct HybridTranscriptionServiceTests {
    @Test func appleModeNeverRunsParakeet() {
        #expect(!HybridTranscriptionService.shouldRefineWithParakeet(mode: .apple, sampleCount: 1_000_000))
    }

    @Test func parakeetNeedsAtLeastAFifthOfASecond() {
        #expect(!HybridTranscriptionService.shouldRefineWithParakeet(mode: .parakeet, sampleCount: 0))
        #expect(!HybridTranscriptionService.shouldRefineWithParakeet(mode: .parakeet, sampleCount: 3_199))
        #expect(HybridTranscriptionService.shouldRefineWithParakeet(mode: .parakeet, sampleCount: 3_200))
    }
}
