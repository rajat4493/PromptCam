import Foundation

/// How a recording ended.
///
/// Persisted so the library can never present an incomplete capture as a
/// finished interview.
public enum RecordingOutcome: String, Codable, Sendable, CaseIterable {
    /// The operating system confirmed a complete file and it was stored.
    case saved
    /// Capture produced a file but storing or finalising it failed. The file
    /// may still exist at `preservedFilePath`.
    case saveFailed
    /// Capture was interrupted. Any partial file is retained but flagged.
    case interrupted
    /// Capture never produced a usable file.
    case failed

    /// Whether this recording may be offered for playback and export.
    ///
    /// The UI must gate playback on this and nothing else.
    public var isPlayable: Bool { self == .saved }

    public var shortDescription: String {
        switch self {
        case .saved: return "Saved"
        case .saveFailed: return "Not saved"
        case .interrupted: return "Interrupted"
        case .failed: return "Failed"
        }
    }
}

/// A moment the operator flagged during recording.
public struct MarkerModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: UUID
    /// Seconds from the start of capture.
    public let offset: TimeInterval
    public var label: String

    public init(id: UUID = UUID(), offset: TimeInterval, label: String) {
        self.id = id
        self.offset = offset
        self.label = label
    }
}

/// A record of the subject-facing question changing during capture.
public struct QuestionChangeModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: UUID
    /// Seconds from the start of capture.
    public let offset: TimeInterval
    /// Zero-based index within the session's question snapshot.
    public let index: Int
    public let text: String

    public init(id: UUID = UUID(), offset: TimeInterval, index: Int, text: String) {
        self.id = id
        self.offset = offset
        self.index = index
        self.text = text
    }
}

/// A completed or attempted interview, in a form that can be persisted,
/// exported and asserted on without any platform framework.
public struct InterviewRecordingModel: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Deck name captured at record time, so renaming or deleting a deck
    /// cannot corrupt history.
    public let deckName: String
    public let startedAt: Date
    public let duration: TimeInterval
    public let outcome: RecordingOutcome
    /// Filename relative to the recordings directory. Relative because the app
    /// container path changes between installs.
    public let fileName: String?
    /// Absolute path of a file preserved after a failure, if any.
    public let preservedFilePath: String?
    public let failureDescription: String?
    public let markers: [MarkerModel]
    public let questionChanges: [QuestionChangeModel]

    public init(
        id: UUID = UUID(),
        deckName: String,
        startedAt: Date,
        duration: TimeInterval,
        outcome: RecordingOutcome,
        fileName: String? = nil,
        preservedFilePath: String? = nil,
        failureDescription: String? = nil,
        markers: [MarkerModel] = [],
        questionChanges: [QuestionChangeModel] = []
    ) {
        self.id = id
        self.deckName = deckName
        self.startedAt = startedAt
        self.duration = duration
        self.outcome = outcome
        self.fileName = fileName
        self.preservedFilePath = preservedFilePath
        self.failureDescription = failureDescription
        self.markers = markers
        self.questionChanges = questionChanges
    }

    public var orderedMarkers: [MarkerModel] {
        markers.sorted { $0.offset < $1.offset }
    }

    public var orderedQuestionChanges: [QuestionChangeModel] {
        questionChanges.sorted { $0.offset < $1.offset }
    }

    /// A human-readable title for the library and for exports.
    public var displayTitle: String {
        deckName.isEmpty ? "Interview" : deckName
    }
}
