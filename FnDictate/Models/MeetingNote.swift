import Foundation

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
        includeSystemAudio: Bool = false
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
    }

    var markdownExport: String {
        var lines: [String] = [
            "# \(title)",
            "",
            "_Recorded \(createdAt.formatted(date: .abbreviated, time: .shortened))_",
            "",
            "## Summary",
            summary.isEmpty ? "_No summary yet._" : summary,
            ""
        ]

        if !decisions.isEmpty {
            lines.append("## Decisions")
            lines.append(contentsOf: decisions.map { "- \($0)" })
            lines.append("")
        }

        if !actionItems.isEmpty {
            lines.append("## Action items")
            lines.append(contentsOf: actionItems.map { "- [ ] \($0)" })
            lines.append("")
        }

        if !openQuestions.isEmpty {
            lines.append("## Open questions")
            lines.append(contentsOf: openQuestions.map { "- \($0)" })
            lines.append("")
        }

        lines.append("## Transcript")
        lines.append(transcript.isEmpty ? "_Empty transcript._" : transcript)
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
