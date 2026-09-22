import Foundation

enum MeetingAudioChannel: Sendable {
    case microphone
    case system
}

struct VoiceLabel: Sendable, Equatable {
    var name: String
    var id: UUID?
    var isUser: Bool
}

/// Compact on-device voice fingerprint. Not a neural model — a spectral
/// envelope plus a pitch histogram, enough to tell regular collaborators apart
/// on the same Mac across meetings.
enum Voiceprint: Sendable {
    static let dimension = 24

    static func make(samples: [Float], sampleRate: Double) -> [Float]? {
        guard sampleRate > 1_000, samples.count >= Int(sampleRate * 0.35) else { return nil }
        let targetRate = 8_000.0
        let mono = downsample(samples, from: sampleRate, to: targetRate)
        let frameSize = 200
        let hop = 80
        guard mono.count >= frameSize else { return nil }

        var bands = [Float](repeating: 0, count: 16)
        var pitches = [Float](repeating: 0, count: 8)
        var voiced = 0
        var pitchVotes = 0
        var offset = 0
        while offset + frameSize <= mono.count {
            let frame = Array(mono[offset..<(offset + frameSize)])
            let energy = rms(frame)
            if energy >= 0.01 {
                voiced += 1
                let spectrum = logBands(frame, sampleRate: Float(targetRate))
                for index in 0..<16 {
                    bands[index] += spectrum[index]
                }
                if voiced % 3 == 0, let bin = pitchBin(frame, sampleRate: Float(targetRate)) {
                    pitches[bin] += 1
                    pitchVotes += 1
                }
            }
            offset += hop
        }
        guard voiced >= 6 else { return nil }
        for index in 0..<16 {
            bands[index] /= Float(voiced)
        }
        let mean = bands.reduce(0, +) / 16
        for index in 0..<16 {
            bands[index] -= mean
        }
        if pitchVotes > 0 {
            for index in 0..<8 {
                pitches[index] /= Float(pitchVotes)
            }
        }
        return normalize(bands + pitches)
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, a.count == dimension else { return 0 }
        var dot: Float = 0
        for index in 0..<a.count {
            dot += a[index] * b[index]
        }
        return dot
    }

    static func blend(_ old: [Float], _ new: [Float], sampleCount: Int) -> [Float] {
        guard old.count == new.count, !old.isEmpty else { return new }
        let weight = min(0.35, 1 / Float(sampleCount + 1))
        var mixed = [Float](repeating: 0, count: old.count)
        for index in 0..<old.count {
            mixed[index] = old[index] * (1 - weight) + new[index] * weight
        }
        return normalize(mixed) ?? new
    }

    private static func normalize(_ vector: [Float]) -> [Float]? {
        var sum: Float = 0
        for value in vector {
            sum += value * value
        }
        let magnitude = sum.squareRoot()
        guard magnitude > 1e-5 else { return nil }
        return vector.map { $0 / magnitude }
    }

