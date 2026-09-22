import Foundation

/// Deterministic speaker-label cleanup after refine (no paid APIs, no acoustic clustering).
/// Fixes over-split Voice N / casing duplicates by merging toward roster + calendar names.
enum SpeakerLabelNormalizer {
    struct IdentityHints: Sendable {
        var calendarAttendees: [String] = []
        var rosterNames: [String] = []
        /// Manual from→to renames; applied last and win over auto merges.
        var lockedRenames: [String: String] = [:]
        /// Preferred display name for the remote channel (calendar 1:1).
        var remoteOneOnOneName: String? = nil
    }

    /// Normalize segment speakers: casing merge, Voice/Speaker N collapse, canonical names.
    static func normalize(
        segments: [MeetingTranscriptSegment],
        hints: IdentityHints
    ) -> [MeetingTranscriptSegment] {
        guard !segments.isEmpty else { return segments }

        let preferred = preferredSpellings(hints: hints)
        let canonicalMap = buildCanonicalMap(speakers: segments.map(\.speaker), preferred: preferred)

        var result = segments.map { seg -> MeetingTranscriptSegment in
            var copy = seg
            copy.speaker = canonicalMap[seg.speaker] ?? canonicalizeToken(seg.speaker, preferred: preferred)
            return copy
        }

        result = collapseAnonymousVoices(segments: result, preferred: preferred, remoteOneOnOne: hints.remoteOneOnOneName)
        result = applyLockedRenames(segments: result, locked: hints.lockedRenames)
        return result
    }

    /// Same as `normalize` but also rewrites a flat labeled transcript body when present.
    static func normalizeNoteFields(
        segments: [MeetingTranscriptSegment],
        transcript: String,
        hints: IdentityHints
    ) -> (segments: [MeetingTranscriptSegment], transcript: String) {
        let normalized = normalize(segments: segments, hints: hints)
        let body: String
        if !normalized.isEmpty {
            body = normalized
                .sorted { $0.startOffset < $1.startOffset }
                .map { "[\($0.speaker)] \($0.text)" }
                .joined(separator: "\n")
        } else {
            body = rewriteLabeledTranscript(transcript, hints: hints)
        }
        return (normalized, body)
    }

    // MARK: - Canonical spelling

