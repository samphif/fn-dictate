import Foundation

/// Builds the phrase list passed to `SpeechAnalyzer` as `AnalysisContext.contextualStrings`.
///
/// Apple's dictation path treats these as *preferred* recognitions (up to ~100 phrases).
/// Feeding misheard forms or stopwords wastes that budget and can bias ASR toward the
/// wrong spelling — so we only send correct / likely-said terms.
enum ASRHintBuilder: Sendable {
    static let dictationLimit = 100
    static let meetingLimit = 100

    static func makeHints(
        preferredSpellings: [String],
        recentVocabulary: [String],
        attendees: [String] = [],
        contextTerms: [String] = [],
        limit: Int
    ) -> [String] {
        let people = normalize(attendees, droppingStopwords: false)
        let context = normalize(contextTerms, droppingStopwords: false)
        let preferred = normalize(preferredSpellings, droppingStopwords: false)
        let recent = normalize(recentVocabulary, droppingStopwords: true)
        return uniquedPreservingOrder(people + context + preferred + recent, limit: max(limit, 0))
    }

    static func isStopword(_ token: String) -> Bool {
        let folded = token
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
        return stopwords.contains(folded)
    }

    private static func normalize(_ items: [String], droppingStopwords: Bool) -> [String] {
        items.compactMap { raw in
            let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return nil }
            if droppingStopwords {
                let tokens = term.split { $0.isWhitespace || $0.isNewline }
                if tokens.count == 1, isStopword(String(tokens[0])) {
                    return nil
                }
            }
            return term
        }
    }

    private static func uniquedPreservingOrder(_ items: [String], limit: Int) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        result.reserveCapacity(min(items.count, limit))
        for item in items {
            let key = item.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(item)
            if result.count >= limit { break }
        }
        return result
    }

    /// High-frequency English function words that crowd out names and jargon in the 100-slot budget.
    private static let stopwords: Set<String> = [
        "the", "and", "for", "that", "this", "with", "from", "have", "has", "had",
        "was", "were", "are", "you", "your", "what", "when", "where", "which", "who",
        "will", "would", "could", "should", "they", "them", "their", "there", "then",
        "than", "just", "like", "some", "more", "very", "also", "into", "about",
        "because", "been", "being", "over", "after", "before", "other", "only",
        "come", "came", "get", "got", "can", "but", "not", "out", "all", "any",
        "our", "his", "her", "she", "him", "its", "it's", "i'm", "i've", "we're",
        "don't", "didn't", "can't", "won't", "that's", "there's", "here's",
        "yeah", "yep", "okay", "ok", "hey", "hi", "please", "thanks", "thank",
        "really", "actually", "basically", "maybe", "something", "someone",
        "going", "gonna", "want", "need", "make", "made", "know", "think",
        "said", "say", "see", "look", "good", "great", "well", "back", "here",
        "now", "how", "why", "too", "still", "even", "much", "many"
    ]
}
