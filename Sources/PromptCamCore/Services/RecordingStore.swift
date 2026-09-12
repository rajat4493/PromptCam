import Foundation

/// The result of moving a captured file into permanent storage.
public struct StoredRecording: Equatable, Sendable {
    /// Final absolute path of the media file.
    public let path: String
    /// Filename relative to the recordings directory.
    public let fileName: String

    public init(path: String, fileName: String) {
        self.path = path
        self.fileName = fileName
    }
}

/// Moves captured files into permanent storage and hands out temporary paths.
///
/// Deliberately narrow so save failure is easy to simulate, and so the
/// "never delete a recording" rule lives in exactly one place.
public protocol RecordingStore: Sendable {
    /// A fresh temporary path to capture into.
    func makeTemporaryPath() throws -> String

    /// Moves a captured temporary file into permanent storage.
    ///
    /// Implementations **must not** delete `temporaryPath` if the move fails —
    /// the caller needs it to preserve the operator's interview.
    func store(temporaryPath: String, startedAt: Date) throws -> StoredRecording

    /// Absolute path of the directory permanent recordings live in.
    var recordingsDirectoryPath: String { get }

    /// Moves a capture that could not be filed into a **persistent recovery**
    /// directory, returning its new absolute path.
    ///
    /// This is what makes "your video has been kept" a truthful promise. A
    /// capture left in the temporary directory is not kept — the next session's
    /// cleanup would remove it — so anything worth preserving must be moved out
    /// of harm's way before the session ends.
    ///
    /// Implementations must not delete `temporaryPath` if the move fails; the
    /// original file is better than no file.
    func preserveForRecovery(temporaryPath: String) throws -> String

    /// Whether a previously preserved file is still on disk.
    ///
    /// The UI must call this before offering recovery, so a path that no longer
    /// resolves is never presented as a recoverable interview.
    func preservedFileExists(atPath path: String) -> Bool

    /// Removes temporary captures abandoned by earlier crashes.
    ///
    /// Deliberately narrow, because this method previously destroyed the very
    /// files the app had promised to keep:
    ///
    /// - It touches the temporary directory only, never
    ///   `recordingsDirectoryPath` and never the recovery directory.
    /// - It skips any path in `excluding`, so a capture in flight cannot be
    ///   deleted underneath itself.
    /// - It deletes only files older than `olderThan`, so a capture belonging
    ///   to another live session is left alone.
    func cleanUpAbandonedTemporaryFiles(
        excluding activePaths: Set<String>,
        olderThan age: TimeInterval
    ) throws
}

/// A failure raised by a `RecordingStore`.
public enum RecordingStoreError: Error, Equatable, Sendable {
    case couldNotCreateDirectory(String)
    case moveFailed(String)
    case temporaryFileMissing
    case insufficientStorage
    /// A capture could not be moved into the recovery directory. The original
    /// file is still at its temporary path.
    case preserveFailed(String)

    public var reasonText: String {
        switch self {
        case .couldNotCreateDirectory(let detail): return "Storage folder unavailable. \(detail)"
        case .moveFailed(let detail): return "The file could not be filed. \(detail)"
        case .temporaryFileMissing: return "The captured file was missing."
        case .insufficientStorage: return "There is not enough free space."
        case .preserveFailed(let detail): return "The captured file could not be moved somewhere safe. \(detail)"
        }
    }
}
