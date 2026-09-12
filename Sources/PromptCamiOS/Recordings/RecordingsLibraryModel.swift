import Foundation
import Observation
import PromptCamCore

/// Owns the recordings library and the export actions.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
@MainActor
@Observable
final class RecordingsLibraryModel {
    private(set) var recordings: [InterviewRecordingModel] = []
    private(set) var errorMessage: String?

    private let repository: any RecordingRepository
    private let store: RecordingFileStore
    private let exporter = MarkerExporter()

    init(repository: any RecordingRepository, store: RecordingFileStore) {
        self.repository = repository
        self.store = store
    }

    func load() async {
        do {
            recordings = try await repository.loadRecordings()
        } catch {
            errorMessage = "Your recordings could not be loaded. \(error.localizedDescription)"
        }
    }

    /// Removes a library entry.
    ///
    /// Does **not** delete the media file — that is a separate, explicit
    /// decision, and nothing in V0 silently destroys an interview.
    func removeFromLibrary(_ recording: InterviewRecordingModel) async {
        do {
            try await repository.delete(recordingID: recording.id)
            recordings = try await repository.loadRecordings()
        } catch {
            errorMessage = "The entry could not be removed. \(error.localizedDescription)"
        }
    }

    /// The playable video file, or `nil` when there is not one.
    func videoURL(for recording: InterviewRecordingModel) -> URL? {
        store.playbackURL(for: recording)
    }

    /// Writes the marker list and returns the file to share.
    func exportMarkers(
        for recording: InterviewRecordingModel,
        format: MarkerExportFormat
    ) -> URL? {
        let stem = exporter.fileNameStem(for: recording)
        do {
            switch format {
            case .csv:
                return try store.writeExport(
                    contents: exporter.csv(for: recording),
                    fileName: "\(stem).csv"
                )
            case .plainText:
                return try store.writeExport(
                    contents: exporter.plainText(for: recording),
                    fileName: "\(stem).txt"
                )
            }
        } catch {
            // Export failure is reported and changes nothing about the
            // recording itself, which stays in the library and playable.
            errorMessage = "The marker list could not be written. \(error.localizedDescription)"
            return nil
        }
    }

    func timelineRows(for recording: InterviewRecordingModel) -> [MarkerExporter.Row] {
        exporter.rows(for: recording)
    }

    func clearError() { errorMessage = nil }
}

enum MarkerExportFormat: String, CaseIterable, Identifiable {
    case csv
    case plainText

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .csv: return "CSV (for editing tools)"
        case .plainText: return "Plain text (to read)"
        }
    }
}
