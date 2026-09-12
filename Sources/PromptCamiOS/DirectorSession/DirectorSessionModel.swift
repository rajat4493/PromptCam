import Foundation
import Observation
import PromptCamCore

/// Orchestrates one interview: the async glue around `InterviewSessionEngine`.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
///
/// ## Division of responsibility
///
/// The engine owns *what is true*. This class owns *when things happen*: it
/// drives the countdown and elapsed-time timers, consumes the capture event
/// stream, moves files, and persists the result. It holds no business rules of
/// its own — every state change goes through the engine, so the rules stay in
/// the layer that has tests.
///
/// ## Capture lifecycle, and the three races it has to survive
///
/// 1. **Stop before capture has actually started.** The engine enters
///    `.recording` when the operator taps record, but AVFoundation does not
///    begin writing until `didStartRecording` fires. A stop in that window used
///    to reach an output that was not yet recording, so nothing happened and
///    the session sat in `.finishing` forever. Stop is now *queued* until
///    capture is confirmed, and a watchdog fails the session if capture never
///    starts at all.
/// 2. **A file finishing after the session already ended.** An interruption
///    brings the session to rest, and AVFoundation may still deliver a
///    completed file afterwards. `finalise` is the single, idempotent
///    reconciliation point: it never claims a save for a session that already
///    ended, it moves the file somewhere persistent, and it updates the library
///    row the session already wrote.
/// 3. **A second finalisation.** `hasReconciledFile` deduplicates physical file
///    callbacks without confusing an earlier runtime error with file
///    completion. A runtime error ends the logical session, but the later file
///    callback must still be accepted and reconciled.
@MainActor
@Observable
final class DirectorSessionModel {

    // MARK: - Observable state

    /// The single source of truth. Both surfaces read from here.
    private(set) var engine: InterviewSessionEngine

    /// Recomputed on a timer while recording, so the view has something to observe.
    private(set) var elapsed: TimeInterval = 0

    /// Whether the operator has switched the subject surface on. Bound directly
    /// into the scene accessory.
    var isSubjectAccessoryEnabled: Bool = true

    /// Set when something needs the operator's attention.
    private(set) var alert: SessionAlert?

    /// Fold position, when the platform reports it. Used only to warn.
    private(set) var foldPosition: FoldPosition = .unknown

    /// The recording that was just completed, for the review screen.
    private(set) var completedRecording: InterviewRecordingModel?

    // MARK: - Dependencies

    private let captureService: any CaptureService
    private let store: any RecordingStore
    private let recordings: any RecordingRepository
    private let clock: any SessionClock
    private let permissions: any PermissionService

    private var captureTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var startupWatchdogTask: Task<Void, Never>?
    private var finalisationWatchdogTask: Task<Void, Never>?

    // MARK: - Capture lifecycle flags

    /// True once AVFoundation has confirmed the first byte is on disk.
    private var hasCaptureStarted = false
    /// True when the operator asked to stop before capture was confirmed.
    private var stopRequestedBeforeStart = false
    /// True only after the physical capture file has produced its terminal
    /// callback. A runtime error does not set this: AVFoundation may still
    /// finish a recoverable file afterwards.
    private var hasReconciledFile = false
    /// The capture in flight, so the sweeper can be told to leave it alone.
    private var activeTemporaryPath: String?

    /// The countdown length. Three seconds is long enough for the subject to
    /// look up and short enough not to feel like waiting.
    private let countdownSeconds: Int

    /// How long to wait for `didStartRecording` before giving up.
    ///
    /// Without this, a capture that never starts leaves the session stuck in
    /// `.finishing` with no way out and no explanation.
    private let captureStartTimeout: Duration
    /// Time allowed for AVFoundation to answer a requested stop with a terminal
    /// file callback. On expiry the session is torn down and any surviving path
    /// is recorded without moving a potentially open file.
    private let captureFinalisationTimeout: Duration