    private static func preferredSpellings(hints: IdentityHints) -> [String] {
        var list: [String] = ["You"]
        if let remote = hints.remoteOneOnOneName, !remote.isEmpty {
            list.append(remote)
        }
        list.append(contentsOf: hints.calendarAttendees)
        list.append(contentsOf: hints.rosterNames)
        // Prefer first occurrence as canonical; uniqued case-insensitively.
        var seen = Set<String>()
        var out: [String] = []
        for name in list {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                out.append(trimmed)
            }
        }
        return out
    }

    private static func buildCanonicalMap(
        speakers: [String],
        preferred: [String]
    ) -> [String: String] {
        var groups: [String: [String]] = [:]
        for speaker in speakers {
            let key = foldKey(speaker)
            groups[key, default: []].append(speaker)
        }

        var map: [String: String] = [:]
        for (key, variants) in groups {
            let canonical = pickCanonical(key: key, variants: variants, preferred: preferred)
            for v in variants {
                map[v] = canonical
            }
        }
        return map
    }

    private static func pickCanonical(key: String, variants: [String], preferred: [String]) -> String {
        if key == "you" { return "You" }
        if key == "others" || key == "them" || key == "other" { return "Others" }

        if let hit = preferred.first(where: { $0.lowercased() == key }) {
            return hit
        }

        // Prefer the most common casing among variants; break ties with Title Case-ish first.
        var counts: [String: Int] = [:]
        for v in variants {
            counts[v, default: 0] += 1
        }
        if let best = counts.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        })?.key {
            // Prefer a variant that starts with uppercase if tied counts already handled.
            if best.first?.isLowercase == true,
               let titled = variants.first(where: { $0.first?.isUppercase == true })
            {
                return titled
            }
            return best
        }
        return variants[0]
    }

    private static func canonicalizeToken(_ speaker: String, preferred: [String]) -> String {
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = foldKey(trimmed)
        if key == "you" { return "You" }
        if key == "others" || key == "them" || key == "other" { return "Others" }
        if let hit = preferred.first(where: { $0.lowercased() == key }) {
            return hit
        }
        if isAnonymousVoiceLabel(trimmed) {
            return trimmed
        }
        return trimmed
    }

    private static func foldKey(_ speaker: String) -> String {
        speaker.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Voice / Speaker N collapse

    /// Anonymous labels like "Voice 3", "Speaker 12", "speaker-1".
    static func isAnonymousVoiceLabel(_ speaker: String) -> Bool {
        let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "others" || lower == "you" { return false }
        // Voice 1, Speaker 2, Speaker N, voice-3
        let pattern = #"^(voice|speaker)\s*[-_]?\s*\d+$"#
        return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func collapseAnonymousVoices(
        segments: [MeetingTranscriptSegment],
        preferred: [String],
        remoteOneOnOne: String?
    ) -> [MeetingTranscriptSegment] {
        let anonymous = Set(
            segments.map(\.speaker).filter { isAnonymousVoiceLabel($0) }
        )
        guard !anonymous.isEmpty else { return segments }

        // 1:1 calendar: all anonymous remote → that one person.
        if let remote = remoteOneOnOne,
           !remote.isEmpty,
           preferred.filter({ $0 != "You" }).count <= 1
        {
            return segments.map { seg in
                guard isAnonymousVoiceLabel(seg.speaker) else { return seg }
                var copy = seg
                copy.speaker = remote
                return copy
            }
        }

        // Without acoustic clustering we cannot responsibly keep Voice 1…N as distinct people.
        // Merge every anonymous label into a single Others bucket (roster/calendar names stay).
        return segments.map { seg in
            guard isAnonymousVoiceLabel(seg.speaker) else { return seg }
            var copy = seg
            copy.speaker = "Others"
            return copy
        }
    }

    private static func applyLockedRenames(
        segments: [MeetingTranscriptSegment],
        locked: [String: String]
    ) -> [MeetingTranscriptSegment] {
        guard !locked.isEmpty else { return segments }
        // Case-insensitive lookup for from-keys.
        var folded: [String: String] = [:]
        for (from, to) in locked {
            let f = from.trimmingCharacters(in: .whitespacesAndNewlines)
            let t = to.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !f.isEmpty, !t.isEmpty else { continue }
            folded[f.lowercased()] = t
        }
        guard !folded.isEmpty else { return segments }

        return segments.map { seg in
            if let to = folded[seg.speaker.lowercased()] {
                var copy = seg
                copy.speaker = to
                return copy
            }
            return seg
        }
    }

    private static func rewriteLabeledTranscript(_ transcript: String, hints: IdentityHints) -> String {
        let lines = transcript.components(separatedBy: .newlines)
        var fakeSegments: [MeetingTranscriptSegment] = []
        var offset: TimeInterval = 0
        var passthrough: [(Int, String)] = []

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("["),
                  let close = trimmed.firstIndex(of: "]")
            else {
                passthrough.append((idx, line))
                continue
            }
            let speaker = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let text = String(trimmed[trimmed.index(after: close)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if speaker.isEmpty || text.isEmpty {
                passthrough.append((idx, line))
                continue
            }
            fakeSegments.append(
                MeetingTranscriptSegment(startOffset: offset, text: text, speaker: speaker)
            )
            offset += 1
        }

        if fakeSegments.isEmpty { return transcript }
        let normalized = normalize(segments: fakeSegments, hints: hints)
        // Rebuild: prefer normalized labeled lines in order; keep non-labeled passthrough rare.
        return normalized.map { "[\($0.speaker)] \($0.text)" }.joined(separator: "\n")
    }
}
