import Foundation

struct MeetingTranscriptSegment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// Seconds from meeting start.
    var startOffset: TimeInterval
    var text: String
    /// "You", a remembered voice, a calendar attendee, or "Others".
    var speaker: String
    /// Stable id for a remembered other-person voice. Nil for You, Others, and older notes.
    var voiceID: UUID?

    init(
        id: UUID = UUID(),
        startOffset: TimeInterval,
        text: String,
        speaker: String,
        voiceID: UUID? = nil
    ) {
        self.id = id
        self.startOffset = startOffset
        self.text = text
        self.speaker = speaker
        self.voiceID = voiceID
    }

    enum CodingKeys: String, CodingKey {
        case id, startOffset, text, speaker, voiceID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startOffset = try container.decode(TimeInterval.self, forKey: .startOffset)
        text = try container.decode(String.self, forKey: .text)
        speaker = try container.decode(String.self, forKey: .speaker)
        voiceID = try container.decodeIfPresent(UUID.self, forKey: .voiceID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startOffset, forKey: .startOffset)
        try container.encode(text, forKey: .text)
        try container.encode(speaker, forKey: .speaker)
        try container.encodeIfPresent(voiceID, forKey: .voiceID)
    }
}

/// Progress of on-device meeting note refinement (summary / action items / speakers).
enum MeetingProcessingState: String, Codable, Sendable, Equatable {
    /// Recording still in progress, or legacy note without status.
    case idle
    /// Apple Intelligence is generating structured notes.
    case processing
    /// Structured notes are ready.
    case complete
    /// Saved transcript, but summary/action items used a limited fallback — retry available.
    case incomplete
}

