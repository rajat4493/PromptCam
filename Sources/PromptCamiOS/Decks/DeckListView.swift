import SwiftUI
import PromptCamCore

/// The deck library.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
struct DeckListView: View {
    @State private var model: DeckLibraryModel
    /// Called when the operator chooses a deck to record with.
    let onRecord: (DeckModel) -> Void

    @State private var editingDeck: DeckModel?
    @State private var showsDeleteConfirmation: DeckModel?

    init(model: DeckLibraryModel, onRecord: @escaping (DeckModel) -> Void) {
        _model = State(initialValue: model)
        self.onRecord = onRecord
    }

    var body: some View {
        List {
            if model.decks.isEmpty {
                emptyState
            } else {
                ForEach(model.decks) { deck in
                    row(for: deck)
                }
            }
        }
        .navigationTitle("Interview decks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        if let created = await model.createDeck() {
                            editingDeck = created
                        }
                    }
                } label: {
                    Label("New deck", systemImage: "plus")
                }
            }
        }
        .task { await model.load() }
        .sheet(item: $editingDeck) { deck in
            NavigationStack {
                DeckEditorView(deck: deck) { updated in
                    Task { await model.save(updated) }
                }
            }
        }
        .confirmationDialog(
            "Delete this deck?",
            isPresented: Binding(
                get: { showsDeleteConfirmation != nil },
                set: { if !$0 { showsDeleteConfirmation = nil } }
            ),
            presenting: showsDeleteConfirmation
        ) { deck in
            Button("Delete \(deck.displayName)", role: .destructive) {
                Task { await model.delete(deck) }
            }
        } message: { _ in
            Text("Recordings made with this deck are kept.")
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No decks yet", systemImage: "list.bullet.rectangle")
        } description: {
            Text("A deck is the list of questions you want to ask. Create one to get started.")
        }
    }

    private func row(for deck: DeckModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack {
                Text(deck.displayName).font(.headline)
                if deck.isSample {
                    Text("Sample")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tertiary, in: .capsule)
                }
            }
            Text(subtitle(for: deck))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .onTapGesture { editingDeck = deck }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                showsDeleteConfirmation = deck
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                onRecord(deck)
            } label: {
                Label("Record", systemImage: "video.fill")
            }
            .tint(Theme.Palette.recording)
            // A deck with no usable question cannot start an interview.
            .disabled(!deck.isRecordable)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the deck for editing")
    }

    private func subtitle(for deck: DeckModel) -> String {
        let count = deck.sessionQuestionTexts.count
        guard count > 0 else { return "No questions yet" }
        return count == 1 ? "1 question" : "\(count) questions"
    }
}
