import Foundation
import Observation

@MainActor
@Observable
final class MeetingStore {
    var notes: [MeetingNote] = []

    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FnDictate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("meetings.json")
        load()
    }

    func upsert(_ note: MeetingNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.insert(note, at: 0)
        }
        notes.sort { $0.createdAt > $1.createdAt }
        save()
    }

    func updateTranscript(id: UUID, transcript: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].transcript = transcript
        // Live partials shouldn't thrash disk / agent export every frame.
    }

    func appendSegment(id: UUID, segment: MeetingTranscriptSegment) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].segments.append(segment)
        notes[index].transcript = notes[index].labeledTranscript
        save(exportAgent: false)
    }

    func updateCatchUp(id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].catchUp = text
        save(exportAgent: false)
    }

    func delete(_ note: MeetingNote) {
        notes.removeAll { $0.id == note.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        notes = (try? JSONDecoder().decode([MeetingNote].self, from: data)) ?? []
        MeetingAgentExport.refresh(notes: notes)
    }

    private func save(exportAgent: Bool = true) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: url, options: .atomic)
        if exportAgent {
            MeetingAgentExport.refresh(notes: notes)
        }
    }
}
