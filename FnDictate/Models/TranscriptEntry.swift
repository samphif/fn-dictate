import Foundation

struct TranscriptEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var text: String
    /// Original ASR text before user edits (used for dictionary learning).
    var originalText: String?
    let createdAt: Date
    var updatedAt: Date?
    let appName: String?
    /// Bundle ID of the app that was frontmost when dictating (for icon lookup).
    let appBundleID: String?

    init(
        id: UUID = UUID(),
        text: String,
        originalText: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date? = nil,
        appName: String? = nil,
        appBundleID: String? = nil
    ) {
        self.id = id
        self.text = text
        self.originalText = originalText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.appName = appName
        self.appBundleID = appBundleID
    }

    /// True when the user (or in-app correction watcher) edited this after paste.
    var isRevised: Bool {
        updatedAt != nil
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
