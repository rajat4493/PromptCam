import Foundation

/// The centre of PromptCam.
///
/// One engine owns the recording state, the question cursor, the countdown, the
/// marker timeline and the subject-surface availability. The director view and
/// the subject view both render from this single instance, which is why they
/// **cannot** disagree about the current question, the countdown, the recording
/// state, the duration or accessory availability — there is only one copy of
/// each.
///
/// It is a synchronous value type on purpose:
///
///  - every state change is a plain function call with a deterministic result,
///    so the required test scenarios need no waiting and no real clock;
///  - it is platform-independent (Foundation only), so it is the layer that can
///    be executed and trusted;
///  - all asynchronous I/O (camera, disk, Photos) is orchestrated by the iOS
///    layer, which calls in here and reads state back out.
public struct InterviewSessionEngine: Sendable {

    // MARK: - Configuration

    /// Deck name captured at session start. A snapshot, so renaming or
    /// deleting the deck mid-interview cannot affect the running session.
    public let deckName: String

    /// The question texts for this session. Snapshotted at start for the same
    /// reason, so editing a deck cannot change what the subject is being asked.
    public let questions: [String]

    public let capabilities: DeviceCapabilities
    public let flags: FeatureFlags

    /// What the operator chose to show the subject.
    public private(set) var displayOptions: SubjectDisplayOptions

    // MARK: - State

    private var machine: RecordingStateMachine
    public private(set) var currentQuestionIndex: Int
    public private(set) var markers: [MarkerModel]
    public private(set) var questionChanges: [QuestionChangeModel]
    /// Bumped on every question change so the subject view can cue a transition.
    public private(set) var questionRevision: Int
    /// When capture actually began writing. `nil` until it does.
    public private(set) var captureStartedAt: Date?
    /// Duration as last reported, used once capture has stopped.
    public private(set) var finalDuration: TimeInterval
    /// Microphone level, normalised 0...1.
    public private(set) var audioLevel: Double
    public private(set) var subjectAvailability: SubjectDisplayAvailability
    /// Temporary capture path, retained so a failed save can preserve the file.
    public private(set) var temporaryCapturePath: String?
    /// Where a capture that could not be filed actually ended up.
    ///
    /// Set by `attachRecoveredFile` once the platform layer has moved the file
    /// somewhere persistent. Preferred over `temporaryCapturePath` when
    /// reporting a result, because the temporary path is swept eventually.
    public private(set) var recoveredFilePath: String?
    /// Stable identity for this session's library row.
    ///
    /// Fixed at construction so a late reconciliation updates the row the
    /// session already wrote instead of inserting a duplicate.
    public let resultIdentifier: UUID
    /// Direction the session is capturing from. PromptCam records the subject.
    public private(set) var captureDirection: CaptureDirection

    public init(
        deckName: String,
        questions: [String],
        capabilities: DeviceCapabilities = .ordinaryPhone,
        flags: FeatureFlags = .default,
        displayOptions: SubjectDisplayOptions = .default,
        captureDirection: CaptureDirection = .rear
    ) {
        self.deckName = deckName
        self.questions = questions
        self.capabilities = capabilities
        self.flags = flags
        // Strip anything the platform cannot actually honour, at the boundary,
        // so an unsupported option can never reach the view layer.
        self.displayOptions = displayOptions.resolved(
            livePreviewSupported: flags.subjectLivePreviewEnabled
        )
        self.captureDirection = captureDirection
        self.machine = RecordingStateMachine()
        self.currentQuestionIndex = 0
        self.markers = []
        self.questionChanges = []
        self.questionRevision = 0
        self.captureStartedAt = nil
        self.finalDuration = 0
        self.audioLevel = 0
        self.subjectAvailability = capabilities.initialSubjectDisplayAvailability
        self.temporaryCapturePath = nil
        self.recoveredFilePath = nil
        self.resultIdentifier = UUID()
    }

    // MARK: - Derived state

    public var state: RecordingState { machine.state }
    public var stateHistory: [RecordingState] { machine.history }

    public var questionCount: Int { questions.count }

    /// The question currently on the subject surface.
    public var currentQuestion: String? {
        guard questions.indices.contains(currentQuestionIndex) else { return nil }
        return questions[currentQuestionIndex]
    }

    /// The next question — **director-only**. Never reaches `SubjectSnapshot`.
    public var nextQuestion: String? {
        let next = currentQuestionIndex + 1
        guard questions.indices.contains(next) else { return nil }
        return questions[next]
    }

    public var canGoToNextQuestion: Bool { currentQuestionIndex + 1 < questions.count }
    public var canGoToPreviousQuestion: Bool { currentQuestionIndex > 0 }

    /// Elapsed capture time. Grows while recording, then freezes.
    public func duration(now: Date) -> TimeInterval {
        guard let start = captureStartedAt else { return finalDuration }
        switch state {
        case .recording, .finishing:
            return max(0, now.timeIntervalSince(start))
        default:
            return finalDuration
        }
    }

