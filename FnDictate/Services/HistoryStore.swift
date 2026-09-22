import Foundation
import Observation

@MainActor
@Observable
final class HistoryStore {
    var entries: [TranscriptEntry] = []

    private let maxEntries = 2000
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FnDictate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("history.json")
        load()
    }

    func add(_ entry: TranscriptEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
    }

    func update(_ entry: TranscriptEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index] = entry
        save()
    }

    func delete(_ entry: TranscriptEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clear() {
        entries = []
        save()
    }

    /// Recent unique words from dictation history for ASR contextual hints.
    func recentVocabulary(limit: Int = 40) -> [String] {
        var words: [String] = []
        var seen = Set<String>()
        let separators = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)

        for entry in entries.prefix(40) {
            for raw in entry.text.components(separatedBy: separators) {
                let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard word.count >= 3 else { continue }
                guard !ASRHintBuilder.isStopword(word) else { continue }
                let key = word.lowercased()
                guard seen.insert(key).inserted else { continue }
                words.append(word)
                if words.count >= limit { return words }
            }
        }
        return words
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        entries = (try? JSONDecoder().decode([TranscriptEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
