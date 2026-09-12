import SwiftUI
import PromptCamCore

/// The library of completed and attempted interviews.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
///
/// Shows failures and interruptions as well as successes. An interview that did
/// not save must leave a visible trace, not disappear.
struct RecordingsListView: View {
    @State private var model: RecordingsLibraryModel

    init(model: RecordingsLibraryModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        List {
            if model.recordings.isEmpty {
                ContentUnavailableView {
                    Label("No interviews yet", systemImage: "film")
                } description: {
                    Text("Recorded interviews appear here with their markers.")
                }
            } else {
                ForEach(model.recordings) { recording in
                    NavigationLink {
                        RecordingDetailView(recording: recording, model: model)
                    } label: {
                        row(for: recording)
                    }
                }
            }
        }
        .navigationTitle("Interviews")
        .task { await model.load() }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.clearError() } }
        )) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private func row(for recording: InterviewRecordingModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.tight) {
            HStack {
                Text(recording.displayTitle).font(.headline)
                Spacer(minLength: 0)
                outcomeBadge(for: recording.outcome)
            }

            HStack(spacing: Theme.Space.snug) {
                Text(recording.startedAt, format: .dateTime.day().month().hour().minute())
                Text("·")
                Text(MarkerExporter.shortTimecode(recording.duration))
                    .monospacedDigit()
                if !recording.markers.isEmpty {
                    Text("·")
                    Label("\(recording.markers.count)", systemImage: "bookmark.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func outcomeBadge(for outcome: RecordingOutcome) -> some View {
        Text(outcome.shortDescription)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(background(for: outcome), in: .capsule)
            .foregroundStyle(outcome.isPlayable ? Color.primary : Color.white)
    }

    private func background(for outcome: RecordingOutcome) -> Color {
        switch outcome {
        case .saved: return Color.secondary.opacity(0.2)
        case .interrupted: return Theme.Palette.warning
        case .saveFailed, .failed: return Theme.Palette.failure
        }
    }
}
