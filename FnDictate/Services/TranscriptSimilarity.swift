import Foundation

/// Near-duplicate detection for the two meeting channels (mic and system audio).
/// The same utterance often lands on both, with small speech-to-text differences.
enum TranscriptSimilarity {
    static func tokenCount(_ text: String) -> Int {
        tokens(text).count
    }

    /// 0...1, longest common word sequence over the longer line.
    static func similarity(_ a: String, _ b: String) -> Double {
        let left = tokens(a)
        let right = tokens(b)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let shared = longestCommonSubsequenceCount(left, right)
        return Double(shared) / Double(max(left.count, right.count))
    }

    static func isNearDuplicate(_ a: String, _ b: String) -> Bool {
        let left = tokens(a)
        let right = tokens(b)
        let shorter = min(left.count, right.count)
        let longer = max(left.count, right.count)
        guard shorter >= 2, longer > 0 else { return false }
        let shared = longestCommonSubsequenceCount(left, right)
        let cover = Double(shared) / Double(longer)
        let recall = Double(shared) / Double(shorter)
        // Short greetings ("Hey, Sam") need a tighter match so "sounds good"
        // replies a few seconds apart are less likely to collapse.
        if longer >= 4 {
            return cover >= 0.62 && recall >= 0.75
        }
        return cover >= 0.9
    }

    /// Drop lines the microphone and system audio both transcribed.
    /// When one copy is You and the other isn't, keep the other — the mic usually heard the speakers.
    static func collapsingChannelEchoes(_ segments: [MeetingTranscriptSegment]) -> [MeetingTranscriptSegment] {
        let sorted = segments.sorted { $0.startOffset < $1.startOffset }
        var kept: [MeetingTranscriptSegment] = []
        for segment in sorted {
            guard let index = duplicateIndex(of: segment, in: kept) else {
                kept.append(segment)
                continue
            }
            let prior = kept[index]
            let incomingIsYou = segment.speaker.caseInsensitiveCompare("You") == .orderedSame
            let priorIsYou = prior.speaker.caseInsensitiveCompare("You") == .orderedSame
            var winner = (incomingIsYou != priorIsYou && priorIsYou) ? segment : prior
            let loser = winner.id == segment.id ? prior : segment
            if tokenCount(loser.text) > tokenCount(winner.text) {
                winner.text = loser.text
            }
            if winner.voiceID == nil {
                winner.voiceID = loser.voiceID
            }
            winner.startOffset = min(prior.startOffset, segment.startOffset)
            kept[index] = winner
        }
        return kept
    }

    private static func duplicateIndex(
        of segment: MeetingTranscriptSegment,
        in kept: [MeetingTranscriptSegment]
    ) -> Int? {
        for index in kept.indices.reversed() {
            let prior = kept[index]
            let count = max(tokenCount(segment.text), tokenCount(prior.text))
            let limit: TimeInterval = count < 5 ? 6 : 12
            if segment.startOffset - prior.startOffset > limit {
                return nil
            }
            if isNearDuplicate(segment.text, prior.text) {
                return index
            }
        }
        return nil
    }

    static func tokens(_ text: String) -> [String] {
        let parts = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        return Array(parts.filter { !$0.isEmpty }.prefix(80))
    }

    private static func longestCommonSubsequenceCount(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = [Int](repeating: 0, count: b.count + 1)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    current[j] = previous[j - 1] + 1
                } else {
                    current[j] = max(previous[j], current[j - 1])
                }
            }
            previous = current
            current = [Int](repeating: 0, count: b.count + 1)
        }
        return previous[b.count]
    }
}

extension MeetingTranscriptSegment {
    /// Keep acoustic voice ids when a later rewrite re-parses the transcript.
    static func restoringVoiceIdentity(
        refined: [MeetingTranscriptSegment],
        original: [MeetingTranscriptSegment]
    ) -> [MeetingTranscriptSegment] {
        guard !original.isEmpty else { return refined }
        var used = Set<UUID>()
        return refined.map { segment in
            var best: MeetingTranscriptSegment?
            var bestScore = 0.0
            for candidate in original where !used.contains(candidate.id) {
                let score = TranscriptSimilarity.similarity(segment.text, candidate.text)
                if score > bestScore {
                    bestScore = score
                    best = candidate
                }
            }
            guard let best, bestScore >= 0.45 else { return segment }
            used.insert(best.id)
            var copy = segment
            copy.voiceID = best.voiceID
            if best.voiceID != nil {
                copy.speaker = best.speaker
            }
            return copy
        }
    }
}
