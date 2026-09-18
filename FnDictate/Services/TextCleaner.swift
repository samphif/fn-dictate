import AppKit
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum CleanupTone: String, Sendable, CaseIterable {
    case raw
    case light
    case polished

    var displayName: String {
        switch self {
        case .raw: return "Raw"
        case .light: return "Light"
        case .polished: return "Polished"
        }
    }

    var next: CleanupTone {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self) else { return .light }
        return all[(index + 1) % all.count]
    }

    static func forApp(bundleID: String?, name: String?) -> CleanupTone {
        let haystack = "\(bundleID ?? "") \(name ?? "")".lowercased()
        if haystack.contains("cursor") || haystack.contains("vscode") || haystack.contains("terminal")
            || haystack.contains("iterm") || haystack.contains("warp") || haystack.contains("xcode")
        {
            return .raw
        }
        // Email / chat can take Light→Medium style cleanup. Browsers stay Light —
        // Wispr Flow's default — so a Safari search box never gets a prose rewrite.
        if haystack.contains("mail") || haystack.contains("slack") || haystack.contains("outlook") {
            return .polished
        }
        return .light
    }
}

/// One row in Library → Formatting (curated default, history app, or orphan override).
struct FormattingProfile: Identifiable, Equatable, Sendable {
    /// Stable id: bundle ID, or a sentinel for the catch-all row.
    let id: String
    let name: String
    let bundleID: String?
    let tone: CleanupTone
    let isOverride: Bool
    /// Informational “everything else → Light” row; not editable.
    let isCatchAll: Bool

    var canEdit: Bool { !isCatchAll && bundleID != nil }
}

enum FormattingDefaults {
    /// Curated apps that mirror `CleanupTone.forApp` buckets (display + override targets).
    static let curatedApps: [(name: String, bundleID: String)] = [
        ("Cursor", "com.todesktop.230313mzl4w4u92"),
        ("VS Code", "com.microsoft.VSCode"),
        ("Terminal", "com.apple.Terminal"),
        ("iTerm", "com.googlecode.iterm2"),
        ("Warp", "dev.warp.Warp-Stable"),
        ("Xcode", "com.apple.dt.Xcode"),
        ("Edge", "com.microsoft.edgemac"),
        ("Chrome", "com.google.Chrome"),
        ("Safari", "com.apple.Safari"),
        ("Mail", "com.apple.mail"),
        ("Slack", "com.tinyspeck.slackmacgap"),
        ("Outlook", "com.microsoft.Outlook"),
    ]

    static let catchAllID = "fn-dictate.other-apps"
}

struct TextCleaner: Sendable {
    func clean(_ text: String, tone: CleanupTone) async -> String {
        let basic = Self.basicCleanup(text)
        guard tone != .raw else { return basic }
        // Wispr Flow skips Auto Cleanup on very short or very long text.
        guard CleanupFidelity.shouldUseModel(basic) else { return basic }

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if let smart = await smartCleanup(basic, tone: tone),
               CleanupFidelity.accept(smart, original: basic, tone: tone)
            {
                return smart
            }
        }
        #endif

