import Foundation

/// Keeps a local agent-readable export of meetings (MCP / Cursor / Claude-friendly).
enum MeetingAgentExport {
    static var rootDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FnDictate", isDirectory: true)
            .appendingPathComponent("agent", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var meetingsDirectory: URL {
        let dir = rootDirectory.appendingPathComponent("meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func refresh(notes: [MeetingNote]) {
        let projects = ProjectStore.loadSnapshot()
        let names = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let fm = FileManager.default
        // Clear stale markdown files.
        if let existing = try? fm.contentsOfDirectory(at: meetingsDirectory, includingPropertiesForKeys: nil) {
            for url in existing where url.pathExtension == "md" {
                try? fm.removeItem(at: url)
            }
        }

        struct IndexEntry: Codable {
            let id: String
            let title: String
            let createdAt: Date
            let endedAt: Date?
            let attendees: [String]
            let source: String?
            let project: String?
            let path: String
            let summary: String
        }

        var index: [IndexEntry] = []
        let iso = ISO8601DateFormatter()

        for note in notes {
            let filename = "\(note.id.uuidString).md"
            let fileURL = meetingsDirectory.appendingPathComponent(filename)
            let project = note.projectID.flatMap { names[$0] }
            try? note.markdownExport(
                projectName: project?.name,
                fallbackSource: project?.usualSource
            ).write(to: fileURL, atomically: true, encoding: .utf8)
            index.append(
                IndexEntry(
                    id: note.id.uuidString,
                    title: note.title,
                    createdAt: note.createdAt,
                    endedAt: note.endedAt,
                    attendees: note.attendees,
                    source: note.sourceDisplayLabel ?? project?.usualSource,
                    project: project?.name,
                    path: "meetings/\(filename)",
                    summary: note.summary
                )
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(index) {
            try? data.write(to: rootDirectory.appendingPathComponent("index.json"), options: .atomic)
        }

        let readme = """
        # Fn Dictate agent export

        Local-first meeting notes for MCP / coding agents.

        - `index.json` — catalog of meetings
        - `meetings/<id>.md` — full note (summary, actions, labeled transcript)

        Generated: \(iso.string(from: .now))
        Path: \(rootDirectory.path)

        Example Cursor MCP (stdio file reader) can point tools at this folder.
        """
        try? readme.write(
            to: rootDirectory.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
    }
}