    private static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples {
            sum += sample * sample
        }
        return (sum / Float(samples.count)).squareRoot()
    }

    private static func downsample(_ samples: [Float], from: Double, to: Double) -> [Float] {
        guard from > to + 1 else { return samples }
        let ratio = from / to
        let outCount = Int(Double(samples.count) / ratio)
        guard outCount > 0 else { return [] }
        var output = [Float](repeating: 0, count: outCount)
        for index in 0..<outCount {
            let start = Int(Double(index) * ratio)
            let end = min(samples.count, max(start + 1, Int(Double(index + 1) * ratio)))
            var sum: Float = 0
            for sampleIndex in start..<end {
                sum += samples[sampleIndex]
            }
            output[index] = sum / Float(end - start)
        }
        return output
    }

    private static func logBands(_ frame: [Float], sampleRate: Float) -> [Float] {
        let magnitudes = fftMagnitudes(frame)
        let binHz = sampleRate / 256
        let minHz: Float = 80
        let maxHz = min(3_800, sampleRate / 2 - binHz)
        let logMin = log(minHz)
        let logMax = log(max(minHz + 1, maxHz))
        var bands = [Float](repeating: 0, count: 16)
        for band in 0..<16 {
            let startHz = exp(logMin + (logMax - logMin) * Float(band) / 16)
            let endHz = exp(logMin + (logMax - logMin) * Float(band + 1) / 16)
            let startBin = max(1, Int(startHz / binHz))
            let endBin = min(magnitudes.count - 1, max(startBin, Int(endHz / binHz)))
            var sum: Float = 0
            for bin in startBin...endBin {
                sum += magnitudes[bin]
            }
            bands[band] = log(1 + sum / Float(endBin - startBin + 1))
        }
        return bands
    }

    private static func pitchBin(_ frame: [Float], sampleRate: Float) -> Int? {
        let minLag = max(1, Int(sampleRate / 400))
        let maxLag = min(frame.count - 1, Int(sampleRate / 70))
        guard maxLag > minLag else { return nil }
        var bestLag = 0
        var best: Float = 0
        for lag in minLag...maxLag {
            var sum: Float = 0
            let limit = frame.count - lag
            for index in 0..<limit {
                sum += frame[index] * frame[index + lag]
            }
            if sum > best {
                best = sum
                bestLag = lag
            }
        }
        guard bestLag > 0 else { return nil }
        let hz = min(320, max(80, sampleRate / Float(bestLag)))
        let position = (log(hz) - log(80)) / (log(320) - log(80))
        return min(7, max(0, Int(position * 8)))
    }

    /// 256-point real FFT magnitudes (first half).
    private static func fftMagnitudes(_ input: [Float]) -> [Float] {
        let count = 256
        var real = [Float](repeating: 0, count: count)
        var imag = [Float](repeating: 0, count: count)
        let used = min(input.count, count)
        if used > 1 {
            for index in 0..<used {
                let window = 0.5 * (1 - cos(2 * .pi * Float(index) / Float(used - 1)))
                real[index] = input[index] * window
            }
        }
        var bit = 0
        for index in 1..<count {
            var mask = count >> 1
            while bit & mask != 0 {
                bit ^= mask
                mask >>= 1
            }
            bit ^= mask
            if index < bit {
                real.swapAt(index, bit)
                imag.swapAt(index, bit)
            }
        }
        var length = 2
        while length <= count {
            let angle = -2 * Float.pi / Float(length)
            let stepReal = cos(angle)
            let stepImag = sin(angle)
            var start = 0
            while start < count {
                var twiddleReal: Float = 1
                var twiddleImag: Float = 0
                let half = length / 2
                for offset in 0..<half {
                    let evenIndex = start + offset
                    let oddIndex = evenIndex + half
                    let oddReal = real[oddIndex] * twiddleReal - imag[oddIndex] * twiddleImag
                    let oddImag = real[oddIndex] * twiddleImag + imag[oddIndex] * twiddleReal
                    real[oddIndex] = real[evenIndex] - oddReal
                    imag[oddIndex] = imag[evenIndex] - oddImag
                    real[evenIndex] += oddReal
                    imag[evenIndex] += oddImag
                    let nextReal = twiddleReal * stepReal - twiddleImag * stepImag
                    twiddleImag = twiddleReal * stepImag + twiddleImag * stepReal
                    twiddleReal = nextReal
                }
                start += length
            }
            length <<= 1
        }
        var magnitudes = [Float](repeating: 0, count: count / 2)
        for index in 0..<(count / 2) {
            magnitudes[index] = (real[index] * real[index] + imag[index] * imag[index]).squareRoot()
        }
        return magnitudes
    }
}

struct VoiceProfile: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var embedding: [Float]
    var sampleCount: Int
    var isUser: Bool
    var updatedAt: Date

    var isGenericName: Bool {
        Self.isGeneric(name)
    }

    static func isGeneric(_ name: String) -> Bool {
        guard name.hasPrefix("Voice ") else { return false }
        let suffix = name.dropFirst("Voice ".count)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }
}

