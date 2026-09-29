import Testing
@testable import FnDictate

struct DiarizationPlanTests {
    private let micSpeech = Fixtures.tone(amplitude: 0.2, seconds: 3)
    private let silentSystem = [Float](repeating: 0, count: 48_000)
    private let noiseFloorSystem = Fixtures.tone(amplitude: 0.002, seconds: 3)
    private let remoteSpeech = Fixtures.tone(amplitude: 0.15, seconds: 3)

    private let inPersonSegments = [Fixtures.segment("You", at: 0), Fixtures.segment("You", at: 5)]
    private let callSegments = [Fixtures.segment("You", at: 0), Fixtures.segment("Others", at: 5)]

    @Test func meanAbsEnergy() {
        #expect(DiarizationPlan.meanAbsEnergy([]) == 0)
        #expect(DiarizationPlan.meanAbsEnergy([-0.5, 0.5, -0.5, 0.5]) == 0.5)
        #expect(abs(DiarizationPlan.meanAbsEnergy(Fixtures.tone(amplitude: 0.3, seconds: 10)) - 0.3) < 0.001)
    }

    @Test func systemAudioShorterThanOneSecondIsNotSpeech() {
        let short = Fixtures.tone(amplitude: 0.3, seconds: 0.9)
        #expect(!DiarizationPlan.hasMeaningfulSpeech(short, versusMic: micSpeech))
    }

    @Test func silentOrNoiseSystemAudioIsNotSpeech() {
        #expect(!DiarizationPlan.hasMeaningfulSpeech(silentSystem, versusMic: micSpeech))
        #expect(!DiarizationPlan.hasMeaningfulSpeech(noiseFloorSystem, versusMic: micSpeech))
    }

    @Test func quietSystemRelativeToLoudMicIsNotSpeech() {
        let quiet = Fixtures.tone(amplitude: 0.01, seconds: 3)
        let loudMic = Fixtures.tone(amplitude: 0.5, seconds: 3)
        #expect(!DiarizationPlan.hasMeaningfulSpeech(quiet, versusMic: loudMic))
    }

    @Test func remoteSpeechIsDetected() {
        #expect(DiarizationPlan.hasMeaningfulSpeech(remoteSpeech, versusMic: micSpeech))
        #expect(DiarizationPlan.hasMeaningfulSpeech(remoteSpeech, versusMic: []))
    }

    @Test func inPersonMeetingDiarizesTheMic() {
        let plan = DiarizationPlan(segments: inPersonSegments, micSamples: micSpeech, systemSamples: silentSystem)
        #expect(plan == DiarizationPlan(channel: .microphone, samples: micSpeech))
    }

    @Test func remoteLinesWithoutFarEndAudioStillDiarizeTheMic() {
        let plan = DiarizationPlan(segments: callSegments, micSamples: micSpeech, systemSamples: noiseFloorSystem)
        #expect(plan == DiarizationPlan(channel: .microphone, samples: micSpeech))
    }

    @Test func speakerPlaybackWithOnlyYouLinesDiarizesTheMicUnmixed() {
        let plan = DiarizationPlan(segments: inPersonSegments, micSamples: micSpeech, systemSamples: remoteSpeech)
        #expect(plan == DiarizationPlan(channel: .microphone, samples: micSpeech))
    }

    @Test func remoteCallDiarizesSystemAudioEvenWhenTheMicRanLonger() {
        let longerMic = Fixtures.tone(amplitude: 0.2, seconds: 4)
        let plan = DiarizationPlan(segments: callSegments, micSamples: longerMic, systemSamples: remoteSpeech)
        #expect(plan == DiarizationPlan(channel: .system, samples: remoteSpeech))
    }

    @Test func nothingToDiarizeWithoutMicAudio() {
        #expect(DiarizationPlan(segments: inPersonSegments, micSamples: [], systemSamples: silentSystem) == nil)
    }

    @Test func diarizeReturnsNothingForUnderTwoSeconds() async {
        let diarizer = MeetingDiarizer()
        let turns = await diarizer.diarize(Fixtures.tone(amplitude: 0.2, seconds: 1.5))
        let ready = await diarizer.isReady
        #expect(turns.isEmpty)
        #expect(!ready)
    }
}