struct MeetingNote: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var endedAt: Date?
    var transcript: String
    var summary: String
    var decisions: [String]
    var actionItems: [String]
    var openQuestions: [String]
    var includeSystemAudio: Bool
    /// Live / finalized utterance chunks with coarse speaker labels.
    var segments: [MeetingTranscriptSegment]
    /// Attendee names from Calendar (when available).
    var attendees: [String]
    var calendarEventIdentifier: String?
    var calendarTitle: String?
    /// Pre-meeting context generated from calendar + past notes.
    var brief: String?
    /// Last mid-meeting catch-up summary (what you missed).
    var catchUp: String?
    /// Structured-notes pipeline status for UI indicators.
    var processingState: MeetingProcessingState
    /// Short status line shown while processing or when incomplete.
    var processingMessage: String?
    /// True when system-audio capture was requested but failed to start.
    var systemAudioCaptureFailed: Bool
    /// Detected call app at record start (Zoom / Teams / Google Meet / …).
    var sourceAppName: String?
    /// Bundle ID of the window that owned the call (desktop app or browser).
    var sourceAppBundleID: String?
    /// Window title / call detail captured at start (used for browser profile hints).
    var sourceDetail: String?
    /// Project this note is tagged to. Nil until matched or chosen.
    var projectID: UUID?
    /// Accessibility roster snapshot (best-effort participant display names).
    var participantRoster: [String]
    /// Manual speaker renames (from → to); re-applied after refine and never overwritten silently.
    var lockedSpeakerRenames: [String: String]
    /// Calendar 1:1 remote display name applied to the Others channel when set.
    var remoteOneOnOneName: String?

    init(
        id: UUID = UUID(),
        title: String = "Untitled meeting",
        createdAt: Date = .now,
        endedAt: Date? = nil,
        transcript: String = "",
        summary: String = "",
        decisions: [String] = [],
        actionItems: [String] = [],
        openQuestions: [String] = [],
        includeSystemAudio: Bool = false,
        segments: [MeetingTranscriptSegment] = [],
        attendees: [String] = [],
        calendarEventIdentifier: String? = nil,
        calendarTitle: String? = nil,
        brief: String? = nil,
        catchUp: String? = nil,
        processingState: MeetingProcessingState = .idle,
        processingMessage: String? = nil,
        systemAudioCaptureFailed: Bool = false,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        sourceDetail: String? = nil,
        projectID: UUID? = nil,
        participantRoster: [String] = [],
        lockedSpeakerRenames: [String: String] = [:],
        remoteOneOnOneName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.endedAt = endedAt
        self.transcript = transcript
        self.summary = summary
        self.decisions = decisions
        self.actionItems = actionItems
        self.openQuestions = openQuestions
        self.includeSystemAudio = includeSystemAudio
        self.segments = segments
        self.attendees = attendees
        self.calendarEventIdentifier = calendarEventIdentifier
        self.calendarTitle = calendarTitle
        self.brief = brief
        self.catchUp = catchUp
        self.processingState = processingState
        self.processingMessage = processingMessage
        self.systemAudioCaptureFailed = systemAudioCaptureFailed
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.sourceDetail = sourceDetail
        self.projectID = projectID
        self.participantRoster = participantRoster
        self.lockedSpeakerRenames = lockedSpeakerRenames
        self.remoteOneOnOneName = remoteOneOnOneName
    }

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, endedAt, transcript, summary
        case decisions, actionItems, openQuestions, includeSystemAudio
        case segments, attendees, calendarEventIdentifier, calendarTitle, brief, catchUp
        case processingState, processingMessage, systemAudioCaptureFailed
        case sourceAppName, sourceAppBundleID, sourceDetail, projectID
        case participantRoster, lockedSpeakerRenames, remoteOneOnOneName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        transcript = try c.decodeIfPresent(String.self, forKey: .transcript) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        decisions = try c.decodeIfPresent([String].self, forKey: .decisions) ?? []
        actionItems = try c.decodeIfPresent([String].self, forKey: .actionItems) ?? []
        openQuestions = try c.decodeIfPresent([String].self, forKey: .openQuestions) ?? []
        includeSystemAudio = try c.decodeIfPresent(Bool.self, forKey: .includeSystemAudio) ?? false
        segments = try c.decodeIfPresent([MeetingTranscriptSegment].self, forKey: .segments) ?? []
        attendees = try c.decodeIfPresent([String].self, forKey: .attendees) ?? []
        calendarEventIdentifier = try c.decodeIfPresent(String.self, forKey: .calendarEventIdentifier)
        calendarTitle = try c.decodeIfPresent(String.self, forKey: .calendarTitle)
        brief = try c.decodeIfPresent(String.self, forKey: .brief)
        catchUp = try c.decodeIfPresent(String.self, forKey: .catchUp)
        processingState = try c.decodeIfPresent(MeetingProcessingState.self, forKey: .processingState) ?? .idle
        processingMessage = try c.decodeIfPresent(String.self, forKey: .processingMessage)
        systemAudioCaptureFailed = try c.decodeIfPresent(Bool.self, forKey: .systemAudioCaptureFailed) ?? false
        sourceAppName = try c.decodeIfPresent(String.self, forKey: .sourceAppName)
        sourceAppBundleID = try c.decodeIfPresent(String.self, forKey: .sourceAppBundleID)
        sourceDetail = try c.decodeIfPresent(String.self, forKey: .sourceDetail)
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        participantRoster = try c.decodeIfPresent([String].self, forKey: .participantRoster) ?? []
        lockedSpeakerRenames = try c.decodeIfPresent([String: String].self, forKey: .lockedSpeakerRenames) ?? [:]
        remoteOneOnOneName = try c.decodeIfPresent(String.self, forKey: .remoteOneOnOneName)
    }

    /// Human-readable call source, e.g. "Zoom", "Teams", "Teams · Edge (Work)".
    var sourceDisplayLabel: String? {
        AppDisplayName.meetingSource(
            appName: sourceAppName,
            bundleID: sourceAppBundleID,
            detail: sourceDetail
        )
    }

    /// Recording length when `endedAt` is known; otherwise nil (still in progress / incomplete).
    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        let seconds = endedAt.timeIntervalSince(createdAt)
        return seconds > 0 ? seconds : nil
    }

    var formattedDuration: String? {
        guard let duration else { return nil }
        let totalSeconds = Int(duration.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes) min"
        }
        return "\(max(seconds, 1))s"
    }

    /// Prefer segment text; fall back to the flat transcript.
    var wordCount: Int {
        let body: String
        if !segments.isEmpty {
            body = segments.map(\.text).joined(separator: " ")
        } else {
            body = transcript
        }
        return body.split { $0.isWhitespace || $0.isNewline }.count
    }

    var formattedWordCount: String {
        let count = wordCount
        if count >= 1_000 {
            let k = Double(count) / 1_000.0
            return String(format: k >= 10 ? "%.0fk words" : "%.1fk words", k)
        }
        return "\(count) word\(count == 1 ? "" : "s")"
    }

    var labeledTranscript: String {
        if !segments.isEmpty {
            return segments
                .sorted { $0.startOffset < $1.startOffset }
                .map { "[\($0.speaker)] \($0.text)" }
                .joined(separator: "\n")
        }
        return transcript
    }

    func markdownExport(projectName: String? = nil, fallbackSource: String? = nil) -> String {
        var lines: [String] = [
            "# \(title)",
            "",
            "_Recorded \(createdAt.formatted(date: .abbreviated, time: .shortened))_",
            ""
        ]

        if let calendarTitle, !calendarTitle.isEmpty {
            lines.append("**Calendar:** \(calendarTitle)")
            lines.append("")
        }

        if let projectName, !projectName.isEmpty {
            lines.append("**Project:** \(projectName)")
            lines.append("")
        }

        if let source = sourceDisplayLabel ?? fallbackSource, !source.isEmpty {
            lines.append("**Source:** \(source)")
            lines.append("")
        }

        if !attendees.isEmpty {
            lines.append("**Attendees:** \(attendees.joined(separator: ", "))")
            lines.append("")
        }

        if !participantRoster.isEmpty {
            lines.append("**Participants (UI):** \(participantRoster.joined(separator: ", "))")
            lines.append("")
        }

        if let brief, !brief.isEmpty {
            lines.append("## Pre-meeting brief")
            lines.append(brief)
            lines.append("")
        }

        lines.append("## Summary")
        lines.append(summary.isEmpty ? "_No summary yet._" : summary)
        lines.append("")

        if !actionItems.isEmpty {
            lines.append("## Action items")
            lines.append(contentsOf: actionItems.map { raw in
                let done = ParsedActionItem.parse(raw).isDone
                let body = ParsedActionItem.strippingDoneMarker(raw)
                return "- [\(done ? "x" : " ")] \(body)"
            })
            lines.append("")
        }

        if !decisions.isEmpty {
            lines.append("## Key points")
            lines.append(contentsOf: decisions.map { "- \($0)" })
            lines.append("")
        }

        if !openQuestions.isEmpty {
            lines.append("## Open questions")
            lines.append(contentsOf: openQuestions.map { "- \($0)" })
            lines.append("")
        }

        if let catchUp, !catchUp.isEmpty {
            lines.append("## Catch-up")
            lines.append(catchUp)
            lines.append("")
        }

        lines.append("## Transcript")
        let body = labeledTranscript
        lines.append(body.isEmpty ? "_Empty transcript._" : body)
        lines.append("")
        return lines.joined(separator: "\n")
    }

    /// People who can own an action item: You, calendar attendees, project people, and named speakers.
    func actionItemAssigneeCandidates(including extra: [String] = []) -> [String] {
        var names: [String] = ["You"]
        for name in extra + attendees where !name.isEmpty {
            if !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                names.append(name)
            }
        }
        for speaker in segments.map(\.speaker) {
            let trimmed = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed.caseInsensitiveCompare("Others") != .orderedSame,
                  !VoiceProfile.isGeneric(trimmed),
                  !names.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame })
            else { continue }
            names.append(trimmed)
        }
        return names
    }
}

