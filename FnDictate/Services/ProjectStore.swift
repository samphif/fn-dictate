import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ProjectStore {
    var projects: [MeetingProject] = []

    private let url: URL
    private let iconsDirectory: URL
    private let seededKey = "FnDictate.didSeedDefaultProjects"

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FnDictate", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("projects.json")
        iconsDirectory = dir.appendingPathComponent("ProjectIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        load()
        seedIfNeeded()
    }

    func project(id: UUID?) -> MeetingProject? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    func add(_ project: MeetingProject) {
        projects.append(project)
        save()
    }

    func update(_ project: MeetingProject) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
        save()
    }

    func delete(_ project: MeetingProject) {
        if let file = projects.first(where: { $0.id == project.id })?.iconFileName {
            try? FileManager.default.removeItem(at: iconsDirectory.appendingPathComponent(file))
        }
        projects.removeAll { $0.id == project.id }
        save()
    }

    func iconImage(for project: MeetingProject) -> NSImage? {
        guard let file = project.iconFileName else { return nil }
        return NSImage(contentsOf: iconsDirectory.appendingPathComponent(file))
    }

    /// Copies a user-picked logo into Application Support and points the project at it.
    func setIcon(from source: URL, for id: UUID) {
        guard var project = project(id: id),
              let image = NSImage(contentsOf: source)
        else { return }
        let fitted = Self.fitted(image, maxSide: 128)
        guard let tiff = fitted.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else { return }
        let file = "\(id.uuidString).png"
        do {
            try png.write(to: iconsDirectory.appendingPathComponent(file), options: .atomic)
        } catch {
            return
        }
        project.iconFileName = file
        update(project)
    }

    func clearIcon(for id: UUID) {
        guard var project = project(id: id) else { return }
        if let file = project.iconFileName {
            try? FileManager.default.removeItem(at: iconsDirectory.appendingPathComponent(file))
        }
        project.iconFileName = nil
        update(project)
    }

    /// Highest-scoring keyword match. Nil when nothing in the note hits a project phrase.
    func bestMatch(for note: MeetingNote) -> MeetingProject? {
        let haystack = [
            note.title,
            note.summary,
            note.calendarTitle ?? "",
            note.transcript
        ]
        .joined(separator: "\n")
        .lowercased()

        var best: (project: MeetingProject, score: Int)?
        for project in projects {
            var score = 0
            for keyword in project.keywords {
                let phrase = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard phrase.count >= 4, haystack.contains(phrase) else { continue }
                score += phrase.count
            }
            guard score > 0 else { continue }
            if best == nil || score > best!.score {
                best = (project, score)
            }
        }
        return best?.project
    }

    /// Reads the on-disk catalog. Used by the agent export, which does not hold this store.
    nonisolated static func loadSnapshot() -> [MeetingProject] {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("FnDictate", isDirectory: true)
            .appendingPathComponent("projects.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([MeetingProject].self, from: data)) ?? []
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        projects = (try? JSONDecoder().decode([MeetingProject].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: seededKey) }
        guard projects.isEmpty else { return }
        projects = [
            MeetingProject(
                name: "Architectural Grille",
                people: ["Jodi"],
                keywords: [
                    "architectural grille",
                    "architectural grill",
                    "archgrille",
                    "archgrill",
                    "pizza tracker"
                ],
                colorHex: "C4784A",
                usualSource: "Zoom"
            )
        ]
        save()
    }

    private static func fitted(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(maxSide / max(size.width, size.height), 1)
        if scale >= 1 { return image }
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let out = NSImage(size: newSize)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize))
        out.unlockFocus()
        return out
    }
}