    init(
        deckName: String,
        questions: [String],
        displayOptions: SubjectDisplayOptions,
        capabilities: DeviceCapabilities,
        flags: FeatureFlags,
        captureService: any CaptureService,
        store: any RecordingStore,
        recordings: any RecordingRepository,
        permissions: any PermissionService,
        clock: any SessionClock = SystemSessionClock(),
        countdownSeconds: Int = 3,
        captureStartTimeout: Duration = .seconds(8),
        captureFinalisationTimeout: Duration = .seconds(8)
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
        self.permissions = permissions
        self.clock = clock
        self.countdownSeconds = countdownSeconds
        self.captureStartTimeout = captureStartTimeout
        self.captureFinalisationTimeout = captureFinalisationTimeout
    }

    // MARK: - Derived view state

    var state: RecordingState { engine.state }
    var currentQuestion: String? { engine.currentQuestion }
    var nextQuestion: String? { engine.nextQuestion }
    var questionPosition: String {
        guard engine.questionCount > 0 else { return "No questions" }
        return "\(engine.currentQuestionIndex + 1) of \(engine.questionCount)"
    }
    var audioLevel: Double { engine.audioLevel }
    var markerCount: Int { engine.markers.count }
    var showsSubjectControls: Bool { engine.showsSubjectDisplayControls }
    var subjectSnapshot: SubjectSnapshot { engine.subjectSnapshot() }
    var formattedElapsed: String { MarkerExporter.shortTimecode(elapsed) }

    /// Blocks swipe-to-dismiss and the close button while a take is live.
    var blocksDismissal: Bool { engine.shouldBlockDismissal }

    var canStartRecording: Bool {
        engine.canApply(.beginRecording) || engine.canApply(.startCountdown(seconds: countdownSeconds))
    }
    /// Stop stays available during the pre-start window — the request is queued
    /// rather than dropped, so the button must not be disabled there.
    var canStopRecording: Bool { engine.canApply(.stop) }
    /// A state-machine `.recording` begins at the button press, slightly before
    /// AVFoundation confirms the first byte. Timestamped actions stay disabled
    /// until that confirmation so no event can point before the media begins.
    var canAddMarker: Bool { hasCaptureStarted && state.isCapturing }

    /// A warning to show before rolling, rather than an interruption during.
    var foldWarning: String? {
        guard foldPosition.mayObscureControls, !state.isCapturing else { return nil }
        return "The device is partly folded. Open it fully so the controls stay clear of the hinge."
    }

    // MARK: - Lifecycle

    /// Checks permission, sweeps genuinely abandoned captures, configures capture.
    func begin() async {
        // Sweep only captures that are old AND not in use. This used to delete
        // every file in the capture directory, which destroyed the very
        // recordings the app had promised to keep.
        var protectedPaths = Set(activeTemporaryPath.map { [$0] } ?? [])
        if let existing = try? await recordings.loadRecordings() {
            protectedPaths.formUnion(existing.compactMap(\.preservedFilePath))
        }
        try? store.cleanUpAbandonedTemporaryFiles(
            excluding: protectedPaths,
            olderThan: RecordingFileStore.abandonedCaptureAge
        )

        let snapshot = PermissionSnapshot(
            camera: await permissions.status(for: .camera),
            microphone: await permissions.status(for: .microphone)
        )
        guard snapshot.canRecord else {
            // Enter `.preparing` first so the failure is a legal transition and
            // the UI has a specific cause to explain.
            try? engine.prepare()
            if let failure = snapshot.blockingFailure {
                applyFailure(failure)
            }
            return
        }

        startConsumingCaptureEvents()

        do {
            try engine.prepare()
        } catch {
            // Already prepared: harmless, and not worth surfacing.
            return
        }
        await captureService.prepare(direction: engine.captureDirection)
    }

