import Foundation
import Testing
@testable import FnDictate

@MainActor
struct VoiceProfileStoreTests {
    @Test func freshStoreCreatesAndPersistsTheUserProfile() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }

        let store = VoiceProfileStore(directory: temp.url)
        let user = try #require(store.profiles.first)
        #expect(store.profiles.count == 1)
        #expect(user.isUser)
        #expect(user.name == "You")
        #expect(store.userVoiceID == user.id)
        #expect(try temp.readProfiles() == store.profiles)
    }

    @Test func createsMissingDirectory() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let nested = temp.url.appendingPathComponent("a/b", isDirectory: true)

        _ = VoiceProfileStore(directory: nested)
        #expect(FileManager.default.fileExists(atPath: nested.appendingPathComponent("voices.json").path))
    }

    @Test func profilesRoundTripThroughDisk() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let saved = [
            Fixtures.profile(name: "You", axis: 0, sampleCount: 4, isUser: true),
            Fixtures.profile(name: "Jodi", axis: 1),
            Fixtures.profile(name: "Voice 3", axis: 2, sampleCount: 1),
        ]
        try temp.writeProfiles(saved)

        let store = VoiceProfileStore(directory: temp.url)
        #expect(store.profiles == saved)

        let jodi = saved[1].id
        #expect(store.rename(id: jodi, to: "  Jodi Smith ") == "Jodi Smith")

        let reloaded = VoiceProfileStore(directory: temp.url)
        #expect(reloaded.profiles.first(where: { $0.id == jodi })?.name == "Jodi Smith")
        #expect(reloaded.profiles.count == 3)
    }

    @Test func corruptFileFallsBackToAFreshUserProfile() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try Data("not json".utf8).write(to: temp.voicesFile)

        let store = VoiceProfileStore(directory: temp.url)
        #expect(store.profiles.count == 1)
        #expect(store.profiles.first?.isUser == true)
    }

    @Test func rememberedNamesSkipUserAndGenericVoices() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        try temp.writeProfiles([
            Fixtures.profile(name: "You", axis: 0, isUser: true),
            Fixtures.profile(name: "Jodi", axis: 1),
            Fixtures.profile(name: "Voice 3", axis: 2),
            Fixtures.profile(name: "Virginia", axis: 3),
        ])

        let store = VoiceProfileStore(directory: temp.url)
        #expect(store.rememberedNames == ["Jodi", "Virginia"])
    }

    @Test(arguments: ["", "   ", "You", "others", String(repeating: "x", count: 41)])
    func renameRejectsReservedOrInvalidNames(_ name: String) throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let jodi = Fixtures.profile(name: "Jodi", axis: 1)
        try temp.writeProfiles([Fixtures.profile(name: "You", axis: 0, isUser: true), jodi])

        let store = VoiceProfileStore(directory: temp.url)
        #expect(store.rename(id: jodi.id, to: name) == nil)
        #expect(store.profiles.first(where: { $0.id == jodi.id })?.name == "Jodi")
    }

    @Test func renameRefusesTheUserProfileAndUnknownIDs() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let store = VoiceProfileStore(directory: temp.url)

        #expect(store.rename(id: store.userVoiceID, to: "Sam") == nil)
        #expect(store.rename(id: UUID(), to: "Sam") == nil)
    }

    @Test func matchesUserOnlyAfterEnoughSamples() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let store = VoiceProfileStore(directory: temp.url)
        let voice = Fixtures.voiceprint(axis: 4)

        #expect(!store.matchesUser(voice))
        store.observeUser(voice)
        #expect(!store.matchesUser(voice))
        store.observeUser(voice)
        #expect(store.matchesUser(voice))
        #expect(!store.matchesUser(Fixtures.voiceprint(axis: 5)))
        #expect(!store.matchesUser(nil))

        let reloaded = VoiceProfileStore(directory: temp.url)
        #expect(reloaded.profiles.first(where: \.isUser)?.sampleCount == 2)
        #expect(reloaded.matchesUser(voice))
    }

    @Test func matchCommittedRemoteFindsSavedVoiceAndLearnsFromIt() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let jodi = Fixtures.profile(name: "Jodi", axis: 1, sampleCount: 3)
        try temp.writeProfiles([Fixtures.profile(name: "You", axis: 0, isUser: true), jodi])

        let store = VoiceProfileStore(directory: temp.url)
        let match = try #require(store.matchCommittedRemote(Fixtures.voiceprint(axis: 1)))
        #expect(match == VoiceLabel(name: "Jodi", id: jodi.id, isUser: false))
        #expect(store.profiles.first(where: { $0.id == jodi.id })?.sampleCount == 4)
        #expect(store.matchCommittedRemote(Fixtures.voiceprint(axis: 7)) == nil)
    }

    @Test func unknownRemoteVoicesStayOthersInsteadOfInventingVoiceN() throws {
        let temp = try TemporaryDirectory()
        defer { temp.remove() }
        let store = VoiceProfileStore(directory: temp.url)

        #expect(store.labelRemote(embedding: nil) == store.othersLabel)
        #expect(store.labelRemote(embedding: Fixtures.voiceprint(axis: 9)) == store.othersLabel)
        #expect(store.profiles.count == 1)
    }
}

struct VoiceprintTests {
    @Test func tooShortAudioHasNoVoiceprint() {
        #expect(Voiceprint.make(samples: Fixtures.tone(amplitude: 0.3, seconds: 0.2), sampleRate: 16_000) == nil)
        #expect(Voiceprint.make(samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000) == nil)
    }

    @Test func voicedAudioProducesAUnitVector() throws {
        let samples = (0..<16_000).map { index in
            Float(0.3 * sin(2 * Double.pi * 180 * Double(index) / 16_000))
        }
        let fingerprint = try #require(Voiceprint.make(samples: samples, sampleRate: 16_000))
        #expect(fingerprint.count == Voiceprint.dimension)
        #expect(abs(Voiceprint.cosine(fingerprint, fingerprint) - 1) < 0.001)
    }

    @Test func cosineRejectsMismatchedDimensions() {
        #expect(Voiceprint.cosine([1, 0], [1, 0]) == 0)
    }

    @Test func blendStaysNormalized() {
        let blended = Voiceprint.blend(Fixtures.voiceprint(axis: 0), Fixtures.voiceprint(axis: 1), sampleCount: 1)
        #expect(abs(Voiceprint.cosine(blended, blended) - 1) < 0.001)
        #expect(blended[0] > blended[1])
    }
}
