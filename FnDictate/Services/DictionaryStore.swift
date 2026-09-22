import Foundation
import Observation

@MainActor
@Observable
final class DictionaryStore {
    var entries: [DictionaryEntry] = []

    private let url: URL

    /// Common function/filler words that must never become dictionary replacements.
    /// Auto-learning from polish diffs was inventing poison like `to` → `You`.
    private static let unsafeLearnWords: Set<String> = [
        "a", "an", "and", "as", "at", "be", "but", "by", "do", "for", "from",
        "have", "i", "if", "in", "is", "it", "me", "my", "no", "not", "of",
        "on", "or", "so", "that", "the", "to", "uh", "um", "up", "we", "with",
        "you", "your",
    ]

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FnDictate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("dictionary.json")
        load()
    }

    var preferredSpellings: [String] {
        entries.map(\.correct)
    }

    func add(incorrect: String, correct: String, starred: Bool = false) {
        let bad = incorrect.trimmingCharacters(in: .whitespacesAndNewlines)
        let good = correct.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !good.isEmpty else { return }

        // Identical pair (or empty heard-as) is a boost-only preferred spelling.
        if bad.isEmpty || bad.caseInsensitiveCompare(good) == .orderedSame {
            addHintOnly(good, starred: starred)
            return
        }
        guard Self.isSafeCorrection(incorrect: bad, correct: good) else { return }

        if let index = entries.firstIndex(where: {
            !$0.incorrect.isEmpty && $0.incorrect.caseInsensitiveCompare(bad) == .orderedSame
        }) {
            entries[index].correct = good
            entries[index].isStarred = starred || entries[index].isStarred
        } else {
            entries.insert(
                DictionaryEntry(incorrect: bad, correct: good, isStarred: starred),
                at: 0
            )
        }
        sortEntries()
        save()
    }

    /// Adds a preferred spelling used as ASR / cleanup vocabulary without a replacement pair.
    private func addHintOnly(_ spelling: String, starred: Bool) {
        if let index = entries.firstIndex(where: {
            $0.correct.caseInsensitiveCompare(spelling) == .orderedSame
        }) {
            entries[index].isStarred = starred || entries[index].isStarred
            sortEntries()
            save()
            return
        }
        entries.insert(
            DictionaryEntry(incorrect: "", correct: spelling, isStarred: starred),
            at: 0
        )
        sortEntries()
        save()
    }

    func update(_ entry: DictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        guard Self.isSafeCorrection(incorrect: entry.incorrect, correct: entry.correct) else { return }
        entries[index] = entry
        sortEntries()
        save()
    }

    func delete(_ entry: DictionaryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func toggleStar(_ entry: DictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isStarred.toggle()
        sortEntries()
        save()
    }

    /// Preview word/phrase substitutions that `learn(from:to:)` would add.
    func previewCorrections(from original: String, to corrected: String) -> [(incorrect: String, correct: String)] {
        let before = Self.tokens(original)
        let after = Self.tokens(corrected)
        guard before != after else { return [] }

        var results: [(incorrect: String, correct: String)] = []
        for span in Self.mismatchedSpans(before: before, after: after) {
            let bad = span.incorrect.trimmingCharacters(in: .whitespacesAndNewlines)
            let good = span.correct.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bad.isEmpty, !good.isEmpty else { continue }
            guard bad.caseInsensitiveCompare(good) != .orderedSame else { continue }
            // Ignore huge rewrites — those aren't dictionary corrections.
            guard bad.count <= 80, good.count <= 80 else { continue }
            guard before.count <= 3 || bad.split(separator: " ").count <= 4 else { continue }
            guard Self.isSafeCorrection(incorrect: bad, correct: good) else { continue }
            results.append((bad, good))
        }
        return results
    }

    /// Rejects corrections that would rewrite everyday function words (e.g. `to` → `You`).
    static func isSafeCorrection(incorrect: String, correct: String) -> Bool {
        let badTokens = tokens(incorrect)
        let goodTokens = tokens(correct)
        guard !badTokens.isEmpty, !goodTokens.isEmpty else { return false }

        // Never learn a replacement whose source is only common words.
        if badTokens.allSatisfy({ unsafeLearnWords.contains($0.lowercased()) }) {
            return false
        }
        // Single-token common → anything is almost always an LCS false pair from polish.
        if badTokens.count == 1, unsafeLearnWords.contains(badTokens[0].lowercased()) {
            return false
        }
        return true
    }

    /// Word-level edits for UI (substitutions, deletions, and insertions).
    static func revisionSpans(from original: String, to revised: String) -> [(removed: String, added: String)] {
        let before = tokens(original)
        let after = tokens(revised)
        guard before != after else { return [] }

        return allMismatchedSpans(before: before, after: after).compactMap { span in
            let removed = span.incorrect.trimmingCharacters(in: .whitespacesAndNewlines)
            let added = span.correct.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !removed.isEmpty || !added.isEmpty else { return nil }
            if !removed.isEmpty, !added.isEmpty,
               removed.caseInsensitiveCompare(added) == .orderedSame
            {
                return nil
            }
            return (removed, added)
        }
    }

    /// Learns substitutions from an edited dictation (single words or short phrases).
    @discardableResult
    func learn(from original: String, to corrected: String) -> Int {
        let spans = previewCorrections(from: original, to: corrected)
        for span in spans {
            add(incorrect: span.incorrect, correct: span.correct)
        }
        return spans.count
    }

    func apply(to text: String) -> String {
        guard !entries.isEmpty, !text.isEmpty else { return text }

        let sorted = entries.sorted { $0.incorrect.count > $1.incorrect.count }
        var result = text
        var usedIDs: [UUID] = []

        for entry in sorted {
            guard !entry.incorrect.isEmpty else { continue }
            guard Self.isSafeCorrection(incorrect: entry.incorrect, correct: entry.correct) else {
                continue
            }
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: entry.incorrect))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = regex.matches(in: result, options: [], range: range)
            guard !matches.isEmpty else { continue }

            // Replace from the end so earlier ranges stay valid. Avoid `withTemplate`
            // so preferred spellings that contain `$` are not treated as backreferences.
            for match in matches.reversed() {
                guard let matchRange = Range(match.range, in: result) else { continue }
                result.replaceSubrange(matchRange, with: entry.correct)
            }
            usedIDs.append(entry.id)
        }

        if !usedIDs.isEmpty {
            for id in Set(usedIDs) {
                if let index = entries.firstIndex(where: { $0.id == id }) {
                    entries[index].useCount += 1
                }
            }
            save()
        }

        return result
    }

    /// LCS-backed span diff so "remy care" → "RemyCare" and unequal word counts still learn.
    /// Only paired substitutions (both sides non-empty) — used for dictionary learning.
    private static func mismatchedSpans(
        before: [String],
        after: [String]
    ) -> [(incorrect: String, correct: String)] {
        allMismatchedSpans(before: before, after: after).filter {
            !$0.incorrect.isEmpty && !$0.correct.isEmpty
        }
    }

    /// LCS-backed span diff including one-sided deletions and insertions.
    private static func allMismatchedSpans(
        before: [String],
        after: [String]
    ) -> [(incorrect: String, correct: String)] {
        let n = before.count
        let m = after.count
        if n == 0 && m == 0 { return [] }
        if n == 0 {
            return [(incorrect: "", correct: after.joined(separator: " "))]
        }
        if m == 0 {
            return [(incorrect: before.joined(separator: " "), correct: "")]
        }

        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n {
            for j in 1...m {
                if before[i - 1].caseInsensitiveCompare(after[j - 1]) == .orderedSame {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        var spans: [(incorrect: String, correct: String)] = []
        var badBuf: [String] = []
        var goodBuf: [String] = []

        func flush() {
            guard !badBuf.isEmpty || !goodBuf.isEmpty else { return }
            spans.append((
                badBuf.reversed().joined(separator: " "),
                goodBuf.reversed().joined(separator: " ")
            ))
            badBuf.removeAll()
            goodBuf.removeAll()
        }

        var i = n
        var j = m
        while i > 0 || j > 0 {
            if i > 0, j > 0, before[i - 1].caseInsensitiveCompare(after[j - 1]) == .orderedSame {
                flush()
                i -= 1
                j -= 1
            } else if j > 0, i == 0 || dp[i][j - 1] >= dp[i - 1][j] {
                goodBuf.append(after[j - 1])
                j -= 1
            } else if i > 0 {
                badBuf.append(before[i - 1])
                i -= 1
            }
        }
        flush()
        return spans
    }

    private func sortEntries() {
        entries.sort {
            if $0.isStarred != $1.isStarred { return $0.isStarred && !$1.isStarred }
            if $0.useCount != $1.useCount { return $0.useCount > $1.useCount }
            return $0.createdAt > $1.createdAt
        }
    }

    private static func tokens(_ text: String) -> [String] {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { !$0.isEmpty }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        entries = (try? JSONDecoder().decode([DictionaryEntry].self, from: data)) ?? []
        purgeUnsafeEntries()
        sortEntries()
    }

    /// Drop poisoned auto-learns like `to` → `You` that slipped in from polish diffs.
    private func purgeUnsafeEntries() {
        let before = entries.count
        entries.removeAll {
            !Self.isSafeCorrection(incorrect: $0.incorrect, correct: $0.correct)
        }
        if entries.count != before {
            save()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
