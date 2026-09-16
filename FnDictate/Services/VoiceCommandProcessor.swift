import Foundation

/// Phrase-based spoken edit commands applied after ASR and before cleanup.
enum VoiceCommandProcessor {
    static func process(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        if let literal = literalContent(from: trimmed) {
            return literal
        }

        var result = trimmed
        result = applyScratchCommands(result)
        result = replacePhrase(result, phrase: "new paragraph", with: "\n\n")
        result = replacePhrase(result, phrase: "new line", with: "\n")
        result = replaceWord(result, word: "period", with: ".")
        result = replaceWord(result, word: "comma", with: ",")
        result = replacePhrase(result, phrase: "question mark", with: "?")
        return collapseWhitespace(result)
    }

    /// "literal …" disables further command parsing for the rest of the utterance.
    private static func literalContent(from text: String) -> String? {
        let pattern = #"^(?i)literal\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let contentRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[contentRange])
    }

    private static func applyScratchCommands(_ text: String) -> String {
        var result = text
        let patterns = [#"\bscratch that\b"#, #"\bdelete that\b"#]

        while true {
            var found: Range<String.Index>?
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                    continue
                }
                let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
                guard let match = regex.firstMatch(in: result, options: [], range: nsRange),
                      let range = Range(match.range, in: result)
                else { continue }
                if found == nil || range.lowerBound < found!.lowerBound {
                    found = range
                }
            }
            guard let commandRange = found else { break }

            let before = String(result[..<commandRange.lowerBound])
            let after = String(result[commandRange.upperBound...])
            result = dropLastSentenceOrClause(before) + after
        }

        return result
    }

    private static func dropLastSentenceOrClause(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let sentenceEnds: [Character] = [".", "!", "?"]
        if let idx = trimmed.lastIndex(where: { sentenceEnds.contains($0) }) {
            let next = trimmed.index(after: idx)
            if next < trimmed.endIndex {
                return String(trimmed[..<next]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let comma = trimmed.lastIndex(of: ",") {
            return String(trimmed[...comma]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return ""
    }

    private static func replacePhrase(_ text: String, phrase: String, with replacement: String) -> String {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: replacement)
    }

    private static func replaceWord(_ text: String, word: String, with replacement: String) -> String {
        replacePhrase(text, phrase: word, with: replacement)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        var result = text
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        // Tidy spaces before punctuation introduced by spoken commands.
        result = result.replacingOccurrences(of: " .", with: ".")
        result = result.replacingOccurrences(of: " ,", with: ",")
        result = result.replacingOccurrences(of: " ?", with: "?")
        result = result.replacingOccurrences(of: " \n", with: "\n")
        result = result.replacingOccurrences(of: "\n ", with: "\n")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
