import Foundation

/// Drives one interview: the orchestration logic, in the layer that can test it.
///
/// ## Why this lives in `PromptCamCore`
///
/// It used to live in the iOS layer, which meant the code that decides what
/// happens when a file arrives late, when a stop races start-up, or when a
/// runtime error interleaves with a completion callback **could not be tested
/// at all** — the tests could only reach the state machine underneath it. That
/// is where the recording-lifecycle defects lived, so the orchestration moved
/// here, behind protocols, and the platform layer became a thin wrapper.
///
/// Everything asynchronous it needs is a `PromptCamCore` protocol
/// (`CaptureService`, `RecordingStore`, `RecordingRepository`, `SessionClock`),
/// so a test can script an exact sequence of capture events and assert the
/// outcome.
///
/// ## Timing is driven from outside
///
/// The countdown tick, the capture start-up timeout and the finalisation
/// timeout are **methods**, not internal timers. The platform layer schedules
/// them; tests call them directly. No test sleeps, and no timing behaviour is
/// untestable.
///
/// ## The two things it guarantees
///
/// **1. A terminal outcome and a reconciled file are separate facts.**
/// `hasPersistedOutcome` and `hasReconciledFile` are tracked independently.
/// Recording a failure must never close the door on the file that arrives
/// afterwards — doing so was how a completed interview got discarded.
///
/// **2. A file is never moved or exposed while the platform may still be
/// writing it.** `reconcileFile` runs only on a signal that means the writer is
/// finished (`recordingFinished`, `recordingFailed`) or after a bounded
/// finalisation timeout. A `runtimeError` records the outcome and waits.
@MainActor
public final class InterviewSessionCoordinator {

    // MARK: - State

    public private(set) var engine: InterviewSessionEngine
    /// Last computed elapsed time, refreshed by `refreshElapsed`.
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var alert: SessionAlertContent?
    /// The library row as last written. Updated by reconciliation.
    public private(set) var persistedRecording: InterviewRecordingModel?

    /// Whether the terminal outcome has been written to the library.
    public private(set) var hasPersistedOutcome = false
    /// Whether the physical capture file has been dealt with — stored, moved
    /// into recovery, or confirmed absent.
    public private(set) var hasReconciledFile = false
    /// Whether the platform has confirmed capture is writing.
    public private(set) var hasCaptureStarted = false
    /// Whether a stop was requested before capture was confirmed.
    public private(set) var isStopPending = false
    /// Whether the session is waiting for a completion callback before it can
    /// safely touch the file.
    public private(set) var isAwaitingFinalisation = false

    private var activeTemporaryPath: String?

    // MARK: - Dependencies

    private let captureService: any CaptureService
    private let store: any RecordingStore
    private let recordings: any RecordingRepository
    private let clock: any SessionClock

    /// Pre-roll countdown length.
    public let countdownSeconds: Int

    public init(
        deckName: String,
        questions: [String],
        displayOptions: SubjectDisplayOptions = .default,
        capabilities: DeviceCapabilities = .ordinaryPhone,
        flags: FeatureFlags = .default,
        captureService: any CaptureService,
        store: any RecordingStore,
        recordings: any RecordingRepository,
        clock: any SessionClock = SystemSessionClock(),
        countdownSeconds: Int = 3
    ) {
        self.engine = InterviewSessionEngine(
            deckName: deckName,
            questions: questions,
            capabilities: capabilities,
            flags: flags,
            displayOptions: displayOptions,
            captureDirection: .rear
        )
        self.captureService = captureService
        self.store = store
        self.recordings = recordings
        self.clock = clock
        self.countdownSeconds = countdownSeconds
    }

    // MARK: - Derived state

    public var state: RecordingState { engine.state }
    public var subjectSnapshot: SubjectSnapshot { engine.subjectSnapshot() }
    public var canAddMarker: Bool { engine.canAddMarker }
    public var blocksDismissal: Bool { engine.shouldBlockDismissal }
    public var canStartRecording: Bool {
        engine.canApply(.beginRecording) || engine.canApply(.startCountdown(seconds: countdownSeconds))
    }
    public var canStopRecording: Bool { engine.canApply(.stop) }

    public func refreshElapsed() {
        elapsed = engine.duration(now: clock.now)
    }

    public func dismissAlert() { alert = nil }

    // MARK: - Lifecycle