        return basic
    }

    func summarizeMeeting(transcript: String) async -> MeetingNote {
        var note = MeetingNote(transcript: transcript)
        let basic = Self.basicCleanup(transcript)
        note.transcript = basic

        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if let structured = await smartMeetingSummary(basic) {
                note.summary = structured.summary
                note.decisions = structured.decisions
                note.actionItems = structured.actionItems
                note.openQuestions = structured.openQuestions
                note.title = structured.title.isEmpty ? "Meeting" : structured.title
                return note
            }
        }
        #endif

        note.summary = Self.fallbackSummary(from: basic)
        note.title = "Meeting \(Date().formatted(date: .abbreviated, time: .omitted))"
        return note
    }

    func prewarm() async {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            let model = SystemLanguageModel.default
            guard case .available = model.availability else { return }
            let session = LanguageModelSession(model: model)
            session.prewarm()
        }
        #endif
    }

    static func basicCleanup(_ text: String) -> String {
        var result = text
        let fillers = [
            #"\b(um|uh|erm|hmm|ah|eh)\b"#,
            #"\byou know\b"#,
            #"\blike\b(?=\s+\w+\s+like\b)"#
        ]
        for pattern in fillers {
            result = result.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        // Collapse runs of spaces/tabs only — keep newlines so spoken
        // "new paragraph" / "new line" (and model structure) survive.
        result = result.replacingOccurrences(of: #"[^\S\n]{2,}"#, with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"\b(\w+)( \1\b)+"#,
            with: "$1",
            options: [.regularExpression, .caseInsensitive]
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fallbackSummary(from transcript: String) -> String {
        let sentences = transcript
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let preview = sentences.prefix(3).joined(separator: ". ")
        if preview.isEmpty { return "No speech captured." }
        return preview + (preview.hasSuffix(".") ? "" : ".")
    }

    #if canImport(FoundationModels)
    @available(macOS 26, *)
    private func smartCleanup(_ text: String, tone: CleanupTone) async -> String? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }

        let instructions: String
        switch tone {
        case .raw:
            return text
        case .light:
            instructions = """
            Clean this dictation lightly (fillers + grammar only).

            Rules:
            - Remove filler words and obvious stutters / false starts.
            - Fix punctuation, capitalization, and spacing.
            - Keep the speaker's wording, names, and technical terms.
            - Preserve existing paragraph breaks.
            - Do not add information, examples, headings, lists, or structure.
            - Do not expand. Output must be the same length as the input, or shorter.
            - Return only the cleaned text.
            """
        case .polished:
            instructions = """
            Edit this spoken dictation for clarity and concision, ready to paste \
            into email or chat.

            Rules:
            - Remove fillers, resolve self-corrections, fix grammar and punctuation.
            - Preserve meaning, names, and technical terms. Prefer the speaker's words.
            - You may reword for clarity, but stay the same length or shorter. \
            Never pad, never add a sign-off, never add "further details."
            - Break into short paragraphs only where the thought actually shifts. \
            Do not invent sections, headings, or outline scaffolding.
            - Format a list only if the speaker used numbers or sequence words \
            (one/two, first/second). Use "- " at the start of each item. \
            Never invent a list the speaker did not say.
            - Plain text only: no markdown bold/italic, no headings, no HTML.
            - Return only the cleaned text.
            """
        }

        do {
            let session = LanguageModelSession(model: model, instructions: instructions)
            let response = try await session.respond(to: text)
            let cleaned = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }

    @available(macOS 26, *)
    private func smartMeetingSummary(_ transcript: String) async -> (
        title: String,
        summary: String,
        decisions: [String],
        actionItems: [String],
        openQuestions: [String]
    )? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }

        let prompt = """
        Summarize this meeting transcript for a personal note.

        Return exactly this structure:
        TITLE: <short title>
        SUMMARY: <1-3 paragraph overview>
        DECISIONS:
        - <decision>
        ACTIONS:
        - <action item>
        QUESTIONS:
        - <open question>

        Omit empty sections' bullets. Keep names and technical terms.
        Transcript:
        \(transcript)
        """

        do {
            let session = LanguageModelSession(
                model: model,
                instructions: "You write concise meeting notes. Follow the requested format exactly."
            )
            let response = try await session.respond(to: prompt)
            return Self.parseMeetingResponse(response.content)
        } catch {
            return nil
        }
    }

    private static func parseMeetingResponse(_ content: String) -> (
        title: String,
        summary: String,
        decisions: [String],
        actionItems: [String],
        openQuestions: [String]
    ) {
        var title = ""
        var summary = ""
        var decisions: [String] = []
        var actions: [String] = []
        var questions: [String] = []
        var section = ""

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.uppercased().hasPrefix("TITLE:") {
                title = line.drop(while: { $0 != ":" }).dropFirst().trimmingCharacters(in: .whitespaces)
                section = "title"
            } else if line.uppercased().hasPrefix("SUMMARY:") {
                summary = line.drop(while: { $0 != ":" }).dropFirst().trimmingCharacters(in: .whitespaces)
                section = "summary"
            } else if line.uppercased().hasPrefix("DECISIONS") {
                section = "decisions"
            } else if line.uppercased().hasPrefix("ACTIONS") {
                section = "actions"
            } else if line.uppercased().hasPrefix("QUESTIONS") {
                section = "questions"
            } else if line.hasPrefix("-") {
                let item = line.dropFirst().trimmingCharacters(in: .whitespaces)
                guard !item.isEmpty else { continue }
                switch section {
                case "decisions": decisions.append(item)
                case "actions": actions.append(item)
                case "questions": questions.append(item)
                default: break
                }
            } else if section == "summary", !line.isEmpty {
                summary = summary.isEmpty ? line : summary + "\n" + line
            }
        }

        return (title, summary, decisions, actions, questions)
    }
    #endif
}

