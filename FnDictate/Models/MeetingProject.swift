import Foundation

/// A client or project a meeting belongs to. Notes show its mark instead of a generic document icon.
struct MeetingProject: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    /// People who work on this project. Used as owner/speaker hints, not invented attendees.
    var people: [String]
    /// Phrases that auto-tag an untagged note (title, summary, calendar, transcript).
    var keywords: [String]
    /// Accent color as RRGGBB, used for the monogram when no custom icon is set.
    var colorHex: String
    /// Optional logo copied into Application Support. Nil means a letter monogram.
    var iconFileName: String?
    /// Shown when a note did not capture Zoom / Teams / Meet itself.
    var usualSource: String?

    init(
        id: UUID = UUID(),
        name: String,
        people: [String] = [],
        keywords: [String] = [],
        colorHex: String = ProjectPalette.defaultHex,
        iconFileName: String? = nil,
        usualSource: String? = nil
    ) {
        self.id = id
        self.name = name
        self.people = people
        self.keywords = keywords
        self.colorHex = colorHex
        self.iconFileName = iconFileName
        self.usualSource = usualSource
    }

    /// Two-letter mark, e.g. "Architectural Grille" → "AG".
    var monogram: String {
        let words = name
            .split(whereSeparator: { $0.isWhitespace })
            .prefix(2)
        let letters = words.compactMap { $0.first.map { String($0).uppercased() } }
        if letters.isEmpty { return "?" }
        return letters.joined()
    }

    enum CodingKeys: String, CodingKey {
        case id, name, people, keywords, colorHex, iconFileName, usualSource
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        people = try c.decodeIfPresent([String].self, forKey: .people) ?? []
        keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? ProjectPalette.defaultHex
        iconFileName = try c.decodeIfPresent(String.self, forKey: .iconFileName)
        usualSource = try c.decodeIfPresent(String.self, forKey: .usualSource)
    }
}

enum ProjectPalette {
    static let defaultHex = "C4784A"
    /// Distinct enough to tell projects apart on the notes list.
    static let hexes = [
        "C4784A", "3D6B8C", "5C6B4A", "8C4A6B",
        "6B5B8C", "4A7C74", "8C5040", "3E5A8C"
    ]

    static func nextHex(used: [String]) -> String {
        let usedLower = Set(used.map { $0.lowercased() })
        return hexes.first { !usedLower.contains($0.lowercased()) } ?? hexes[used.count % hexes.count]
    }
}

/// Rewrites action owners that the model invented, when a project has one known person
/// and that name never appears in the transcript.
enum ProjectAssignment {
    static func reconcileOwners(
        _ items: [String],
        transcript: String,
        people: [String]
    ) -> [String] {
        let known = people
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard known.count == 1, let person = known.first else { return items }
        let haystack = transcript.lowercased()

        return items.map { raw in
            let parsed = ParsedActionItem.parse(raw)
            guard let assignee = parsed.assignee else { return raw }
            if assignee.caseInsensitiveCompare("You") == .orderedSame { return raw }
            if known.contains(where: { $0.caseInsensitiveCompare(assignee) == .orderedSame }) {
                return raw
            }
            if haystack.contains(assignee.lowercased()) { return raw }
            return ParsedActionItem.compose(task: parsed.task, assignee: person, done: parsed.isDone)
        }
    }
}