    /// Whether the operator should be protected from dismissing the screen.
    public var shouldBlockDismissal: Bool { state.isBusy }

    /// Whether a subject-facing surface should be offered in the director UI.
    public var showsSubjectDisplayControls: Bool {
        subjectAvailability.shouldShowSubjectControls
    }

    /// What the subject surface is showing right now.
    ///
    /// The only channel from engine to subject view.
    public func subjectSnapshot() -> SubjectSnapshot {
        SubjectSnapshot(
            questionText: displayOptions.showsQuestion ? currentQuestion : nil,
            questionNumber: currentQuestion == nil ? nil : currentQuestionIndex + 1,
            questionCount: questions.count,
            countdownRemaining: displayOptions.showsCountdown ? state.countdownRemaining : nil,
            isRecording: displayOptions.showsRecordingStatus && state.isCapturing,
            questionRevision: questionRevision,
            options: displayOptions
        )
    }

    // MARK: - Lifecycle

    /// Begin configuring the capture pipeline.
    public mutating func prepare() throws {
        try machine.apply(.prepare)
    }

    /// The pipeline reported it is ready.
    public mutating func markPrepared() throws {
        try machine.apply(.prepareSucceeded)
    }

    /// Start a cancellable pre-roll countdown.
    public mutating func startCountdown(seconds: Int) throws {
        try machine.apply(.startCountdown(seconds: seconds))
    }

    /// One second elapsed on the countdown.
    ///
    /// Reaching zero does **not** start capture; the caller must still call
    /// `beginRecording`.
    public mutating func tickCountdown() throws {
        try machine.apply(.countdownTick)
    }

    /// Abandon the countdown. Returns to a prepared pipeline, so the operator
    /// can roll again immediately without reconfiguring the camera.
    public mutating func cancelCountdown() throws {
        try machine.apply(.cancelCountdown)
    }

    /// Begin capture.
    ///
    /// `at` seeds the timeline. `noteCaptureStarted` refines it once the
    /// pipeline confirms the first byte was written.
    public mutating func beginRecording(at now: Date, temporaryPath: String? = nil) throws {
        try machine.apply(.beginRecording)
        captureStartedAt = now
        temporaryCapturePath = temporaryPath
        // Record the question that was on screen when capture began, so an
        // export always has a question at offset zero.
        if let question = currentQuestion {
            questionChanges.append(
                QuestionChangeModel(offset: 0, index: currentQuestionIndex, text: question)
            )
        }
    }

    /// The pipeline confirmed capture actually started, at `now`.
    ///
    /// Rebases the timeline so marker offsets measure from the real first byte
    /// rather than from the button press.
    public mutating func noteCaptureStarted(at now: Date) {
        guard state.isCapturing else { return }
        captureStartedAt = now
    }

    /// Operator asked to stop. The file is not complete yet.
    public mutating func stop() throws {
        try machine.apply(.stop)
    }

    /// The operating system confirmed a finalised, stored file.
    ///
    /// The only route to a "saved" claim.
    public mutating func confirmSaved(fileName: String, duration: TimeInterval) throws {
        try machine.apply(.saveConfirmed(fileName: fileName))
        finalDuration = duration
        // The temporary file has been consumed by a successful store.
        temporaryCapturePath = nil
    }

    /// Finalising or filing the recording failed.
    ///
    /// `preservedPath` must be the surviving temporary file when one exists, so
    /// the operator's interview is never silently discarded.
    public mutating func failSave(reason: String, preservedPath: String?, duration: TimeInterval) throws {
        try machine.apply(.saveFailed(.saveFailed(reason: reason, preservedPath: preservedPath)))
        finalDuration = duration
    }

    /// A failure occurred while preparing or capturing.
    public mutating func fail(_ failure: RecordingFailure, duration: TimeInterval = 0) throws {
        try machine.apply(.fail(failure))
        if duration > 0 { finalDuration = duration }
    }

    /// An external event interrupted the session.
    public mutating func interrupt(_ reason: InterruptionReason, at now: Date) throws {
        let elapsed = duration(now: now)
        try machine.apply(.interrupt(reason))
        finalDuration = elapsed
    }

    /// Return a terminal session to idle so another take can begin.
    public mutating func reset() throws {
        try machine.apply(.reset)
        currentQuestionIndex = 0
        markers = []
        questionChanges = []
        questionRevision = 0
        captureStartedAt = nil
        finalDuration = 0
        audioLevel = 0
        temporaryCapturePath = nil
        recoveredFilePath = nil
    }

    /// Whether an event would be accepted, for enabling and disabling controls.
    public func canApply(_ event: RecordingEvent) -> Bool {
        machine.canApply(event)
    }

    // MARK: - Question navigation