    /// Sweeps genuinely abandoned captures and configures the pipeline.
    ///
    /// `permissions` is resolved by the caller, which owns the platform
    /// privacy APIs; passing the resolved snapshot in keeps this testable.
    public func begin(permissions: PermissionSnapshot) async {
        // Protect both the capture in flight and every path an existing library
        // row still points at. A recorded `preservedFilePath` is a promise the
        // file is recoverable; the sweeper must not be able to break it, even
        // for a file old enough to look abandoned. (Library protection adopted
        // from the parallel fix in 90e09c3.)
        var protectedPaths = Set(activeTemporaryPath.map { [$0] } ?? [])
        if let existing = try? await recordings.loadRecordings() {
            for recording in existing {
                if let preserved = recording.preservedFilePath {
                    protectedPaths.insert(preserved)
                }
            }
        }
        try? store.cleanUpAbandonedTemporaryFiles(
            excluding: protectedPaths,
            olderThan: 3600
        )

        guard permissions.canRecord else {
            try? engine.prepare()
            if let failure = permissions.blockingFailure {
                await recordFailure(failure, offersSettings: true)
            }
            return
        }

        try? engine.prepare()
        await captureService.prepare(direction: engine.captureDirection)
    }

    public func end() async {
        await captureService.tearDown()
    }

    // MARK: - Operator intents

    /// Returns `true` if a countdown was started, so the caller knows whether
    /// to schedule ticks.
    @discardableResult
    public func tapRecord() async -> Bool {
        if engine.canApply(.startCountdown(seconds: countdownSeconds)) {
            try? engine.startCountdown(seconds: countdownSeconds)
            return true
        }
        if engine.canApply(.beginRecording) {
            await beginCapture()
        }
        return false
    }

    /// One countdown second elapsed. Returns `true` once capture has begun.
    @discardableResult
    public func countdownTick() async -> Bool {
        guard engine.state.countdownRemaining != nil else { return false }
        try? engine.tickCountdown()
        if engine.state.countdownRemaining == 0 {
            await beginCapture()
            return true
        }
        return false
    }

    public func cancelCountdown() {
        try? engine.cancelCountdown()
    }

    public func tapStop() async {
        guard engine.canApply(.stop) else { return }
        try? engine.stop()

        guard hasCaptureStarted else {
            // Capture has not begun, so asking the output to stop would do
            // nothing and the session would hang in `.finishing`. The request
            // is honoured by `handle(.recordingStarted)`.
            isStopPending = true
            return
        }
        await captureService.stopRecording()
    }

    @discardableResult
    public func addMarker(label: String? = nil) -> MarkerModel? {
        engine.addMarker(label: label, at: clock.now)
    }

    @discardableResult
    public func goToNextQuestion() -> Bool { engine.goToNextQuestion(at: clock.now) }
    @discardableResult
    public func goToPreviousQuestion() -> Bool { engine.goToPreviousQuestion(at: clock.now) }
    @discardableResult
    public func goToQuestion(_ index: Int) -> Bool { engine.goToQuestion(index, at: clock.now) }

    public func updateDisplayOptions(_ options: SubjectDisplayOptions) {
        engine.updateDisplayOptions(options)
    }

    public func updateSubjectAvailability(_ availability: SubjectDisplayAvailability) {
        // Never touches recording state: losing the subject screen is not a
        // reason to lose the interview.
        engine.updateSubjectAvailability(availability)
    }

    /// Clears a finished take so another can be recorded.
    public func reset() {
        try? engine.reset()
        hasPersistedOutcome = false
        hasReconciledFile = false
        hasCaptureStarted = false
        isStopPending = false
        isAwaitingFinalisation = false
        activeTemporaryPath = nil
        persistedRecording = nil
        elapsed = 0
    }

    // MARK: - Timeouts, scheduled by the caller

    /// Capture never confirmed within the platform's grace period.
    ///
    /// Two things have to happen, and the previous implementation did only the
    /// first: record the failure **and** stop the pipeline. Without the stop, a
    /// `recordingStarted` arriving afterwards began an unattended recording
    /// that ran until the app died.
    ///
    /// File reconciliation deliberately stays **open**: the writer may yet
    /// produce a file, and `finalisationTimedOut` is the backstop.
    public func captureStartTimedOut() async {
        guard !hasCaptureStarted else { return }
        guard engine.state.isCapturing || engine.state == .finishing else { return }

        await recordFailure(
            .captureFailed("The camera did not start recording."),
            offersSettings: false,
            reconcileFileNow: false
        )
        isAwaitingFinalisation = true

        // Stop whatever the pipeline may be doing, and make sure a late start
        // is stopped too.
        isStopPending = true
        await captureService.stopRecording()
    }

