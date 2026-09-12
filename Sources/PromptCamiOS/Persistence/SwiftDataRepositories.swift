import Foundation
import SwiftData
import PromptCamCore

/// SwiftData-backed deck storage.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
///
/// `@MainActor` because SwiftData's `ModelContext` is not `Sendable` and the app
/// drives it from the UI. The repository protocols are `async`, so this
/// isolation is expressed honestly rather than being forced through an
/// `assumeIsolated` call that would crash if the assumption were ever wrong.
@MainActor
final class SwiftDataDeckRepository: DeckRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func loadDecks() async throws -> [DeckModel] {
        let descriptor = FetchDescriptor<StoredDeck>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return try context.fetch(descriptor).map { $0.toModel() }
    }

    func save(_ deck: DeckModel) async throws {
        let identifier = deck.id
        var descriptor = FetchDescriptor<StoredDeck>(
            predicate: #Predicate { $0.identifier == identifier }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.update(from: deck)
        } else {
            context.insert(StoredDeck(from: deck))
        }
        try context.save()
    }

    func delete(deckID: UUID) async throws {
        var descriptor = FetchDescriptor<StoredDeck>(
            predicate: #Predicate { $0.identifier == deckID }
        )
        descriptor.fetchLimit = 1
        guard let existing = try context.fetch(descriptor).first else { return }
        context.delete(existing)
        try context.save()
    }

    func seedSampleDeckIfNeeded(now: Date) async throws {
        // Seed only when the store is completely empty. A user who deliberately
        // deleted the sample deck must not have it reappear.
        var descriptor = FetchDescriptor<StoredDeck>()
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return }

        context.insert(StoredDeck(from: DeckModel.sampleTestimonialDeck(now: now)))
        try context.save()
    }
}

/// SwiftData-backed recording storage.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
@MainActor
final class SwiftDataRecordingRepository: RecordingRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func loadRecordings() async throws -> [InterviewRecordingModel] {
        let descriptor = FetchDescriptor<StoredRecording>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.toModel() }
    }

    func save(_ recording: InterviewRecordingModel) async throws {
        context.insert(StoredRecording(from: recording))
        try context.save()
    }

    func delete(recordingID: UUID) async throws {
        var descriptor = FetchDescriptor<StoredRecording>(
            predicate: #Predicate { $0.identifier == recordingID }
        )
        descriptor.fetchLimit = 1
        guard let existing = try context.fetch(descriptor).first else { return }

        // Deliberately does NOT delete the media file. Removing a library entry
        // must never destroy an interview the user may still want; deleting the
        // file is a separate, explicit action.
        context.delete(existing)
        try context.save()
    }
}