/// Guards so cleanup stays a Wispr-style edit of what was said, never a generated essay.
enum CleanupFidelity {
    /// Below this, paste basic cleanup only (Wispr: skip Auto Cleanup on very short text).
    static let minModelWords = 8
    /// Above this, skip the model so long dictations don't get a hallucinated rewrite.
    static let maxModelWords = 800
    static let maxModelCharacters = 8_000

    static func shouldUseModel(_ text: String) -> Bool {
        let count = words(text).count
        guard count >= minModelWords, count <= maxModelWords else { return false }
        return text.count <= maxModelCharacters
    }

    /// Reject model output that invents content, lists, or a much longer rewrite.
    static func accept(_ cleaned: String, original: String, tone: CleanupTone) -> Bool {
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let originalWords = words(original)
        let cleanedWords = words(trimmed)
        guard !originalWords.isEmpty else { return true }

        let maxWords: Int
        switch tone {
        case .raw:
            return true
        case .light:
            maxWords = max(originalWords.count + 4, Int((Double(originalWords.count) * 1.25).rounded(.up)))
        case .polished:
            maxWords = max(originalWords.count + 12, Int((Double(originalWords.count) * 1.5).rounded(.up)))
        }
        if cleanedWords.count > maxWords { return false }
        if inventedList(original: original, cleaned: trimmed) { return false }

        let floor: Double = (tone == .light) ? 0.55 : 0.28
        return coverage(originalWords, in: cleanedWords) >= floor
    }

    static func words(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .filter { !$0.isEmpty }
    }

    private static func coverage(_ original: [String], in cleaned: [String]) -> Double {
        let cleanedLower = Set(cleaned.map { $0.lowercased() })
        let hits = original.filter { cleanedLower.contains($0.lowercased()) }.count
        return Double(hits) / Double(original.count)
    }

    /// Wispr only auto-lists from sequence words ("one… two…", "first… second…").
    private static func inventedList(original: String, cleaned: String) -> Bool {
        let listLines = cleaned.split(whereSeparator: \.isNewline).filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("- ") || t.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil
        }
        guard listLines.count >= 2 else { return false }
        if original.range(of: #"(?m)^\s*[-*•]\s"#, options: .regularExpression) != nil {
            return false
        }
        if original.range(of: #"(?m)^\s*\d+[.)]\s"#, options: .regularExpression) != nil {
            return false
        }
        let sequence = #"\b(one|two|three|four|five|six|seven|eight|nine|ten|first|second|third|fourth|fifth|next|lastly|finally|number\s+\d+)\b"#
        if original.range(of: sequence, options: [.regularExpression, .caseInsensitive]) != nil {
            return false
        }
        return true
    }
}
