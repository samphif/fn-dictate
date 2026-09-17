import Foundation

struct MeetingTranscriptSegment: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// Seconds from meeting start.
    var startOffset: TimeInterval
    var text: String
    /// "You", a calendar attendee name, or "Others".
    var speaker: String

    init(
        id: UUID = UUID(),
        startOffset: TimeInterval,
        text: String,
        speaker: String
    ) {
        self.id = id
        self.startOffset = startOffset
        self.text = text
        self.speaker = speaker
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
        systemAudioCaptureFailed: Bool = false
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
    }

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, endedAt, transcript, summary
        case decisions, actionItems, openQuestions, includeSystemAudio
        case segments, attendees, calendarEventIdentifier, calendarTitle, brief, catchUp
        case processingState, processingMessage, systemAudioCaptureFailed
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

    var markdownExport: String {
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

        if !attendees.isEmpty {
            lines.append("**Attendees:** \(attendees.joined(separator: ", "))")
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
            lines.append(contentsOf: actionItems.map { "- [ ] \($0)" })
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
}
