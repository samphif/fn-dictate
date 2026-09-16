import Foundation

struct DictionaryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    /// Misheard / incorrect form (matched case-insensitively as a whole word).
    var incorrect: String
    /// Preferred spelling / display form.
    var correct: String
    var createdAt: Date
    var useCount: Int
    var isStarred: Bool

    init(
        id: UUID = UUID(),
        incorrect: String,
        correct: String,
        createdAt: Date = .now,
        useCount: Int = 0,
        isStarred: Bool = false
    ) {
        self.id = id
        self.incorrect = incorrect.trimmingCharacters(in: .whitespacesAndNewlines)
        self.correct = correct.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.useCount = useCount
        self.isStarred = isStarred
    }
}
