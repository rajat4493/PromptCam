import Foundation

/// Everything the subject-facing surface is allowed to know.
///
/// The subject view is rendered from **this and nothing else**. Because the
/// type physically cannot carry upcoming questions, operator notes, deck
/// contents or camera controls, there is no way for director-only information
/// to reach the subject display — the compiler enforces the privacy rule that
/// the brief states in prose.
public struct SubjectSnapshot: Equatable, Sendable {
    /// The question the subject should answer, if any.
    public let questionText: String?
    /// 1-based position, so the subject can see progress ("2 of 6").
    public let questionNumber: Int?
    public let questionCount: Int
    /// Seconds remaining before capture begins, if a countdown is running.
    public let countdownRemaining: Int?
    /// Whether capture is active right now.
    public let isRecording: Bool
    /// Increments whenever the question changes, so the view can play a subtle
    /// cue without diffing strings.
    public let questionRevision: Int
    /// What this surface is permitted to display.
    public let options: SubjectDisplayOptions

    public init(
        questionText: String?,
        questionNumber: Int?,
        questionCount: Int,
        countdownRemaining: Int?,
        isRecording: Bool,
        questionRevision: Int,
        options: SubjectDisplayOptions
    ) {
        self.questionText = questionText
        self.questionNumber = questionNumber
        self.questionCount = questionCount
        self.countdownRemaining = countdownRemaining
        self.isRecording = isRecording
        self.questionRevision = questionRevision
        self.options = options
    }

    /// A blank snapshot, used before a session starts.
    public static let empty = SubjectSnapshot(
        questionText: nil,
        questionNumber: nil,
        questionCount: 0,
        countdownRemaining: nil,
        isRecording: false,
        questionRevision: 0,
        options: .default
    )

    /// Whether there is anything worth putting on the subject surface.
    ///
    /// Guards against presenting an empty screen to the interviewee.
    public var hasPresentableContent: Bool {
        if options.showsCountdown, countdownRemaining != nil { return true }
        if options.showsQuestion, let text = questionText, !text.isEmpty { return true }
        if options.showsRecordingStatus, isRecording { return true }
        return false
    }
}

/// The outcome of a session, in a form the iOS layer can persist without
/// reaching back into the live session object.
public struct SessionResultSnapshot: Equatable, Sendable {
    /// Stable identity, so a late reconciliation updates the library row the
    /// session already wrote rather than inserting a duplicate.
    public let identifier: UUID
    public let deckName: String
    public let startedAt: Date
    public let duration: TimeInterval
    public let outcome: RecordingOutcome
    /// Filename relative to the recordings directory, when a file was stored.
    public let fileName: String?
    /// Absolute path of a file kept after a failure, so nothing is lost.
    public let preservedFilePath: String?
    public let failureDescription: String?
    public let markers: [MarkerModel]
    public let questionChanges: [QuestionChangeModel]

    public init(
        identifier: UUID = UUID(),
        deckName: String,
        startedAt: Date,
        duration: TimeInterval,
        outcome: RecordingOutcome,
        fileName: String?,
        preservedFilePath: String?,
        failureDescription: String?,
        markers: [MarkerModel],
        questionChanges: [QuestionChangeModel]
    ) {
        self.identifier = identifier
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

    /// Converts to the persistable model, carrying the session's stable identity
    /// so repeated saves upsert the same row.
    public func makeRecordingModel() -> InterviewRecordingModel {
        InterviewRecordingModel(
            id: identifier,
            deckName: deckName,
            startedAt: startedAt,
            duration: duration,
            outcome: outcome,
            fileName: fileName,
            preservedFilePath: preservedFilePath,
            failureDescription: failureDescription,
            markers: markers,
            questionChanges: questionChanges
        )
    }
}
