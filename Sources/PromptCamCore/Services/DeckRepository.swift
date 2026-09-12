import Foundation

/// Persists interview decks.
///
/// The iOS layer implements this with SwiftData; tests use an in-memory double.
/// Keeping it a protocol is what lets deck creation, editing, ordering and
/// reload be exercised without a database.
public protocol DeckRepository: Sendable {
    func loadDecks() throws -> [DeckModel]
    func save(_ deck: DeckModel) throws
    func delete(deckID: UUID) throws
    /// Inserts the shipped sample deck if the store has never been seeded.
    func seedSampleDeckIfNeeded(now: Date) throws
}

/// Persists completed interviews.
public protocol RecordingRepository: Sendable {
    func loadRecordings() throws -> [InterviewRecordingModel]
    func save(_ recording: InterviewRecordingModel) throws
    func delete(recordingID: UUID) throws
}

/// Why a deck cannot be saved.
public enum DeckValidationError: Error, Equatable, Sendable {
    case emptyName
    case noQuestions

    public var message: String {
        switch self {
        case .emptyName: return "Give the deck a name."
        case .noQuestions: return "Add at least one question."
        }
    }
}

public extension DeckModel {
    /// Checks a deck before it is used to start an interview.
    ///
    /// Name emptiness is *not* fatal for storage (an untitled deck displays as
    /// "Untitled deck"), but a deck with no usable question cannot record.
    func validateForRecording() throws {
        guard isRecordable else { throw DeckValidationError.noQuestions }
    }
}
