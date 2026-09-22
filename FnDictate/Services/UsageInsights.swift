import Foundation

enum DictationAppCategory: String, CaseIterable, Identifiable, Sendable {
    case aiPrompts
    case workMessages
    case personalMessages
    case emails
    case documents
    case otherTasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .aiPrompts: return "AI prompts"
        case .workMessages: return "Work messages"
        case .personalMessages: return "Personal messages"
        case .emails: return "Emails"
        case .documents: return "Documents"
        case .otherTasks: return "Other tasks"
        }
    }

    var icon: String {
        switch self {
        case .aiPrompts: return "sparkles"
        case .workMessages: return "briefcase"
        case .personalMessages: return "message"
        case .emails: return "envelope"
        case .documents: return "doc"
        case .otherTasks: return "infinity"
        }
    }

    static func classify(bundleID: String?, appName: String?) -> DictationAppCategory {
        let haystack = "\(bundleID ?? "") \(appName ?? "")".lowercased()
        if matches(haystack, Self.aiTokens) { return .aiPrompts }
        if matches(haystack, Self.workTokens) { return .workMessages }
        if matches(haystack, Self.personalTokens) { return .personalMessages }
        if matches(haystack, Self.emailTokens) { return .emails }
        if matches(haystack, Self.documentTokens) { return .documents }
        return .otherTasks
    }

    private static func matches(_ haystack: String, _ tokens: [String]) -> Bool {
        tokens.contains { haystack.contains($0) }
    }

    private static let aiTokens = [
        "cursor", "vscode", "visual studio code", "com.microsoft.vscode",
        "xcode", "com.apple.dt.xcode", "warp", "iterm", "terminal",
        "com.apple.terminal", "chatgpt", "openai", "claude", "anthropic",
        "copilot", "windsurf", "zed", "sublime", "com.todesktop", "grok",
    ]
    private static let workTokens = [
        "slack", "tinyspeck", "teams", "linear", "com.linear",
    ]
    private static let personalTokens = [
        "messages", "mobilesms", "whatsapp", "telegram", "signal", "imessage",
    ]
    private static let emailTokens = [
        "mail", "outlook", "spark", "superhuman", "airmail",
    ]
    private static let documentTokens = [
        "word", "pages", "notes", "textedit", "obsidian", "notion", "craft", "bear",
        "paper", "keynote", "excel", "numbers", "powerpoint",
    ]
}

struct UsageAppRow: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let bundleID: String?
    let wordCount: Int
    let dictationCount: Int
    let category: DictationAppCategory
}

struct UsageCategoryRow: Identifiable, Sendable, Equatable {
    var id: DictationAppCategory { category }
    let category: DictationAppCategory
    let wordCount: Int
    let dictationCount: Int
    let fraction: Double
}

struct UsageDay: Sendable, Equatable {
    let date: Date
    let wordCount: Int
    let dictationCount: Int
}

struct UsageInsights: Sendable, Equatable {
    let totalWords: Int
    let dictationCount: Int
    let uniqueAppCount: Int
    let wordsCorrected: Int
    let dictionaryFixes: Int
    let currentStreak: Int
    let longestStreak: Int
    let categories: [UsageCategoryRow]
    let apps: [UsageAppRow]
    let days: [Date: UsageDay]
    let catchphrase: String?
    let mostUsedWord: String?
    let peakWeekday: Int?
    let peakHour: Int?
    let peakAppName: String?

    var totalFixes: Int { wordsCorrected + dictionaryFixes }

    var formattedWordCount: String {
        Self.compactCount(totalWords)
    }

    var wordMilestone: String? {
        // Rough page ≈ 250 words; chapter ≈ 5,000. Factual scale, not invented copy.
        if totalWords >= 5_000 {
            let chapters = totalWords / 5_000
            return chapters == 1
                ? "You've written about a book chapter."
                : "You've written about \(chapters) book chapters."
        }
        if totalWords >= 250 {
            let pages = max(1, totalWords / 250)
            return pages == 1
                ? "You've written about a page."
                : "You've written about \(pages) pages."
        }
        return nil
    }

    func peakTimeLabel(calendar: Calendar = .current) -> String? {
        guard let weekday = peakWeekday, let hour = peakHour,
              weekday >= 1, weekday <= 7
        else { return nil }
        let dayName = calendar.weekdaySymbols[weekday - 1]
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "a.m." : "p.m."
        return "\(dayName) at \(hour12) \(suffix)"
    }

