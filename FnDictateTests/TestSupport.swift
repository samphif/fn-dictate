import Foundation
@testable import FnDictate

struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FnDictateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    var voicesFile: URL {
        url.appendingPathComponent("voices.json")
    }

    func writeProfiles(_ profiles: [VoiceProfile]) throws {
        try JSONEncoder().encode(profiles).write(to: voicesFile)
    }

    func readProfiles() throws -> [VoiceProfile] {
        try JSONDecoder().decode([VoiceProfile].self, from: Data(contentsOf: voicesFile))
    }
}

enum Fixtures {
    /// Unit-length voiceprint pointing along one axis, so distinct axes have cosine 0.
    static func voiceprint(axis: Int) -> [Float] {
        var vector = [Float](repeating: 0, count: Voiceprint.dimension)
        vector[axis] = 1
        return vector
    }

    static func profile(
        name: String,
        axis: Int,
        sampleCount: Int = 3,
        isUser: Bool = false
    ) -> VoiceProfile {
        VoiceProfile(
            id: UUID(),
            name: name,
            embedding: voiceprint(axis: axis),
            sampleCount: sampleCount,
            isUser: isUser,
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
    }

    static func segment(_ speaker: String, at offset: TimeInterval, _ text: String = "hello there") -> MeetingTranscriptSegment {
        MeetingTranscriptSegment(startOffset: offset, text: text, speaker: speaker)
    }

    static func turn(_ speaker: Int, _ start: TimeInterval, _ end: TimeInterval) -> MeetingDiarizerTurn {
        MeetingDiarizerTurn(speakerIndex: speaker, startTime: start, endTime: end)
    }

    static func tone(amplitude: Float, seconds: Double, sampleRate: Double = 16_000) -> [Float] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { index in
            index.isMultiple(of: 2) ? amplitude : -amplitude
        }
    }
}
