import Foundation

// PromptCamCore is platform-independent by contract: Foundation only.
// No SwiftUI, UIKit, AVFoundation, SwiftData, Photos or StoreKit.
// Persistence of these value types is the iOS layer's job (see
// Sources/PromptCamiOS/Persistence).

/// One interview question.
public struct QuestionModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: UUID
    public var text: String

    public init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }

    /// Whether this question is usable. A question of only whitespace would
    /// render as a blank subject screen, which is worse than no question.
    public var isValid: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// An ordered list of interview questions.
///
/// Order is the array order. There is no separate `order` field to drift out of
/// sync — the persistence layer is responsible for writing an index and
/// restoring this order exactly.
public struct DeckModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var questions: [QuestionModel]
    public let createdAt: Date
    public var updatedAt: Date
    /// Marks the deck PromptCam ships with.
    public var isSample: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        questions: [QuestionModel] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isSample: Bool = false
    ) {
        self.id = id
        self.name = name
        self.questions = questions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isSample = isSample
    }

    public var questionCount: Int { questions.count }

    /// The question texts handed to a session.
    ///
    /// Invalid (blank) questions are filtered out so a running interview can
    /// never display an empty prompt to the subject.
    public var sessionQuestionTexts: [String] {
        questions.filter(\.isValid).map(\.trimmedText)
    }

    /// A deck with no usable question cannot start an interview.
    public var isRecordable: Bool { !sessionQuestionTexts.isEmpty }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled deck" : trimmed
    }

    // MARK: - Editing
    //
    // Mutations live on the model so the same rules apply whether the caller is
    // the UI, a test, or a future import feature.

    public mutating func addQuestion(_ text: String, now: Date = Date()) {
        questions.append(QuestionModel(text: text))
        updatedAt = now
    }

    public mutating func updateQuestion(id: UUID, text: String, now: Date = Date()) {
        guard let index = questions.firstIndex(where: { $0.id == id }) else { return }
        questions[index].text = text
        updatedAt = now
    }

    public mutating func deleteQuestion(id: UUID, now: Date = Date()) {
        questions.removeAll { $0.id == id }
        updatedAt = now
    }

    /// Moves questions using the same offset semantics as SwiftUI's
    /// `onMove(perform:)`, so drag-to-reorder needs no translation layer.
    public mutating func moveQuestions(fromOffsets source: IndexSet, toOffset destination: Int, now: Date = Date()) {
        questions.move(fromOffsets: source, toOffset: destination)
        updatedAt = now
    }

    public mutating func rename(to newName: String, now: Date = Date()) {
        name = newName
        updatedAt = now
    }
}

public extension DeckModel {
    /// The one sample deck PromptCam ships with.
    ///
    /// Chosen to be genuinely usable rather than filler: this is a real
    /// customer-testimonial running order, which is the highest-value template
    /// for the V0 audience.
    static func sampleTestimonialDeck(now: Date = Date()) -> DeckModel {
        DeckModel(
            name: "Customer testimonial",
            questions: [
                "Tell me who you are and what you do.",
                "What was going wrong before you found us?",
                "What made you decide to try us?",
                "What changed after you started?",
                "Is there a specific result or number you can share?",
                "Who would you recommend this to, and why?"
            ].map { QuestionModel(text: $0) },
            createdAt: now,
            updatedAt: now,
            isSample: true
        )
    }
}