    /// Releases the camera and stops every timer.
    ///
    /// Clears `captureTask` as well as cancelling it, so a later `begin()` can
    /// subscribe again instead of silently refusing to.
    func end() async {
        countdownTask?.cancel(); countdownTask = nil
        tickerTask?.cancel(); tickerTask = nil
        startupWatchdogTask?.cancel(); startupWatchdogTask = nil
        finalisationWatchdogTask?.cancel(); finalisationWatchdogTask = nil

        await captureService.tearDown()

        captureTask?.cancel()
        captureTask = nil
    }

    // MARK: - Operator actions

    /// Record button. Starts a countdown, or rolls immediately if the countdown
    /// has already finished.
    func tapRecord() {
        // Both branches ask the engine whether the move is legal, so a fast
        // double-tap is absorbed here and would be rejected again by the engine
        // even if it were not. From `.recording` or `.finishing` neither is
        // legal and the tap does nothing.
        if engine.canApply(.startCountdown(seconds: countdownSeconds)) {
            startCountdown()
        } else if engine.canApply(.beginRecording) {
            beginCapture()
        }
    }

    func tapStop() {
        guard engine.canApply(.stop) else { return }
        do {
            try engine.stop()
        } catch {
            return
        }
        tickerTask?.cancel()

        guard hasCaptureStarted else {
            // Capture has not actually begun, so asking the output to stop
            // would do nothing and the session would hang in `.finishing`.
            // Remember the request; `.recordingStarted` honours it immediately.
            stopRequestedBeforeStart = true
            return
        }
        startFinalisationWatchdog()
        Task { await captureService.stopRecording() }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        try? engine.cancelCountdown()
    }

    func addMarker() {
        guard canAddMarker else { return }
        _ = engine.addMarker(at: clock.now)
    }

    func nextQuestionTapped() { navigate(to: engine.currentQuestionIndex + 1) }
    func previousQuestionTapped() { navigate(to: engine.currentQuestionIndex - 1) }
    func selectQuestion(at index: Int) { navigate(to: index) }
    func updateDisplayOptions(_ options: SubjectDisplayOptions) { engine.updateDisplayOptions(options) }
    func dismissAlert() { alert = nil }

    /// Clears a finished take so another can be recorded with the same deck.
    func startAnotherTake() async {
        completedRecording = nil
        hasCaptureStarted = false
        stopRequestedBeforeStart = false
        hasReconciledFile = false
        activeTemporaryPath = nil
        finalisationWatchdogTask?.cancel(); finalisationWatchdogTask = nil
        try? engine.reset()
        await begin()
    }

    // MARK: - Accessory callbacks
    //
    // The system is the only source of availability truth; these are the only
    // places that set it.

    func subjectAccessoryAvailabilityChanged(_ isAvailable: Bool) {
        if isAvailable {
            // Preserve `.presented` if content is already on screen.
            if engine.subjectAvailability != .presented {
                engine.updateSubjectAvailability(.availableNotEnabled)
            }
        } else {
            engine.updateSubjectAvailability(.unavailable)
        }
    }

    func subjectAccessoryPresentationChanged(_ isPresented: Bool) {
        // Losing the subject surface never stops the interview.
        engine.updateSubjectAvailability(isPresented ? .presented : .unavailable)
    }

    func foldPositionChanged(_ position: FoldPosition) {
        foldPosition = position
    }

    // MARK: - Countdown

