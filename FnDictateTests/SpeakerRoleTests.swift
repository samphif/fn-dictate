import Testing
@testable import FnDictate

struct SpeakerRoleTests {
    @Test(arguments: ["you", " YOU "])
    func parsesYou(_ label: String) {
        #expect(SpeakerRole(label) == .you)
    }

    @Test(arguments: ["Others", "other", "Them"])
    func parsesOthersSynonyms(_ label: String) {
        #expect(SpeakerRole(label) == .others)
    }

    @Test func parsesDiarizationSlotsAndLegacyVoices() {
        #expect(SpeakerRole("Speaker 12") == .slot(12))
        #expect(SpeakerRole("speaker-1") == .slot(1))
        #expect(SpeakerRole("SPEAKER 4") == .slot(4))
        #expect(SpeakerRole("voice_2") == .legacyVoice(2))
        #expect(SpeakerRole(" Voice 7 ") == .legacyVoice(7))
    }

    @Test(arguments: ["Speaker", "Jodi", "Voice of reason", "Speaker 2 Jodi", "Speakman"])
    func treatsEverythingElseAsANamedPerson(_ label: String) {
        #expect(SpeakerRole(label) == .named(label))
        #expect(!SpeakerRole(label).isAnonymous)
    }

    @Test func labelsRoundTrip() {
        for role: SpeakerRole in [.you, .others, .slot(3), .legacyVoice(2), .named("Jodi")] {
            #expect(SpeakerRole(role.label) == role)
        }
    }
}
