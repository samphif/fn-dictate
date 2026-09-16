import Foundation
import Observation

@MainActor
@Observable
final class HistoryStore {
    var entries: [TranscriptEntry] = []

    private let maxEntries = 50
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

    func clear() {
        entries = []
        save()
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