    /// Move the subject-facing question.
    ///
    /// Legal at any time, including mid-recording. While recording, the change
    /// is timestamped so an editor can find each answer.
    ///
    /// Returns `false` when the index is out of range, leaving state untouched.
    @discardableResult
    public mutating func goToQuestion(_ index: Int, at now: Date) -> Bool {
        guard questions.indices.contains(index) else { return false }
        guard index != currentQuestionIndex else { return false }
        currentQuestionIndex = index
        questionRevision += 1
        if state.isCapturing, let start = captureStartedAt {
            questionChanges.append(
                QuestionChangeModel(
                    offset: max(0, now.timeIntervalSince(start)),
                    index: index,
                    text: questions[index]
                )
            )
        }
        return true
    }

    @discardableResult
    public mutating func goToNextQuestion(at now: Date) -> Bool {
        goToQuestion(currentQuestionIndex + 1, at: now)
    }

    @discardableResult
    public mutating func goToPreviousQuestion(at now: Date) -> Bool {
        goToQuestion(currentQuestionIndex - 1, at: now)
    }

    // MARK: - Markers

    /// Flag the current moment.
    ///
    /// Only legal while capturing — a marker with no recording to point into
    /// would be meaningless, so it is rejected rather than stored at offset 0.
    ///
    /// Returns the created marker, or `nil` if not recording.
    @discardableResult
    public mutating func addMarker(label: String? = nil, at now: Date) -> MarkerModel? {
        guard state.isCapturing, let start = captureStartedAt else { return nil }
        let offset = max(0, now.timeIntervalSince(start))
        let resolvedLabel: String
        if let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            resolvedLabel = label
        } else {
            resolvedLabel = "Marker \(markers.count + 1)"
        }
        let marker = MarkerModel(offset: offset, label: resolvedLabel)
        markers.append(marker)
        return marker
    }

    // MARK: - Live inputs

    public mutating func applyAudioLevel(_ level: Double) {
        audioLevel = min(1, max(0, level))
    }

    /// Update which display options the operator selected.
    ///
    /// Re-resolved against the flags, so an unsupported option cannot be
    /// enabled by the UI.
    public mutating func updateDisplayOptions(_ options: SubjectDisplayOptions) {
        displayOptions = options.resolved(livePreviewSupported: flags.subjectLivePreviewEnabled)
    }

    /// The system changed subject-surface availability.
    ///
    /// **This never affects the recording state.** Losing the subject screen is
    /// not a reason to lose the take; the interview continues and the director
    /// keeps full control.
    public mutating func updateSubjectAvailability(_ availability: SubjectDisplayAvailability) {
        // A device that cannot host the accessory stays `.unsupported`, so a
        // spurious availability callback cannot light up Duo-only controls.
        guard capabilities.supportsSubjectAccessory else {
            subjectAvailability = .unsupported
            return
        }
        subjectAvailability = availability
    }

    public mutating func updateCaptureDirection(_ direction: CaptureDirection) {
        captureDirection = direction
    }

    /// Records where a capture that could not be filed actually ended up.
    ///
    /// Called when the operating system finalises a file *after* the session has
    /// already come to rest — an interruption, then a late completion callback.
    /// Deliberately does **not** change `state`: the session ended as
    /// interrupted or failed, and a file appearing afterwards does not retrospectively
    /// make it a successful take. It only makes the file recoverable.
    ///
    /// Rejected unless the session is terminal and not already saved, so this
    /// can never be used as a back door into claiming a save.
    @discardableResult
    public mutating func attachRecoveredFile(path: String?, duration: TimeInterval) -> Bool {
        guard state.isTerminal, !state.hasConfirmedSavedFile else { return false }
        recoveredFilePath = path
        if duration > 0, finalDuration == 0 { finalDuration = duration }
        return true
    }

    // MARK: - Result

    /// The persistable outcome, available once the session has come to rest.
    ///
    /// Returns `nil` while the session is still in flight, so a caller cannot
    /// accidentally persist a half-finished interview.
    public func resultSnapshot() -> SessionResultSnapshot? {
        guard state.isTerminal, let startedAt = captureStartedAt else { return nil }

        let outcome: RecordingOutcome
        var failureDescription: String?
        var preservedPath: String?
        var fileName: String?

        switch state {
        case .saved(let name):
            outcome = .saved
            fileName = name
        case .failed(let failure):
            if case .saveFailed(_, let path) = failure {
                outcome = .saveFailed
                preservedPath = path
            } else {
                outcome = .failed
            }
            failureDescription = failure.operatorMessage
        case .interrupted(let reason):
            outcome = .interrupted
            failureDescription = reason.operatorMessage
            // A partial file is kept, never deleted, so the operator can try to
            // salvage the take.
            preservedPath = temporaryCapturePath
        default:
            return nil
        }

        // Once the platform layer has moved the file somewhere persistent, that
        // is the path worth recording: the temporary one is swept eventually.
        if let recoveredFilePath { preservedPath = recoveredFilePath }

        return SessionResultSnapshot(
            identifier: resultIdentifier,
            deckName: deckName,
            startedAt: startedAt,
            duration: finalDuration,
            outcome: outcome,
            fileName: fileName,
            preservedFilePath: preservedPath,
            failureDescription: failureDescription,
            markers: markers,
            questionChanges: questionChanges
        )
    }
}