/// Parsed owner + task text for an action-item string (owners are often embedded inconsistently by the model).
struct ParsedActionItem: Equatable, Sendable {
    var task: String
    /// nil means unassigned / unspecified.
    var assignee: String?
    /// User checked this item off. Stored as a prefix so existing notes stay valid.
    var isDone: Bool = false

    static let unassignedLabel = "Unassigned"
    /// Leading marker peeled before owner/task parsing. Not shown in the UI.
    static let donePrefix = "☑ "

    var displayAssignee: String {
        assignee ?? Self.unassignedLabel
    }

    static func parse(_ raw: String) -> ParsedActionItem {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDone = consumeDoneMarker(from: &text)
        guard !text.isEmpty else {
            return ParsedActionItem(task: "", assignee: nil, isDone: isDone)
        }

        let tagged = peelTaggedOwner(from: &text)
        // "Leslie to create…" names who does the work. That wins over a wrong
        // [Sam] / (Owner: Sam) tag the model often copies from the previous item.
        let spoken = peelSpokenOwner(from: &text)
        return ParsedActionItem(task: text, assignee: spoken ?? tagged, isDone: isDone)
    }

    /// Stored text with the completion marker removed, wording otherwise unchanged.
    static func strippingDoneMarker(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = consumeDoneMarker(from: &text)
        return text
    }

