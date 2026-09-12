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

    /// Removes temporary captures left behind by earlier crashes.
    ///
    /// Must never touch `recordingsDirectoryPath`.
    func cleanUpAbandonedTemporaryFiles() throws
}

/// A failure raised by a `RecordingStore`.
public enum RecordingStoreError: Error, Equatable, Sendable {
    case couldNotCreateDirectory(String)
    case moveFailed(String)
    case temporaryFileMissing
    case insufficientStorage

    public var reasonText: String {
        switch self {
        case .couldNotCreateDirectory(let detail): return "Storage folder unavailable. \(detail)"
        case .moveFailed(let detail): return "The file could not be filed. \(detail)"
        case .temporaryFileMissing: return "The captured file was missing."
        case .insufficientStorage: return "There is not enough free space."
        }
    }
}