    static func compactCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        }
        if count >= 1_000 {
            let k = Double(count) / 1_000.0
            return String(format: k >= 10 ? "%.0fK" : "%.1fK", k)
        }
        return grouped(count)
    }

    static func grouped(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    @MainActor
    static func from(entries: [TranscriptEntry], dictionary: [DictionaryEntry]) -> UsageInsights {
        guard !entries.isEmpty else {
            return UsageInsights(
                totalWords: 0,
                dictationCount: 0,
                uniqueAppCount: 0,
                wordsCorrected: 0,
                dictionaryFixes: dictionary.reduce(0) { $0 + $1.useCount },
                currentStreak: 0,
                longestStreak: 0,
                categories: DictationAppCategory.allCases.map {
                    UsageCategoryRow(category: $0, wordCount: 0, dictationCount: 0, fraction: 0)
                },
                apps: [],
                days: [:],
                catchphrase: nil,
                mostUsedWord: nil,
                peakWeekday: nil,
                peakHour: nil,
                peakAppName: nil
            )
        }

        let calendar = Calendar.current
        var totalWords = 0
        var wordsCorrected = 0
        var appTotals: [String: UsageAppRow] = [:]
        var categoryWords: [DictationAppCategory: Int] = [:]
        var categoryCounts: [DictationAppCategory: Int] = [:]
        var dayWords: [Date: Int] = [:]
        var dayCounts: [Date: Int] = [:]
        var hourWords: [String: Int] = [:]
        var hourApp: [String: [String: Int]] = [:]

        for entry in entries {
            let words = entry.wordCount
            totalWords += words
            wordsCorrected += Self.correctedWords(in: entry)

            let category = DictationAppCategory.classify(
                bundleID: entry.appBundleID,
                appName: entry.appName
            )
            categoryWords[category, default: 0] += words
            categoryCounts[category, default: 0] += 1

            let name = Self.displayName(appName: entry.appName, bundleID: entry.appBundleID)
            let key = name.lowercased()
            if let row = appTotals[key] {
                appTotals[key] = UsageAppRow(
                    id: key,
                    name: row.name,
                    bundleID: row.bundleID ?? entry.appBundleID,
                    wordCount: row.wordCount + words,
                    dictationCount: row.dictationCount + 1,
                    category: row.category
                )
            } else {
                appTotals[key] = UsageAppRow(
                    id: key,
                    name: name,
                    bundleID: entry.appBundleID,
                    wordCount: words,
                    dictationCount: 1,
                    category: category
                )
            }

            let day = calendar.startOfDay(for: entry.createdAt)
            dayWords[day, default: 0] += words
            dayCounts[day, default: 0] += 1

            let weekday = calendar.component(.weekday, from: entry.createdAt)
            let hour = calendar.component(.hour, from: entry.createdAt)
            let slot = "\(weekday)-\(hour)"
            hourWords[slot, default: 0] += words
            hourApp[slot, default: [:]][name, default: 0] += words
        }

        let apps = appTotals.values.sorted {
            if $0.wordCount != $1.wordCount { return $0.wordCount > $1.wordCount }
            return $0.dictationCount > $1.dictationCount
        }

        let categories = DictationAppCategory.allCases.map { category in
            let words = categoryWords[category] ?? 0
            let fraction = totalWords == 0 ? 0 : Double(words) / Double(totalWords)
            return UsageCategoryRow(
                category: category,
                wordCount: words,
                dictationCount: categoryCounts[category] ?? 0,
                fraction: fraction
            )
        }
        .sorted {
            if $0.wordCount != $1.wordCount { return $0.wordCount > $1.wordCount }
            return $0.category.title < $1.category.title
        }

        let days: [Date: UsageDay] = Dictionary(uniqueKeysWithValues: dayCounts.keys.map { date in
            (
                date,
                UsageDay(
                    date: date,
                    wordCount: dayWords[date] ?? 0,
                    dictationCount: dayCounts[date] ?? 0
                )
            )
        })

        let streaks = Self.streaks(days: Set(dayCounts.keys), calendar: calendar)
        let phrases = Self.voicePhrases(from: entries)
        let peak = hourWords.max(by: { $0.value < $1.value })
        var peakWeekday: Int?
        var peakHour: Int?
        var peakAppName: String?
        if let slot = peak?.key {
            let parts = slot.split(separator: "-")
            if parts.count == 2 {
                peakWeekday = Int(parts[0])
                peakHour = Int(parts[1])
            }
            peakAppName = hourApp[slot]?.max(by: { $0.value < $1.value })?.key
        }

        return UsageInsights(
            totalWords: totalWords,
            dictationCount: entries.count,
            uniqueAppCount: appTotals.count,
            wordsCorrected: wordsCorrected,
            dictionaryFixes: dictionary.reduce(0) { $0 + $1.useCount },
            currentStreak: streaks.current,
            longestStreak: streaks.longest,
            categories: categories,
            apps: apps,
            days: days,
            catchphrase: phrases.catchphrase,
            mostUsedWord: phrases.mostUsedWord,
            peakWeekday: peakWeekday,
            peakHour: peakHour,
            peakAppName: peakAppName
        )
    }

    /// One row per app. Entries saved with and without a bundle ID used to split Cursor in two.
    private static func displayName(appName: String?, bundleID: String?) -> String {
        let short = AppDisplayName.short(name: appName, bundleID: bundleID)
        return short == "Unknown" ? "No app" : short
    }

    static func currentStreakDays(from days: Set<Date>, calendar: Calendar = .current) -> Set<Date> {
        guard !days.isEmpty else { return [] }
        var cursor = calendar.startOfDay(for: .now)
        if !days.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  days.contains(yesterday)
            else { return [] }
            cursor = yesterday
        }
        var streak: Set<Date> = []
        while days.contains(cursor) {
            streak.insert(cursor)
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    private static func streaks(days: Set<Date>, calendar: Calendar) -> (current: Int, longest: Int) {
        let current = currentStreakDays(from: days, calendar: calendar).count
        guard !days.isEmpty else { return (0, 0) }
        let sorted = days.sorted()
        var longest = 1
        var run = 1
        for index in 1..<sorted.count {
            let gap = calendar.dateComponents([.day], from: sorted[index - 1], to: sorted[index]).day ?? 0
            if gap == 1 {
                run += 1
                longest = max(longest, run)
            } else {
                run = 1
            }
        }
        return (current, max(longest, current))
    }

    @MainActor
    private static func correctedWords(in entry: TranscriptEntry) -> Int {
        guard let original = entry.originalText,
              original != entry.text
        else { return 0 }
        return DictionaryStore.revisionSpans(from: original, to: entry.text).reduce(0) { partial, span in
            let removed = span.removed.split { $0.isWhitespace || $0.isNewline }.count
            let added = span.added.split { $0.isWhitespace || $0.isNewline }.count
            return partial + max(removed, added)
        }
    }

    private static let skipWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "can", "do",
        "for", "from", "get", "got", "had", "has", "have", "i", "if", "in",
        "is", "it", "it's", "its", "just", "like", "me", "my", "no", "not",
        "of", "oh", "ok", "okay", "on", "or", "so", "that", "the", "then",
        "there", "this", "to", "uh", "um", "up", "we", "was", "with", "you",
        "your",
    ]

    private static func voicePhrases(from entries: [TranscriptEntry]) -> (catchphrase: String?, mostUsedWord: String?) {
        var words: [String: Int] = [:]
        var grams: [String: Int] = [:]
        let separators = CharacterSet.alphanumerics.inverted

        for entry in entries {
            let tokens = entry.text
                .lowercased()
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 2 }
            for token in tokens {
                words[token, default: 0] += 1
            }
            if tokens.count >= 3 {
                for index in 0..<(tokens.count - 2) {
                    let gram = [tokens[index], tokens[index + 1], tokens[index + 2]].joined(separator: " ")
                    grams[gram, default: 0] += 1
                }
            }
        }

        let mostUsedWord = words
            .filter { !skipWords.contains($0.key) }
            .max { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                return lhs.key > rhs.key
            }?
            .key

        let catchphrase = grams
            .filter { $0.value >= 3 }
            .filter { phrase in
                let parts = phrase.key.split(separator: " ").map(String.init)
                return !parts.allSatisfy { skipWords.contains($0) }
            }
            .max { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                return lhs.key.count < rhs.key.count
            }?
            .key

        return (catchphrase, mostUsedWord)
    }
}