/// Saved voices live in Application Support so a person named once is recognized later.
@MainActor
final class VoiceProfileStore {
    private(set) var profiles: [VoiceProfile] = []
    private var sessionIDs = Set<UUID>()
    private var createdThisSession = Set<UUID>()
    private let url: URL

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FnDictate", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("voices.json")
        load()
        ensureUserProfile()
    }

    var userVoiceID: UUID {
        profiles.first(where: \.isUser)?.id ?? ensureUserProfile()
    }

    var userLabel: VoiceLabel {
        VoiceLabel(name: "You", id: nil, isUser: true)
    }

    /// Names the user actually chose — useful as speech hints, not "Voice 3".
    var rememberedNames: [String] {
        profiles.compactMap { profile in
            guard !profile.isUser, !profile.isGenericName else { return nil }
            return profile.name
        }
    }

    func beginSession() {
        sessionIDs.removeAll()
        createdThisSession.removeAll()
    }

    func endSession(keepingWeakVoices: Bool) {
        if !keepingWeakVoices {
            let drop = createdThisSession.filter { id in
                guard let profile = profiles.first(where: { $0.id == id }) else { return false }
                return profile.sampleCount < 2 && profile.isGenericName
            }
            if !drop.isEmpty {
                profiles.removeAll { drop.contains($0.id) }
            }
        }
        sessionIDs.removeAll()
        createdThisSession.removeAll()
        save()
    }

    func matchesUser(_ embedding: [Float]?) -> Bool {
        guard let embedding,
              let user = profiles.first(where: \.isUser),
              user.sampleCount >= 2
        else { return false }
        return Voiceprint.cosine(user.embedding, embedding) >= 0.84
    }

    /// A remote voice we already trust: saved from before, or heard earlier in this meeting.
    func matchCommittedRemote(_ embedding: [Float]) -> VoiceLabel? {
        guard let match = bestRemote(matching: embedding, allowFresh: false) else { return nil }
        observeRemote(id: match.id, embedding: embedding)
        return VoiceLabel(name: match.name, id: match.id, isUser: false)
    }

    func labelRemote(embedding: [Float]?) -> VoiceLabel {
        guard let embedding else {
            return VoiceLabel(name: "Others", id: nil, isUser: false)
        }
        if let match = bestRemote(matching: embedding, allowFresh: true) {
            observeRemote(id: match.id, embedding: embedding)
            return VoiceLabel(name: match.name, id: match.id, isUser: false)
        }
        return createRemote(embedding: embedding)
    }

    func observeUser(_ embedding: [Float]) {
        guard let index = profiles.firstIndex(where: \.isUser) else { return }
        profiles[index].embedding = Voiceprint.blend(
            profiles[index].embedding,
            embedding,
            sampleCount: profiles[index].sampleCount
        )
        profiles[index].sampleCount += 1
        profiles[index].updatedAt = .now
        save()
    }

    func rename(id: UUID, to name: String) -> String? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 40 else { return nil }
        guard cleaned.caseInsensitiveCompare("You") != .orderedSame,
              cleaned.caseInsensitiveCompare("Others") != .orderedSame
        else { return nil }
        guard let index = profiles.firstIndex(where: { $0.id == id }), !profiles[index].isUser else {
            return nil
        }
        profiles[index].name = cleaned
        profiles[index].updatedAt = .now
        save()
        return cleaned
    }

    private func observeRemote(id: UUID, embedding: [Float]) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].embedding = Voiceprint.blend(
            profiles[index].embedding,
            embedding,
            sampleCount: profiles[index].sampleCount
        )
        profiles[index].sampleCount += 1
        profiles[index].updatedAt = .now
        sessionIDs.insert(id)
        save()
    }

    private func bestRemote(matching embedding: [Float], allowFresh: Bool) -> VoiceProfile? {
        var best: VoiceProfile?
        var bestScore: Float = 0
        for profile in profiles where !profile.isUser {
            let score = Voiceprint.cosine(profile.embedding, embedding)
            let threshold: Float
            if sessionIDs.contains(profile.id) {
                threshold = 0.76
            } else if allowFresh {
                threshold = 0.80
            } else {
                // Relabeling a line already tagged You needs a voice we've actually learned.
                threshold = createdThisSession.contains(profile.id) && profile.sampleCount < 2 ? 1.1 : 0.80
            }
            guard score >= threshold, score > bestScore else { continue }
            best = profile
            bestScore = score
        }
        return best
    }

    private func createRemote(embedding: [Float]) -> VoiceLabel {
        let profile = VoiceProfile(
            id: UUID(),
            name: nextGenericName(),
            embedding: embedding,
            sampleCount: 1,
            isUser: false,
            updatedAt: .now
        )
        profiles.append(profile)
        sessionIDs.insert(profile.id)
        createdThisSession.insert(profile.id)
        save()
        return VoiceLabel(name: profile.name, id: profile.id, isUser: false)
    }

    private func nextGenericName() -> String {
        let used = Set(profiles.map(\.name))
        var number = 1
        while used.contains("Voice \(number)") {
            number += 1
        }
        return "Voice \(number)"
    }

    @discardableResult
    private func ensureUserProfile() -> UUID {
        if let existing = profiles.first(where: \.isUser) {
            return existing.id
        }
        let profile = VoiceProfile(
            id: UUID(),
            name: "You",
            embedding: [],
            sampleCount: 0,
            isUser: true,
            updatedAt: .now
        )
        profiles.append(profile)
        save()
        return profile.id
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        profiles = (try? JSONDecoder().decode([VoiceProfile].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
