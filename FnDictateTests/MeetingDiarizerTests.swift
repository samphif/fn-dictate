import Testing
@testable import FnDictate

struct MeetingDiarizerTests {
    private let micSpeech = Fixtures.tone(amplitude: 0.2, seconds: 3)
    private let silentSystem = [Float](repeating: 0, count: 48_000)
    private let noiseFloorSystem = Fixtures.tone(amplitude: 0.002, seconds: 3)
    private let remoteSpeech = Fixtures.tone(amplitude: 0.15, seconds: 3)

    @Test func mixAveragesAndPadsTheShorterStream() {
        #expect(MeetingDiarizer.mix([1, 1, 1], [1]) == [1, 0.5, 0.5])
        #expect(MeetingDiarizer.mix([], [0.4]) == [0.2])
        #expect(MeetingDiarizer.mix([], []).isEmpty)
    }

    @Test func meanAbsEnergy() {
        #expect(MeetingDiarizer.meanAbsEnergy([]) == 0)
        #expect(MeetingDiarizer.meanAbsEnergy([-0.5, 0.5, -0.5, 0.5]) == 0.5)
        #expect(abs(MeetingDiarizer.meanAbsEnergy(Fixtures.tone(amplitude: 0.3, seconds: 10)) - 0.3) < 0.001)
    }

    @Test func systemAudioShorterThanOneSecondIsNotSpeech() {
        let short = Fixtures.tone(amplitude: 0.3, seconds: 0.9)
        #expect(!MeetingDiarizer.hasMeaningfulSpeech(short, versusMic: micSpeech))
    }

    @Test func silentOrNoiseSystemAudioIsNotSpeech() {
        #expect(!MeetingDiarizer.hasMeaningfulSpeech(silentSystem, versusMic: micSpeech))
        #expect(!MeetingDiarizer.hasMeaningfulSpeech(noiseFloorSystem, versusMic: micSpeech))
    }

    @Test func quietSystemRelativeToLoudMicIsNotSpeech() {
        let quiet = Fixtures.tone(amplitude: 0.01, seconds: 3)
        let loudMic = Fixtures.tone(amplitude: 0.5, seconds: 3)
        #expect(!MeetingDiarizer.hasMeaningfulSpeech(quiet, versusMic: loudMic))
    }

    @Test func remoteSpeechIsDetected() {
        #expect(MeetingDiarizer.hasMeaningfulSpeech(remoteSpeech, versusMic: micSpeech))
        #expect(MeetingDiarizer.hasMeaningfulSpeech(remoteSpeech, versusMic: []))
    }

    @Test func inPersonMeetingDiarizesTheMicAsSharedMic() throws {
        let input = try #require(
            MeetingDiarizer.input(youSamples: micSpeech, othersSamples: silentSystem, liveLabelsAllYou: true)
        )
        #expect(input.isSharedMic)
        #expect(input.samples == micSpeech)
    }

    @Test func emptySystemAudioMeansSharedMicEvenWithMixedLiveLabels() throws {
        let input = try #require(
            MeetingDiarizer.input(youSamples: micSpeech, othersSamples: noiseFloorSystem, liveLabelsAllYou: false)
        )
        #expect(input.isSharedMic)
        #expect(input.samples == micSpeech)
    }

    @Test func allYouLabelsWithSpeakerPlaybackMixesChannels() throws {
        let input = try #require(
            MeetingDiarizer.input(youSamples: micSpeech, othersSamples: remoteSpeech, liveLabelsAllYou: true)
        )
        #expect(input.isSharedMic)
        #expect(input.samples == MeetingDiarizer.mix(micSpeech, remoteSpeech))
    }

    @Test func sharedMicWithoutMicAudioHasNothingToDiarize() {
        #expect(MeetingDiarizer.input(youSamples: [], othersSamples: silentSystem, liveLabelsAllYou: true) == nil)
    }

    @Test func remoteCallDiarizesSystemAudio() throws {
        let input = try #require(
            MeetingDiarizer.input(youSamples: micSpeech, othersSamples: remoteSpeech, liveLabelsAllYou: false)
        )
        #expect(!input.isSharedMic)
        #expect(input.samples == remoteSpeech)
    }

    @Test func remoteCallWithShorterSystemAudioMixesChannels() throws {
        let longerMic = Fixtures.tone(amplitude: 0.2, seconds: 4)
        let input = try #require(
            MeetingDiarizer.input(youSamples: longerMic, othersSamples: remoteSpeech, liveLabelsAllYou: false)
        )
        #expect(!input.isSharedMic)
        #expect(input.samples == MeetingDiarizer.mix(longerMic, remoteSpeech))
    }

    @Test func diarizeReturnsNothingForUnderTwoSeconds() async {
        let diarizer = MeetingDiarizer()
        let turns = await diarizer.diarize(Fixtures.tone(amplitude: 0.2, seconds: 1.5))
        let ready = await diarizer.isReady
        #expect(turns.isEmpty)
        #expect(!ready)
    }
}
