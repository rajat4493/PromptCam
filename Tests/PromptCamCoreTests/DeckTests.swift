import Testing
import Foundation
@testable import PromptCamCore

@Suite("Decks: creation, editing, ordering")
struct DeckTests {

    @Test("A new deck starts empty and is not recordable")
    func newDeckIsNotRecordable() {
        let deck = DeckModel(name: "Street interviews")
        #expect(deck.questionCount == 0)
        #expect(deck.isRecordable == false)
        #expect(throws: DeckValidationError.noQuestions) {
            try deck.validateForRecording()
        }
    }

    @Test("Adding questions makes a deck recordable and bumps updatedAt")
    func addingQuestions() {
        let created = Date(timeIntervalSince1970: 1000)
        var deck = DeckModel(name: "Testimonials", createdAt: created, updatedAt: created)

        deck.addQuestion("Who are you?", now: Date(timeIntervalSince1970: 2000))

        #expect(deck.questionCount == 1)
        #expect(deck.isRecordable)
        #expect(deck.updatedAt == Date(timeIntervalSince1970: 2000))
    }

    @Test("Editing a question changes only that question")
    func editingQuestion() {
        var deck = DeckModel(name: "D", questions: [
            QuestionModel(text: "First"),
            QuestionModel(text: "Second")
        ])
        let targetID = deck.questions[1].id

        deck.updateQuestion(id: targetID, text: "Second, revised")

        #expect(deck.questions[0].text == "First")
        #expect(deck.questions[1].text == "Second, revised")
        #expect(deck.questions[1].id == targetID)
    }

    @Test("Editing an unknown question is a no-op rather than a crash")
    func editingUnknownQuestion() {
        var deck = DeckModel(name: "D", questions: [QuestionModel(text: "First")])
        deck.updateQuestion(id: UUID(), text: "Nope")
        #expect(deck.questions.count == 1)
        #expect(deck.questions[0].text == "First")
    }

    @Test("Deleting a question removes exactly one")
    func deletingQuestion() {
        var deck = DeckModel(name: "D", questions: [
            QuestionModel(text: "A"), QuestionModel(text: "B"), QuestionModel(text: "C")
        ])
        deck.deleteQuestion(id: deck.questions[1].id)

        #expect(deck.questions.map(\.text) == ["A", "C"])
    }

    @Test("Reordering questions uses SwiftUI onMove offsets")
    func reorderingQuestions() {
        var deck = DeckModel(name: "D", questions: [
            QuestionModel(text: "A"), QuestionModel(text: "B"), QuestionModel(text: "C")
        ])

        // Move "C" (index 2) to the front.
        deck.moveQuestions(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        #expect(deck.questions.map(\.text) == ["C", "A", "B"])
    }

    @Test("Blank questions never reach a session")
    func blankQuestionsFiltered() {
        let deck = DeckModel(name: "D", questions: [
            QuestionModel(text: "Real question"),
            QuestionModel(text: "   "),
            QuestionModel(text: "\n\t"),
            QuestionModel(text: "  Another real one  ")
        ])

        #expect(deck.sessionQuestionTexts == ["Real question", "Another real one"])
    }

    @Test("A deck of only blank questions is not recordable")
    func allBlankIsNotRecordable() {
        let deck = DeckModel(name: "D", questions: [QuestionModel(text: "  ")])
        #expect(deck.isRecordable == false)
    }

    @Test("An unnamed deck still displays a usable name")
    func untitledDeckDisplayName() {
        #expect(DeckModel(name: "").displayName == "Untitled deck")
        #expect(DeckModel(name: "   ").displayName == "Untitled deck")
        #expect(DeckModel(name: " Real name ").displayName == "Real name")
    }

    @Test("Renaming updates the name and the timestamp")
    func renaming() {
        var deck = DeckModel(name: "Old")
        deck.rename(to: "New", now: Date(timeIntervalSince1970: 5000))
        #expect(deck.name == "New")
        #expect(deck.updatedAt == Date(timeIntervalSince1970: 5000))
    }

    @Test("The shipped sample deck is genuinely usable")
    func sampleDeck() {
        let deck = DeckModel.sampleTestimonialDeck()
        #expect(deck.isSample)
        #expect(deck.isRecordable)
        #expect(deck.questionCount >= 5)
        // Every shipped question must be valid, or the sample would embarrass us.
        #expect(deck.questions.allSatisfy(\.isValid))
    }
}

@Suite("Decks: persistence and reload")
struct DeckPersistenceTests {

    @Test("A saved deck reloads with its questions in order")
    func saveAndReload() async throws {
        let repository = InMemoryDeckRepository()
        var deck = DeckModel(name: "Founder interviews")
        deck.addQuestion("Why did you start?")
        deck.addQuestion("What nearly killed it?")
        deck.addQuestion("What's next?")

        try await repository.save(deck)
        let reloaded = try await repository.loadDecks()

        #expect(reloaded.count == 1)
        #expect(reloaded[0].id == deck.id)
        #expect(reloaded[0].questions.map(\.text) == [
            "Why did you start?", "What nearly killed it?", "What's next?"
        ])
    }

    @Test("Reordering survives a save and reload")
    func reorderSurvivesReload() async throws {
        let repository = InMemoryDeckRepository()
        var deck = DeckModel(name: "D")
        deck.addQuestion("A")
        deck.addQuestion("B")
        deck.addQuestion("C")
        try await repository.save(deck)

        deck.moveQuestions(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        try await repository.save(deck)

        let reloaded = try await repository.loadDecks()
        #expect(reloaded[0].questions.map(\.text) == ["B", "C", "A"])
    }

    @Test("Deleting a deck removes it from the store")
    func deleteDeck() async throws {
        let repository = InMemoryDeckRepository()
        let deck = DeckModel(name: "Temporary")
        try await repository.save(deck)
        let afterSave = try await repository.loadDecks()
        #expect(afterSave.count == 1)

        try await repository.delete(deckID: deck.id)
        let afterDelete = try await repository.loadDecks()
        #expect(afterDelete.isEmpty)
    }

    @Test("The sample deck is seeded once and not duplicated")
    func seedOnce() async throws {
        let repository = InMemoryDeckRepository()
        let now = Date(timeIntervalSince1970: 1000)

        try await repository.seedSampleDeckIfNeeded(now: now)
        try await repository.seedSampleDeckIfNeeded(now: now)
        try await repository.seedSampleDeckIfNeeded(now: now)

        let decks = try await repository.loadDecks()
        #expect(decks.count == 1)
        #expect(decks[0].isSample)
    }

    @Test("A storage failure surfaces instead of being swallowed")
    func saveFailureSurfaces() async {
        let repository = InMemoryDeckRepository()
        repository.writeError = RecordingStoreError.moveFailed("disk full")

        #expect(throws: (any Error).self) {
            try await repository.save(DeckModel(name: "Doomed"))
        }
    }
}
