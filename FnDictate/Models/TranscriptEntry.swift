import Foundation

struct TranscriptEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let text: String
    let createdAt: Date
    let appName: String?

    init(id: UUID = UUID(), text: String, createdAt: Date = .now, appName: String? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.appName = appName
    }
}