    private func startCountdown() {
        do {
            try engine.startCountdown(seconds: countdownSeconds)
        } catch {
            return
        }

        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self else { return }

                // A cancel that raced this tick leaves the engine out of
                // countdown, and the tick is simply rejected.
                guard self.state.countdownRemaining != nil else { return }
                try? self.engine.tickCountdown()

                if self.state.countdownRemaining == 0 {
                    self.beginCapture()
                    return
                }
            }
        }
    }

    // MARK: - Capture

    private func beginCapture() {
        guard engine.canApply(.beginRecording) else { return }

        let temporaryPath: String
        do {
            temporaryPath = try store.makeTemporaryPath()
        } catch {
            applyFailure(.captureFailed("A file could not be created for this recording."))
            return
        }

        do {
            try engine.beginRecording(at: clock.now, temporaryPath: temporaryPath)
        } catch {
            return
        }

        hasCaptureStarted = false
        stopRequestedBeforeStart = false
        hasReconciledFile = false
        activeTemporaryPath = temporaryPath

        startTicker()
        startStartupWatchdog()
        Task { await captureService.startRecording(toPath: temporaryPath) }
    }

    /// Fails the session if capture never actually starts.
    ///
    /// Without this a pipeline that accepts `startRecording` but never reports
    /// `didStartRecording` leaves the operator staring at a running timer that
    /// is recording nothing.
    private func startStartupWatchdog() {
        startupWatchdogTask?.cancel()
        startupWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: self?.captureStartTimeout ?? .seconds(8))
            if Task.isCancelled { return }
            guard let self, !self.hasCaptureStarted else { return }
            guard self.state.isCapturing || self.state == .finishing else { return }

            await self.failActiveCapture(
                .captureFailed("The camera did not start recording. Nothing was captured.")
            )
        }
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.elapsed = self.engine.duration(now: self.clock.now)
                // Twice a second: the timer shows whole seconds, and this keeps
                // it from visibly lagging without waking constantly.
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func startConsumingCaptureEvents() {
        guard captureTask == nil else { return }
        captureTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.captureService.events {
                if Task.isCancelled { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: CaptureEvent) async {
        switch event {
        case .ready:
            try? engine.markPrepared()

        case .configurationFailed(let failure):
            applyFailure(failure)

        case .recordingStarted:
            hasCaptureStarted = true
            startupWatchdogTask?.cancel()
            startupWatchdogTask = nil
            // Rebase the timeline onto the real first byte so every marker
            // offset matches the finished file.
            engine.noteCaptureStarted(at: clock.now)

            if stopRequestedBeforeStart {
                // The operator asked to stop during the start-up window. Honour
                // it now that there is actually something to stop.
                stopRequestedBeforeStart = false
                await captureService.stopRecording()
                startFinalisationWatchdog()
            }

        case .recordingFinished(let path, let duration):
            await finalise(temporaryPath: path, duration: duration)

        case .recordingFailed(let failure):
            await finaliseFailure(failure)

        case .runtimeError(let failure):
            await failActiveCapture(failure)

        case .interrupted(let reason):
            await applyInterruption(reason)

        case .interruptionEnded:
            // Deliberately does not resume automatically. Restarting capture
            // without the operator asking would produce a second file they did
            // not intend and did not see begin.
            break

        case .audioLevel(let level):
            engine.applyAudioLevel(level)
        }
    }

    // MARK: - Finalisation
    //
    // One idempotent entry point per take. Everything that ends a capture comes
    // through here so a late callback cannot contradict a session that has
    // already come to rest.

    /// The operating system finalised a file.
    private func finalise(temporaryPath: String, duration: TimeInterval) async {
        guard !hasReconciledFile else { return }
        hasReconciledFile = true

        tickerTask?.cancel()
        startupWatchdogTask?.cancel()
        finalisationWatchdogTask?.cancel()

        switch engine.state {
        case .finishing:
            await storeAndConfirm(temporaryPath: temporaryPath, duration: duration)

        case .recording:
            // Capture ended without the operator asking — the output stopped
            // itself. Route through the normal stop so the state machine stays
            // legal, then file it like any other completed take.
            try? engine.stop()
            await storeAndConfirm(temporaryPath: temporaryPath, duration: duration)

        default:
            // The session already ended (interrupted, or failed) and the file
            // arrived afterwards. It is NOT a successful take and must not be
            // reported as saved. Move it somewhere persistent and attach it to
            // the row already written, so the operator can recover it.
            await reconcileLateFile(temporaryPath: temporaryPath, duration: duration)
        }
    }

    /// Capture ended without producing a usable file.
    private func finaliseFailure(_ failure: RecordingFailure) async {
        guard !hasReconciledFile else { return }
        hasReconciledFile = true

        tickerTask?.cancel()
        startupWatchdogTask?.cancel()
        finalisationWatchdogTask?.cancel()

        // Whatever partial file exists belongs to the operator. Move it out of
        // the sweeper's reach before reporting.
        let preserved = preserveActiveCapture()
        let elapsedNow = engine.duration(now: clock.now)

        if engine.canApply(.fail(failure)) {
            try? engine.fail(failure, duration: elapsedNow)
            engine.attachRecoveredFile(path: preserved, duration: elapsedNow)
        } else {
            engine.attachRecoveredFile(path: preserved, duration: elapsedNow)
        }

        alert = SessionAlert(
            title: "Recording problem",
            message: failure.operatorMessage + recoveryClause(for: preserved),
            offersSettings: false
        )
        await persistResult()
    }

    /// Ends the logical session after a runtime/startup failure while leaving
    /// the physical file lifecycle open for its authoritative delegate event.
    private func failActiveCapture(_ failure: RecordingFailure) async {
        guard engine.canApply(.fail(failure)) else { return }
        tickerTask?.cancel()
        countdownTask?.cancel()
        startupWatchdogTask?.cancel()

        let hadCapturePath = activeTemporaryPath != nil
        try? engine.fail(failure, duration: engine.duration(now: clock.now))
        alert = SessionAlert(
            title: "Recording problem",
            message: failure.operatorMessage
                + (hadCapturePath ? " PromptCam is finalising any video captured so far." : ""),
            offersSettings: false
        )
        await persistResult()

        guard hadCapturePath else { return }
        // Works whether capture already started or is still in the start-up
        // window; the platform service queues an early stop itself.
        stopRequestedBeforeStart = !hasCaptureStarted
        await captureService.stopRecording()
        startFinalisationWatchdog()
    }

    private func startFinalisationWatchdog() {
        finalisationWatchdogTask?.cancel()
        finalisationWatchdogTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.captureFinalisationTimeout)
            if Task.isCancelled || self.hasReconciledFile { return }

            // Stop the session before exposing a fallback path. We deliberately
            // do not move it: a delayed delegate callback may still arrive with
            // the authoritative final file and will then move/reconcile it.
            await self.captureService.tearDown()
            guard let path = self.activeTemporaryPath else { return }
            // Record the expected path even if the filesystem has not exposed
            // it yet. The recovery UI independently checks existence, while the
            // cleanup pass must protect this path if it appears after teardown.
            _ = self.engine.attachRecoveredFile(
                path: path,
                duration: self.engine.duration(now: self.clock.now)
            )
            await self.persistResult()
        }
    }

    /// Moves a confirmed capture into permanent storage, then — and only then —
    /// claims the save.
    private func storeAndConfirm(temporaryPath: String, duration: TimeInterval) async {
        let startedAt = engine.captureStartedAt ?? clock.now
        do {
            let stored = try store.store(temporaryPath: temporaryPath, startedAt: startedAt)
            try engine.confirmSaved(fileName: stored.fileName, duration: duration)
            activeTemporaryPath = nil
        } catch {
            // Filing failed. The capture is still at its temporary path, so move
            // it somewhere the sweeper cannot reach and record where it went.
            let reason = (error as? RecordingStoreError)?.reasonText ?? error.localizedDescription
            let preserved = preserveActiveCapture(fallbackPath: temporaryPath)

            try? engine.failSave(reason: reason, preservedPath: preserved, duration: duration)
            engine.attachRecoveredFile(path: preserved, duration: duration)

            alert = SessionAlert(
                title: "Could not file the interview",
                message: reason + recoveryClause(for: preserved),
                offersSettings: false
            )
        }
        await persistResult()
    }

    /// Handles a file that finished after the session already ended.
    ///
    /// Never claims a save. Updates the existing library row so the interview is
    /// recoverable rather than orphaned on disk with nothing pointing at it.
    private func reconcileLateFile(temporaryPath: String, duration: TimeInterval) async {
        let preserved = preserveActiveCapture(fallbackPath: temporaryPath)
        engine.attachRecoveredFile(path: preserved, duration: duration)
        await persistResult()
    }

    /// Moves the in-flight capture into the recovery directory.
    ///
    /// Returns the path the file actually occupies afterwards — the recovery
    /// path on success, the original path if the move failed but the file is
    /// still there, or `nil` if there is no file at all. Never reports a path
    /// that does not exist.
    private func preserveActiveCapture(fallbackPath: String? = nil) -> String? {
        guard let candidate = fallbackPath ?? activeTemporaryPath ?? engine.temporaryCapturePath else {
            return nil
        }
        if let recovered = try? store.preserveForRecovery(temporaryPath: candidate) {
            activeTemporaryPath = nil
            return recovered
        }
        return store.preservedFileExists(atPath: candidate) ? candidate : nil
    }

    private func recoveryClause(for preservedPath: String?) -> String {
        preservedPath == nil
            ? " No video file survived."
            : " The video that was captured has been kept, and you can recover it from the interview's details."
    }

    private func applyFailure(_ failure: RecordingFailure, duration: TimeInterval = 0) {
        tickerTask?.cancel()
        countdownTask?.cancel()
        startupWatchdogTask?.cancel()

        guard engine.canApply(.fail(failure)) else { return }
        try? engine.fail(failure, duration: duration)

        let preserved = preserveActiveCapture()
        engine.attachRecoveredFile(path: preserved, duration: duration)

        alert = SessionAlert(
            title: "Recording problem",
            message: failure.operatorMessage,
            offersSettings: failure == .cameraPermissionDenied || failure == .microphonePermissionDenied
        )
        Task { await persistResult() }
    }

    private func applyInterruption(_ reason: InterruptionReason) async {
        guard engine.canApply(.interrupt(reason)) else { return }
        tickerTask?.cancel()
        countdownTask?.cancel()

        let wasCapturing = state.isCapturing
        try? engine.interrupt(reason, at: clock.now)

        alert = SessionAlert(
            title: "Recording interrupted",
            message: reason.operatorMessage
                + (wasCapturing ? " PromptCam is finalising any video captured so far." : ""),
            offersSettings: false
        )
        await persistResult()

        if wasCapturing {
            // Ask the pipeline to finalise what it has. The completion callback
            // arrives after the session is already terminal, and `finalise`
            // routes it to `reconcileLateFile` — which preserves the file and
            // updates this row rather than claiming a save.
            await captureService.stopRecording()
            startFinalisationWatchdog()
        }
    }

    /// Question navigation remains responsive while the camera starts, but a
    /// pre-start change is not written into the media timeline. Once the first
    /// byte exists, the engine records the change normally.
    private func navigate(to index: Int) {
        if state.isCapturing, !hasCaptureStarted {
            _ = engine.goToQuestion(index, at: clock.now, recordTimeline: false)
            return
        }
        _ = engine.goToQuestion(index, at: clock.now)
    }

    /// Writes the outcome to the library.
    ///
    /// Every terminal outcome is recorded, including failures and
    /// interruptions, so a lost interview leaves a trace the operator can act
    /// on rather than vanishing. The snapshot carries a stable identifier, so
    /// calling this again after a late reconciliation updates the same row.
    private func persistResult() async {
        guard let snapshot = engine.resultSnapshot() else { return }
        let model = snapshot.makeRecordingModel()
        do {
            try await recordings.save(model)
            completedRecording = model
        } catch {
            alert = SessionAlert(
                title: "Could not update the library",
                message: "The interview details could not be filed. "
                    + (model.fileName != nil
                        ? "The video itself was saved."
                        : "Check the recordings folder for the captured file."),
                offersSettings: false
            )
        }
    }
}

/// Something the operator has to be told.
struct SessionAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    /// Whether an "Open Settings" button is useful for this problem.
    let offersSettings: Bool
}
