import SwiftUI
import PromptCamCore

/// Edits one deck: name, questions, order.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
struct DeckEditorView: View {
    @State private var deck: DeckModel
    let onSave: (DeckModel) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newQuestionText = ""
    @FocusState private var newQuestionFocused: Bool

    init(deck: DeckModel, onSave: @escaping (DeckModel) -> Void) {
        _deck = State(initialValue: deck)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Deck name", text: $deck.name)
                    .textInputAutocapitalization(.sentences)
            }

            Section {
                ForEach($deck.questions) { $question in
                    TextField("Question", text: $question.text, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .lineLimit(1...4)
                }
                .onDelete { offsets in
                    // Delete by identity rather than index, so a concurrent
                    // reorder cannot remove the wrong row.
                    let ids = offsets.map { deck.questions[$0].id }
                    for id in ids { deck.deleteQuestion(id: id) }
                }
                .onMove { source, destination in
                    deck.moveQuestions(fromOffsets: source, toOffset: destination)
                }

                HStack {
                    TextField("Add a question", text: $newQuestionText, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                        .lineLimit(1...4)
                        .focused($newQuestionFocused)
                        .onSubmit(addQuestion)

                    Button {
                        addQuestion()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newQuestionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add question")
                }
            } header: {
                Text("Questions")
            } footer: {
                if deck.isRecordable {
                    Text("Drag to reorder. The subject sees one question at a time.")
                } else {
                    // Says why recording is unavailable, rather than silently
                    // disabling the record button elsewhere.
                    Text("Add at least one question before you can record with this deck.")
                        .foregroundStyle(Theme.Palette.warning)
                }
            }
        }
        .navigationTitle(deck.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onSave(deck)
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
    }

    private func addQuestion() {
        let trimmed = newQuestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        deck.addQuestion(trimmed)
        newQuestionText = ""
        newQuestionFocused = true
    }
}
