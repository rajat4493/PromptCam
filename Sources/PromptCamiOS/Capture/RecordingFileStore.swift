import Foundation
import PromptCamCore

/// The real recording store.
///
/// STATICALLY_REVIEWED — Foundation file APIs, never compiled. REQUIRES_MAC.
///
/// ## Three directories, three lifetimes
///
/// | Directory | Contents | Cleanup |
/// |---|---|---|
/// | `Captures/` | in-flight capture, before the OS confirms it | swept, but only files that are old **and** not in use |
/// | `Recordings/` | confirmed, complete interviews | never swept |
/// | `Recovery/`  | captures that could not be filed, kept for the user | never swept |
///
/// ## Safety rules
///
///  - Captures are written to `Captures/`, then moved into `Recordings/` only
///    after the operating system confirms the file. A crash mid-take therefore
///    never leaves a half-file in the user's library.
///  - `store` **never** deletes the temporary file when the move fails.
///  - Anything worth keeping is moved into `Recovery/` — a directory the sweeper
///    cannot reach. Leaving a "preserved" file in `Captures/` would mean the
///    next session deleted the interview the app had promised to keep.
///  - `cleanUpAbandonedTemporaryFiles` touches `Captures/` only, skips paths in
///    use, and only removes files older than the age it is given.
struct RecordingFileStore: RecordingStore {

    private let fileManager = FileManager.default

    /// How old a temporary capture must be before the sweeper may remove it.
    ///
    /// Generous on purpose: a file younger than this could belong to a capture
    /// that is still running, and deleting a live interview is far worse than
    /// leaving a stray file on disk for an hour.
    static let abandonedCaptureAge: TimeInterval = 60 * 60

    /// `Application Support/PromptCam` — outside Documents so interviews are not
    /// exposed to file sharing by accident.
    private var baseDirectory: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support.appendingPathComponent("PromptCam", isDirectory: true)
    }

    var recordingsDirectory: URL {
        baseDirectory.appendingPathComponent("Recordings", isDirectory: true)
    }

    /// In-flight captures. The only directory the sweeper may touch.
    var temporaryDirectory: URL {
        baseDirectory.appendingPathComponent("Captures", isDirectory: true)
    }

    /// Captures that could not be filed but must survive. Never swept.
    var recoveryDirectory: URL {
        baseDirectory.appendingPathComponent("Recovery", isDirectory: true)
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

        let destination = try uniqueDestination(
            in: recordingsDirectory,
            stem: Self.fileNameStem(for: startedAt)
        )

        do {
            try fileManager.moveItem(at: URL(fileURLWithPath: temporaryPath), to: destination)
        } catch {
            // Deliberately do NOT delete the temporary file. The caller moves it
            // into `Recovery/` so the operator keeps their interview.
            throw RecordingStoreError.moveFailed(error.localizedDescription)
        }

        return StoredRecording(
            path: destination.path,
            fileName: destination.lastPathComponent
        )
    }

    func preserveForRecovery(temporaryPath: String) throws -> String {
        guard fileManager.fileExists(atPath: temporaryPath) else {
            throw RecordingStoreError.temporaryFileMissing
        }

        // Already in the recovery directory: nothing to do, and re-moving would
        // change a path the library has already recorded.
        let source = URL(fileURLWithPath: temporaryPath)
        if source.deletingLastPathComponent().standardizedFileURL
            == recoveryDirectory.standardizedFileURL {
            return temporaryPath
        }

        do {
            try ensureDirectory(recoveryDirectory)
        } catch {
            throw RecordingStoreError.preserveFailed(error.localizedDescription)
        }

        let destination = try uniqueDestination(
            in: recoveryDirectory,
            stem: "Recovered-\(Self.timestampStem(for: Date()))"
        )

        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            // The move failed, so the file is still at its temporary path. That
            // is a worse place to be but it is better than nothing, and the
            // caller records whichever path actually holds the file.
            throw RecordingStoreError.preserveFailed(error.localizedDescription)
        }
        return destination.path
    }

    func preservedFileExists(atPath path: String) -> Bool {
        fileManager.fileExists(atPath: path)
    }

    func cleanUpAbandonedTemporaryFiles(
        excluding activePaths: Set<String>,
        olderThan age: TimeInterval
    ) throws {
        guard fileManager.fileExists(atPath: temporaryDirectory.path) else { return }

        let contents = try fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        let cutoff = Date().addingTimeInterval(-age)
        let activeStandardised = Set(
            activePaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        )

        for url in contents {
            // Never delete anything outside the temporary directory, whatever
            // the enumeration returns. `Recordings/` and `Recovery/` are
            // unreachable from here by construction.
            guard url.deletingLastPathComponent().standardizedFileURL
                == temporaryDirectory.standardizedFileURL else { continue }

            // Never delete a capture that is in use right now.
            guard !activeStandardised.contains(url.standardizedFileURL.path) else { continue }

            // Never delete a recent file: it may belong to a capture that is
            // still running, or to a session about to reconcile it.
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let modified, modified < cutoff else { continue }

            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Helpers

    /// Resolves a stored recording for playback.
    ///
    /// Returns `nil` unless the recording is playable *and* the file is still
    /// present, so a missing file can never be offered to the player.
    func playbackURL(for recording: InterviewRecordingModel) -> URL? {
        guard recording.outcome.isPlayable, let fileName = recording.fileName else { return nil }
        let url = recordingsDirectory.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Resolves a preserved file so the user can actually recover it.
    ///
    /// Returns `nil` when the path no longer resolves, so the UI never offers a
    /// recovery action that would fail.
    func recoveryURL(for recording: InterviewRecordingModel) -> URL? {
        guard let path = recording.preservedFilePath, preservedFileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// Writes an export payload to a file for the share sheet.
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

    /// A destination that does not already exist, so two takes started in the
    /// same second cannot overwrite each other.
    private func uniqueDestination(in directory: URL, stem: String) throws -> URL {
        let plain = directory.appendingPathComponent("\(stem).mov")
        guard fileManager.fileExists(atPath: plain.path) else { return plain }

        for _ in 0..<10 {
            let candidate = directory.appendingPathComponent(
                "\(stem)-\(UUID().uuidString.prefix(6)).mov"
            )
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        throw RecordingStoreError.moveFailed("No free filename was available.")
    }

    private static func timestampStem(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }

    private static func fileNameStem(for date: Date) -> String {
        "Interview-\(timestampStem(for: date))"
    }
}
