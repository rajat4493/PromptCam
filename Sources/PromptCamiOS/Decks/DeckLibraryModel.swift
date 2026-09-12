import Foundation
import Observation
import PromptCamCore

/// Owns the deck library.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
///
/// All editing rules live on `DeckModel` in the Core layer, so this class only
/// loads, saves and surfaces errors.
@MainActor
@Observable
final class DeckLibraryModel {
    private(set) var decks: [DeckModel] = []
    private(set) var errorMessage: String?

    private let repository: any DeckRepository
    private let clock: any SessionClock

    init(repository: any DeckRepository, clock: any SessionClock = SystemSessionClock()) {
        self.repository = repository
        self.clock = clock
    }

    func load() async {
        do {
            // Seeding is idempotent and only fires on a completely empty store,
            // so a user who deleted the sample deck does not get it back.
            try await repository.seedSampleDeckIfNeeded(now: clock.now)
            decks = try await repository.loadDecks()
        } catch {
            errorMessage = "Your decks could not be loaded. \(error.localizedDescription)"
        }
    }

    /// Creates and persists an empty deck, returning it for immediate editing.
    func createDeck() async -> DeckModel? {
        let deck = DeckModel(name: "New deck", createdAt: clock.now, updatedAt: clock.now)
        do {
            try await repository.save(deck)
            decks = try await repository.loadDecks()
            return deck
        } catch {
            errorMessage = "The deck could not be created. \(error.localizedDescription)"
            return nil
        }
    }

    func save(_ deck: DeckModel) async {
        do {
            try await repository.save(deck)
            decks = try await repository.loadDecks()
        } catch {
            errorMessage = "Your changes could not be saved. \(error.localizedDescription)"
        }
    }

    func delete(_ deck: DeckModel) async {
        do {
            try await repository.delete(deckID: deck.id)
            decks = try await repository.loadDecks()
        } catch {
            errorMessage = "The deck could not be deleted. \(error.localizedDescription)"
        }
    }

    func clearError() { errorMessage = nil }
}