    /// The completion callback never arrived after a failure or interruption.
    ///
    /// The bounded backstop. By now the platform has had its grace period, and
    /// leaving the file in the swept capture directory would guarantee its loss
    /// — so it is moved into recovery. Moving a file whose descriptor is still
    /// open is safe on POSIX: the writer keeps writing to the same inode.
    public func finalisationTimedOut() async {
        guard isAwaitingFinalisation, !hasReconciledFile else { return }
        isAwaitingFinalisation = false
        await reconcileFile(at: activeTemporaryPath, duration: engine.duration(now: clock.now))
    }

    // MARK: - Capture events

    public func handle(_ event: CaptureEvent) async {
        switch event {
        case .ready:
            try? engine.markPrepared()

        case .configurationFailed(let failure):
            await recordFailure(failure, offersSettings: failure.isPermissionFailure)

        case .recordingStarted:
            await handleRecordingStarted()

        case .recordingFinished(let path, let duration):
            await handleCompletion(path: path, duration: duration)

        case .recordingFailed(let failure):
            // Final: the file is closed, so it is safe to reconcile now.
            await recordFailure(failure, offersSettings: false, reconcileFileNow: true)

        case .runtimeError(let failure):
            // NOT final. Record the outcome, leave the file alone, and wait for
            // the completion callback or the finalisation timeout.
            await recordFailure(failure, offersSettings: false, reconcileFileNow: false)
            isAwaitingFinalisation = true

        case .interrupted(let reason):
            await handleInterruption(reason)

        case .interruptionEnded:
            // Never resumes automatically: a second file the operator did not
            // ask for and did not see begin is worse than a short take.
            break

        case .audioLevel(let level):
            engine.applyAudioLevel(level)
        }
    }

    private func handleRecordingStarted() async {
        // A confirmation arriving after the session ended means the pipeline
        // started a recording nobody is waiting for. Stop it.
        guard engine.state.isCapturing else {
            await captureService.stopRecording()
            isAwaitingFinalisation = true
            return
        }

        hasCaptureStarted = true
        engine.noteCaptureStarted(at: clock.now)

        if isStopPending {
            isStopPending = false
            await captureService.stopRecording()
        }
    }

    private func handleCompletion(path: String, duration: TimeInterval) async {
        isAwaitingFinalisation = false

        switch engine.state {
        case .finishing:
            await storeAndConfirm(temporaryPath: path, duration: duration)

        case .recording:
            // The output stopped itself. Route through the normal stop so the
            // state machine stays legal, then file it.
            try? engine.stop()
            await storeAndConfirm(temporaryPath: path, duration: duration)

        default:
            // The session already ended. This is NOT a successful take and must
            // never be reported as saved — but the file is now final, so it can
            // be preserved and attached to the row already written.
            //
            // Reached only if the file has not already been reconciled, so a
            // duplicate completion is a no-op.
            guard !hasReconciledFile else { return }
            await reconcileFile(at: path, duration: duration)
        }
    }

    private func handleInterruption(_ reason: InterruptionReason) async {
        guard engine.canApply(.interrupt(reason)) else { return }
        let wasCapturing = engine.state.isCapturing
        try? engine.interrupt(reason, at: clock.now)

        alert = SessionAlertContent(
            title: "Recording interrupted",
            message: reason.operatorMessage + " Any video captured so far has been kept.",
            offersSettings: false
        )
        await persistOutcome()

        if wasCapturing {
            // Ask the pipeline to finalise what it has. The completion callback
            // arrives after the session is terminal and is reconciled there.
            isAwaitingFinalisation = true
            await captureService.stopRecording()
        }
    }

    // MARK: - Capture start

    private func beginCapture() async {
        guard engine.canApply(.beginRecording) else { return }

        let temporaryPath: String
        do {
            temporaryPath = try store.makeTemporaryPath()
        } catch {
            await recordFailure(.captureFailed("A file could not be created for this recording."),
                                offersSettings: false)
            return
        }

        do {
            try engine.beginRecording(at: clock.now, temporaryPath: temporaryPath)
        } catch {
            return
        }

        hasCaptureStarted = false
        isStopPending = false
        hasPersistedOutcome = false
        hasReconciledFile = false
        isAwaitingFinalisation = false
        activeTemporaryPath = temporaryPath

        await captureService.startRecording(toPath: temporaryPath)
    }

    // MARK: - Finalisation

