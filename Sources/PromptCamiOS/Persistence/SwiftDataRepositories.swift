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
    /// Records that the shipped sample deck has been inserted once.
    ///
    /// Stored outside the database on purpose. Keying seeding on "is the
    /// database empty?" reseeds the sample every time the user deletes every
    /// deck — which contradicts the promise that a deliberately deleted sample
    /// stays deleted.
    static let hasSeededSampleKey = "com.promptcam.hasSeededSampleDeck"

    private let context: ModelContext
    private let defaults: UserDefaults

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
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
        // Seed at most once, ever. A user who deletes the sample deck — or every
        // deck — must not have it reappear on the next launch.
        guard !defaults.bool(forKey: Self.hasSeededSampleKey) else { return }

        // Belt and braces: if decks already exist, this install has been used,
        // so mark it seeded without inserting anything.
        var descriptor = FetchDescriptor<StoredDeck>()
        descriptor.fetchLimit = 1
        let isEmpty = try context.fetch(descriptor).isEmpty

        if isEmpty {
            context.insert(StoredDeck(from: DeckModel.sampleTestimonialDeck(now: now)))
            try context.save()
        }
        // Only record success after the write, so a failed save retries next launch.
        defaults.set(true, forKey: Self.hasSeededSampleKey)
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

    /// Inserts or updates by identifier.
    ///
    /// Upsert rather than insert, because a session persists its outcome once
    /// when it ends and may persist it again after a late reconciliation (a
    /// file finalised after an interruption). Inserting twice would leave the
    /// library showing the same interview two ways.
    func save(_ recording: InterviewRecordingModel) async throws {
        let identifier = recording.id
        var descriptor = FetchDescriptor<StoredRecording>(
            predicate: #Predicate { $0.identifier == identifier }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.update(from: recording)
        } else {
            context.insert(StoredRecording(from: recording))
        }
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