    /// Toggle completion without rewriting assignee or task wording.
    static func setDone(_ raw: String, done: Bool) -> String {
        let body = strippingDoneMarker(raw)
        guard done, !body.isEmpty else { return body }
        return donePrefix + body
    }

    private static func consumeDoneMarker(from text: inout String) -> Bool {
        if text.hasPrefix(donePrefix) {
            text = String(text.dropFirst(donePrefix.count))
            return true
        }
        if text.hasPrefix("☑") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            return true
        }
        return false
    }

    /// (Owner: Sam), [Sam], or "Sam: …" prefixes. Returns nil when unassigned.
    private static func peelTaggedOwner(from text: inout String) -> String? {
        // Trailing punctuation is common: "(owner: Abby)."
        if let match = text.range(
            of: #"\s*\(\s*Owner\s*:\s*([^)]+?)\s*\)[.!?,;:]*\s*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let clause = String(text[match])
            let ownerRaw = clause.replacingOccurrences(
                of: #"^\s*\(\s*Owner\s*:\s*|\s*\)[.!?,;:]*\s*$"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            text = String(text[..<match.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedAssignee(ownerRaw)
        }

        if let match = text.range(of: #"^\[([^\]]+)\]\s*(?:to\s+)?"#, options: .regularExpression) {
            let bracketed = String(text[match])
            let name = bracketed
                .replacingOccurrences(of: #"^\[|\]\s*(?:to\s+)?$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            text = String(text[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedAssignee(name)
        }

        if let match = text.range(of: #"^([A-Za-z][A-Za-z0-9 .'-]{0,40}?):\s+"#, options: .regularExpression) {
            let prefix = String(text[match])
            let name = prefix
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let blocked = ["note", "action", "actions", "todo", "item", "summary", "decision", "question"]
            if !blocked.contains(name.lowercased()), name.split(separator: " ").count <= 3 {
                text = String(text[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return normalizedAssignee(name)
            }
        }

        return nil
    }

    /// Words that introduce an infinitive ("Need to…") and are not people.
    private static let nonPersonLeadIns: Set<String> = [
        "need", "needs", "remember", "remembers", "have", "has", "want", "wants",
        "going", "try", "tries", "plan", "plans", "continue", "continues", "be",
        "make", "makes", "please", "someone", "anyone", "everybody", "everyone",
        "somebody", "we", "they", "he", "she", "it", "us", "get", "gets", "help",
        "helps", "work", "works", "follow", "follows", "come", "comes", "start",
        "starts", "begin", "begins", "seem", "seems", "appear", "appears", "tend",
        "tends", "ought", "used", "able", "sure", "ready", "not", "the", "our",
        "your", "their", "his", "her", "my", "do", "does", "did", "also", "then",
        "next", "just", "still", "something", "nothing", "people", "let", "lets",
        "let's", "fail", "fails", "supposed", "about", "here", "there", "this",
        "that", "dont", "don't", "ask", "asks", "tell", "tells", "remind",
        "reminds", "email", "emails", "ping", "pings", "call", "calls", "text",
        "texts", "message", "messages", "notify", "notifies", "invite", "invites"
    ]

    /// "Leslie to create the sheet" → assignee Leslie, task "Create the sheet".
    private static func peelSpokenOwner(from text: inout String) -> String? {
        let pattern = #"^([A-Z][\p{L}'’.-]+(?:\s+[A-Z][\p{L}'’.-]+){0,2})\s+(?:is\s+going\s+to|is\s+to|needs\s+to|has\s+to|going\s+to|to|should|will|must)\s+(\S.*)$"#
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }

        let prefix = String(text[match])
        guard let split = prefix.range(
            of: #"\s+(?:is\s+going\s+to|is\s+to|needs\s+to|has\s+to|going\s+to|to|should|will|must)\s+"#,
            options: .regularExpression
        ) else { return nil }

        let name = String(prefix[..<split.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = String(prefix[split.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikePersonName(name), !remainder.isEmpty else { return nil }

        text = sentenceCase(remainder)
        return normalizedAssignee(name)
    }

    private static func looksLikePersonName(_ name: String) -> Bool {
        let words = name.split(separator: " ")
        guard !words.isEmpty, words.count <= 3 else { return false }
        let first = words[0].lowercased()
        if nonPersonLeadIns.contains(first) { return false }
        // Reject acronyms ("ASV to match") while keeping "Leslie" / "O'Brien".
        return name.contains(where: \.isLowercase)
    }

    private static func sentenceCase(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }

    static func compose(task: String, assignee: String?, done: Bool = false) -> String {
        let cleaned = task.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: String
        if let assignee, !assignee.isEmpty,
           assignee.caseInsensitiveCompare(unassignedLabel) != .orderedSame {
            body = "[\(assignee)] \(cleaned)"
        } else {
            body = cleaned
        }
        guard done, !body.isEmpty else { return body }
        return donePrefix + body
    }

    /// Name typed in the assignee field. "You" / "me" map to the local participant.
    static func assigneeName(typed raw: String) -> String? {
        let stripped = raw
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
        return normalizedAssignee(stripped)
    }

    private static func normalizedAssignee(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if ["unspecified", "unassigned", "none", "n/a", "na", "unknown", "tbd"].contains(lower) {
            return nil
        }
        if lower == "user" || lower == "you" || lower == "me" { return "You" }
        return trimmed
    }
}

/// Action items rolled up by assignee for denser UI (one header per person).
struct ActionItemGroup: Identifiable, Equatable, Sendable {
    /// Stable key: lowercased assignee, or a sentinel for unassigned.
    var id: String
    var assignee: String?
    /// Indices into the original `actionItems` array, in encounter order.
    var indices: [Int]

    var displayName: String { assignee ?? ParsedActionItem.unassignedLabel }
    var count: Int { indices.count }

    static let unassignedID = "__unassigned__"

    static func groups(from rawItems: [String]) -> [ActionItemGroup] {
        var order: [String] = []
        var buckets: [String: (assignee: String?, indices: [Int])] = [:]

        for (index, raw) in rawItems.enumerated() {
            let parsed = ParsedActionItem.parse(raw)
            let key = parsed.assignee.map { $0.lowercased() } ?? Self.unassignedID
            if buckets[key] == nil {
                buckets[key] = (parsed.assignee, [])
                order.append(key)
            }
            buckets[key]?.indices.append(index)
        }

        let sortedKeys = order.sorted { a, b in
            sortRank(a) < sortRank(b)
                || (sortRank(a) == sortRank(b) && displaySortKey(a, buckets: buckets)
                    .localizedCaseInsensitiveCompare(displaySortKey(b, buckets: buckets)) == .orderedAscending)
        }

        return sortedKeys.compactMap { key in
            guard let bucket = buckets[key] else { return nil }
            return ActionItemGroup(id: key, assignee: bucket.assignee, indices: bucket.indices)
        }
    }

    private static func sortRank(_ key: String) -> Int {
        if key == "you" { return 0 }
        if key == unassignedID { return 2 }
        return 1
    }

    private static func displaySortKey(
        _ key: String,
        buckets: [String: (assignee: String?, indices: [Int])]
    ) -> String {
        buckets[key]?.assignee ?? key
    }
}
