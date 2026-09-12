import Foundation
import SwiftData
import PromptCamCore

/// SwiftData storage for a deck.
///
/// STATICALLY_REVIEWED — SwiftData macros, never compiled. REQUIRES_MAC.
///
/// These types exist only at the persistence boundary. The rest of the app
/// works with `PromptCamCore`'s value types, so a schema change or a SwiftData
/// quirk cannot reach the session logic or the tests.
@Model
final class StoredDeck {
    #Index<StoredDeck>([\.createdAt])

    var identifier: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isSample: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \StoredQuestion.deck)
    var questions: [StoredQuestion] = []

    init(from model: DeckModel) {
        identifier = model.id
        name = model.name
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        isSample = model.isSample
        questions = model.questions.enumerated().map { index, question in
            StoredQuestion(identifier: question.id, text: question.text, order: index)
        }
    }

    /// Converts back to the value type.
    ///
    /// Questions are sorted by the explicit `order` field: SwiftData does not
    /// guarantee the ordering of a to-many relationship across a reload, so the
    /// array order alone is not trustworthy.
    func toModel() -> DeckModel {
        DeckModel(
            id: identifier,
            name: name,
            questions: questions
                .sorted { $0.order < $1.order }
                .map { QuestionModel(id: $0.identifier, text: $0.text) },
            createdAt: createdAt,
            updatedAt: updatedAt,
            isSample: isSample
        )
    }

    /// Rewrites this record in place from `model`.
    func update(from model: DeckModel) {
        name = model.name
        updatedAt = model.updatedAt
        isSample = model.isSample

        // Replace wholesale. Decks are tiny and this avoids a diffing bug
        // silently corrupting question order.
        questions.removeAll()
        questions = model.questions.enumerated().map { index, question in
            StoredQuestion(identifier: question.id, text: question.text, order: index)
        }
    }
}

@Model
final class StoredQuestion {
    var identifier: UUID = UUID()
    var text: String = ""
    /// Zero-based position. The authority on ordering.
    var order: Int = 0
    var deck: StoredDeck?

    init(identifier: UUID, text: String, order: Int) {
        self.identifier = identifier
        self.text = text
        self.order = order
    }
}

/// SwiftData storage for a completed interview.
@Model
final class StoredRecording {
    #Index<StoredRecording>([\.startedAt])

    var identifier: UUID = UUID()
    var deckName: String = ""
    var startedAt: Date = Date()
    var duration: TimeInterval = 0
    var fileName: String?
    var preservedFilePath: String?
    /// Raw value of `RecordingOutcome`. Stored as a string so adding a case
    /// later cannot corrupt existing rows.
    var outcomeRaw: String = RecordingOutcome.failed.rawValue
    var failureDescription: String?

    @Relationship(deleteRule: .cascade, inverse: \StoredMarker.recording)
    var markers: [StoredMarker] = []

    @Relationship(deleteRule: .cascade, inverse: \StoredQuestionChange.recording)
    var questionChanges: [StoredQuestionChange] = []

    init(from model: InterviewRecordingModel) {
        identifier = model.id
        deckName = model.deckName
        startedAt = model.startedAt
        duration = model.duration
        fileName = model.fileName
        preservedFilePath = model.preservedFilePath
        outcomeRaw = model.outcome.rawValue
        failureDescription = model.failureDescription
        markers = model.markers.map { StoredMarker(identifier: $0.id, offset: $0.offset, label: $0.label) }
        questionChanges = model.questionChanges.map {
            StoredQuestionChange(identifier: $0.id, offset: $0.offset, index: $0.index, text: $0.text)
        }
    }

    /// Rewrites this row in place from `model`.
    ///
    /// Used by the upsert path when a session reconciles a late file. Children
    /// are replaced wholesale — they are few, and a diffing bug here would
    /// silently corrupt a marker timeline.
    func update(from model: InterviewRecordingModel) {
        deckName = model.deckName
        startedAt = model.startedAt
        duration = model.duration
        fileName = model.fileName
        preservedFilePath = model.preservedFilePath
        outcomeRaw = model.outcome.rawValue
        failureDescription = model.failureDescription

        markers.removeAll()
        markers = model.markers.map {
            StoredMarker(identifier: $0.id, offset: $0.offset, label: $0.label)
        }
        questionChanges.removeAll()
        questionChanges = model.questionChanges.map {
            StoredQuestionChange(identifier: $0.id, offset: $0.offset, index: $0.index, text: $0.text)
        }
    }

    func toModel() -> InterviewRecordingModel {
        InterviewRecordingModel(
            id: identifier,
            deckName: deckName,
            startedAt: startedAt,
            duration: duration,
            // An unrecognised raw value degrades to `.failed`, which is not
            // playable — the safe direction to fail in.
            outcome: RecordingOutcome(rawValue: outcomeRaw) ?? .failed,
            fileName: fileName,
            preservedFilePath: preservedFilePath,
            failureDescription: failureDescription,
            markers: markers.map { MarkerModel(id: $0.identifier, offset: $0.offset, label: $0.label) },
            questionChanges: questionChanges.map {
                QuestionChangeModel(id: $0.identifier, offset: $0.offset, index: $0.index, text: $0.text)
            }
        )
    }
}

@Model
final class StoredMarker {
    var identifier: UUID = UUID()
    var offset: TimeInterval = 0
    var label: String = ""
    var recording: StoredRecording?

    init(identifier: UUID, offset: TimeInterval, label: String) {
        self.identifier = identifier
        self.offset = offset
        self.label = label
    }
}

@Model
final class StoredQuestionChange {
    var identifier: UUID = UUID()
    var offset: TimeInterval = 0
    var index: Int = 0
    var text: String = ""
    var recording: StoredRecording?

    init(identifier: UUID, offset: TimeInterval, index: Int, text: String) {
        self.identifier = identifier
        self.offset = offset
        self.index = index
        self.text = text
    }
}

/// The app's SwiftData schema, in one place.
enum PromptCamSchema {
    static var models: [any PersistentModel.Type] {
        [
            StoredDeck.self,
            StoredQuestion.self,
            StoredRecording.self,
            StoredMarker.self,
            StoredQuestionChange.self
        ]
    }

    /// The live, on-disk container.
    static func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Schema(models))
    }

    /// An in-memory container, for previews and for tests that want the real
    /// SwiftData stack rather than the in-memory double.
    static func makeEphemeralContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