    /// Moves a confirmed capture into permanent storage, then claims the save.
    private func storeAndConfirm(temporaryPath: String, duration: TimeInterval) async {
        guard !hasReconciledFile else { return }
        let startedAt = engine.captureStartedAt ?? clock.now

        do {
            let stored = try store.store(temporaryPath: temporaryPath, startedAt: startedAt)
            try engine.confirmSaved(fileName: stored.fileName, duration: duration)
            hasReconciledFile = true
            activeTemporaryPath = nil
        } catch {
            let reason = (error as? RecordingStoreError)?.reasonText ?? error.localizedDescription
            let preserved = movePreservedFile(from: temporaryPath)

            try? engine.failSave(reason: reason, preservedPath: preserved, duration: duration)
            engine.attachRecoveredFile(path: preserved, duration: duration)
            hasReconciledFile = true

            alert = SessionAlertContent(
                title: "Could not file the interview",
                message: reason + recoveryClause(for: preserved),
                offersSettings: false
            )
        }
        await persistOutcome(force: true)
    }

    /// Deals with the physical file once the platform has finished with it.
    ///
    /// Separate from `persistOutcome` because the outcome and the file are
    /// independent facts: the outcome may already be recorded while the file is
    /// still being written.
    private func reconcileFile(at path: String?, duration: TimeInterval) async {
        guard !hasReconciledFile else { return }
        let preserved = path.flatMap { movePreservedFile(from: $0) }
        engine.attachRecoveredFile(path: preserved, duration: duration)
        hasReconciledFile = true
        activeTemporaryPath = nil

        if let existing = alert {
            alert = SessionAlertContent(
                title: existing.title,
                message: existing.message + recoveryClause(for: preserved),
                offersSettings: existing.offersSettings
            )
        }
        await persistOutcome(force: true)
    }

    /// Records a terminal failure.
    ///
    /// `reconcileFileNow` must be `false` whenever the platform may still be
    /// writing. The failed outcome is persisted either way, so the interview is
    /// never invisible; only the *file* waits.
    private func recordFailure(
        _ failure: RecordingFailure,
        offersSettings: Bool,
        reconcileFileNow: Bool = true
    ) async {
        if engine.canApply(.fail(failure)) {
            try? engine.fail(failure, duration: engine.duration(now: clock.now))
        }

        alert = SessionAlertContent(
            title: "Recording problem",
            message: failure.operatorMessage,
            offersSettings: offersSettings
        )

        if reconcileFileNow {
            await reconcileFile(at: activeTemporaryPath, duration: engine.duration(now: clock.now))
        } else {
            await persistOutcome()
        }
    }

    /// Writes the terminal outcome to the library.
    ///
    /// Idempotent unless `force` is set, which reconciliation uses to update the
    /// row with a recovered file path. The snapshot carries a stable identifier
    /// and the repository upserts, so this updates one row rather than adding.
    private func persistOutcome(force: Bool = false) async {
        guard force || !hasPersistedOutcome else { return }
        guard let snapshot = engine.resultSnapshot() else { return }

        let model = snapshot.makeRecordingModel()
        do {
            try await recordings.save(model)
            hasPersistedOutcome = true
            persistedRecording = model
        } catch {
            alert = SessionAlertContent(
                title: "Could not update the library",
                message: "The interview details could not be filed. "
                    + (model.fileName != nil
                        ? "The video itself was saved."
                        : "Check the recordings folder for the captured file."),
                offersSettings: false
            )
        }
    }

    /// Moves a capture into recovery, returning wherever the file actually is.
    ///
    /// Returns `nil` when there is no file, so a path that does not resolve is
    /// never recorded as recoverable.
    private func movePreservedFile(from path: String) -> String? {
        if let recovered = try? store.preserveForRecovery(temporaryPath: path) {
            return recovered
        }
        return store.preservedFileExists(atPath: path) ? path : nil
    }

    private func recoveryClause(for preservedPath: String?) -> String {
        preservedPath == nil
            ? " No video file survived."
            : " The video that was captured has been kept, and you can recover it from the interview's details."
    }
}

/// Something the operator has to be told. Platform-free so the coordinator can
/// produce it and any UI can render it.
public struct SessionAlertContent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let message: String
    /// Whether an "Open Settings" button would help with this problem.
    public let offersSettings: Bool

    public init(id: UUID = UUID(), title: String, message: String, offersSettings: Bool) {
        self.id = id
        self.title = title
        self.message = message
        self.offersSettings = offersSettings
    }
}

public extension RecordingFailure {
    /// Whether sending the user to Settings could plausibly help.
    var isPermissionFailure: Bool {
        self == .cameraPermissionDenied || self == .microphonePermissionDenied
    }
}
