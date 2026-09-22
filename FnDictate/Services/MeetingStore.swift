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

    /// Rename every segment with `from` speaker to `to`, lock the mapping against re-refine overwrite.
    func renameSpeaker(id: UUID, from: String, to: String) {
        let trimmedFrom = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFrom.isEmpty, !trimmedTo.isEmpty, trimmedFrom != trimmedTo else { return }
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

        notes[index].lockedSpeakerRenames[trimmedFrom] = trimmedTo
        // Also lock case-insensitive matches already present.
        for seg in notes[index].segments where seg.speaker.compare(trimmedFrom, options: .caseInsensitive) == .orderedSame {
            notes[index].lockedSpeakerRenames[seg.speaker] = trimmedTo
        }

        for i in notes[index].segments.indices {
            if notes[index].segments[i].speaker.compare(trimmedFrom, options: .caseInsensitive) == .orderedSame {
                notes[index].segments[i].speaker = trimmedTo
            }
        }
        notes[index].transcript = notes[index].labeledTranscript
        save()
    }

    func updateParticipantRoster(id: UUID, names: [String]) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].participantRoster = names
        save(exportAgent: false)
    }

    func updateSegment(
        meetingID: UUID,
        segmentID: UUID,
        text: String,
        speaker: String,
        voiceID: UUID?
    ) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == meetingID }),
              let segmentIndex = notes[noteIndex].segments.firstIndex(where: { $0.id == segmentID })
        else { return }
        notes[noteIndex].segments[segmentIndex].text = text
        notes[noteIndex].segments[segmentIndex].speaker = speaker
        notes[noteIndex].segments[segmentIndex].voiceID = voiceID
        notes[noteIndex].transcript = notes[noteIndex].labeledTranscript
        save(exportAgent: false)
    }

    func renameVoice(id: UUID, to name: String) {
        var changed = false
        for noteIndex in notes.indices {
            var noteChanged = false
            for segmentIndex in notes[noteIndex].segments.indices
            where notes[noteIndex].segments[segmentIndex].voiceID == id {
                notes[noteIndex].segments[segmentIndex].speaker = name
                noteChanged = true
            }
            if noteChanged {
                notes[noteIndex].transcript = notes[noteIndex].labeledTranscript
                changed = true
            }
        }
        if changed {
            save()
        }
    }

    func updateCatchUp(id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].catchUp = text
        save(exportAgent: false)
    }

    func updateActionItem(id: UUID, index: Int, text: String) {
        guard let noteIndex = notes.firstIndex(where: { $0.id == id }),
              notes[noteIndex].actionItems.indices.contains(index)
        else { return }
        notes[noteIndex].actionItems[index] = text
        save()
    }

    func delete(_ note: MeetingNote) {
        notes.removeAll { $0.id == note.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        notes = (try? JSONDecoder().decode([MeetingNote].self, from: data)) ?? []
        var changed = false
        for index in notes.indices {
            let collapsed = TranscriptSimilarity.collapsingChannelEchoes(notes[index].segments)
            if collapsed != notes[index].segments {
                notes[index].segments = collapsed
                notes[index].transcript = notes[index].labeledTranscript
                changed = true
            }
        }
        if changed {
            save()
        } else {
            MeetingAgentExport.refresh(notes: notes)
        }
    }

    private func save(exportAgent: Bool = true) {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: url, options: .atomic)
        if exportAgent {
            MeetingAgentExport.refresh(notes: notes)
        }
    }
}
