import Foundation
import PromptCamCore

/// The real recording store.
///
/// STATICALLY_REVIEWED — Foundation file APIs, never compiled. REQUIRES_MAC.
///
/// ## Safety rules this type implements
///
///  - Captures are written to a **temporary** directory, then moved into a
///    permanent one only after the OS confirms the file. A crash mid-take
///    therefore never leaves a half-file in the user's library.
///  - `store` **never** deletes the temporary file when the move fails. The
///    caller preserves its path so the interview can be recovered.
///  - `cleanUpAbandonedTemporaryFiles` touches the temporary directory only. It
///    can never reach a stored recording.
struct RecordingFileStore: RecordingStore {

    private let fileManager = FileManager.default

    /// `Application Support/PromptCam/Recordings` — outside Documents so it is
    /// not exposed to file-sharing by accident, and excluded from backup would
    /// be wrong here (interviews are the user's data and should be backed up).
    private var baseDirectory: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("PromptCam", isDirectory: true)
    }

    var recordingsDirectory: URL {
        baseDirectory.appendingPathComponent("Recordings", isDirectory: true)
    }

    var temporaryDirectory: URL {
        baseDirectory.appendingPathComponent("Captures", isDirectory: true)
    }

    var recordingsDirectoryPath: String { recordingsDirectory.path }

    // MARK: - RecordingStore

    func makeTemporaryPath() throws -> String {
        try ensureDirectory(temporaryDirectory)
        return temporaryDirectory
            .appendingPathComponent("capture-\(UUID().uuidString).mov")
            .path
    }

    func store(temporaryPath: String, startedAt: Date) throws -> StoredRecording {
        guard fileManager.fileExists(atPath: temporaryPath) else {
            throw RecordingStoreError.temporaryFileMissing
        }
        try ensureDirectory(recordingsDirectory)

        let fileName = Self.fileName(for: startedAt)
        var destination = recordingsDirectory.appendingPathComponent(fileName)

        // Two takes started in the same second must not overwrite each other.
        if fileManager.fileExists(atPath: destination.path) {
            let unique = "\(Self.fileNameStem(for: startedAt))-\(UUID().uuidString.prefix(6)).mov"
            destination = recordingsDirectory.appendingPathComponent(unique)
        }

        do {
            try fileManager.moveItem(at: URL(fileURLWithPath: temporaryPath), to: destination)
        } catch {
            // Deliberately do NOT delete the temporary file. The caller reports
            // its path so the operator keeps their interview.
            throw RecordingStoreError.moveFailed(error.localizedDescription)
        }

        return StoredRecording(
            path: destination.path,
            fileName: destination.lastPathComponent
        )
    }

    func cleanUpAbandonedTemporaryFiles() throws {
        guard fileManager.fileExists(atPath: temporaryDirectory.path) else { return }

        let contents = try fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        )
        for url in contents {
            // Belt and braces: never delete anything outside the temporary
            // directory, whatever the enumeration returns.
            guard url.deletingLastPathComponent().standardizedFileURL
                == temporaryDirectory.standardizedFileURL else { continue }
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Helpers

    /// Resolves a stored recording for playback.
    ///
    /// Returns `nil` when the recording is not playable or the file is gone, so
    /// a missing file can never be offered to the player.
    func playbackURL(for recording: InterviewRecordingModel) -> URL? {
        guard recording.outcome.isPlayable, let fileName = recording.fileName else { return nil }
        let url = recordingsDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Writes an export payload to a temporary file for the share sheet.
    func writeExport(contents: String, fileName: String) throws -> URL {
        let directory = baseDirectory.appendingPathComponent("Exports", isDirectory: true)
        try ensureDirectory(directory)
        let url = directory.appendingPathComponent(fileName)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func ensureDirectory(_ url: URL) throws {
        guard !fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw RecordingStoreError.couldNotCreateDirectory(error.localizedDescription)
        }
    }

    private static func fileNameStem(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "Interview-\(formatter.string(from: date))"
    }

    private static func fileName(for date: Date) -> String {
        "\(fileNameStem(for: date)).mov"
    }
}
