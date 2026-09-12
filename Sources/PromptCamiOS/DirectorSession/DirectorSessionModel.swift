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
/// stream, moves files, and persists the result. It contains no business rules
/// of its own — every state change goes through the engine, so the rules stay
/// in the layer that has tests.
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
    private let store: RecordingFileStore
    private let recordings: any RecordingRepository
    private let clock: any SessionClock
    private let permissions: AVPermissionService

    private var captureTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?

    /// The countdown length. Three seconds is long enough for the subject to
    /// look up and short enough not to feel like waiting.
    private let countdownSeconds = 3

    init(
        deckName: String,
        questions: [String],
        displayOptions: SubjectDisplayOptions,
        capabilities: DeviceCapabilities,
        flags: FeatureFlags,
        captureService: any CaptureService,
        store: RecordingFileStore,
        recordings: any RecordingRepository,
        permissions: AVPermissionService,
        clock: any SessionClock = SystemSessionClock()
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

    /// Whether the record button should be tappable. Also what stops a
    /// double-tap from reaching the engine in the first place.
    var canStartRecording: Bool {
        engine.canApply(.beginRecording) || engine.canApply(.startCountdown(seconds: countdownSeconds))
    }
    var canStopRecording: Bool { engine.canApply(.stop) }
    var canAddMarker: Bool { state.isCapturing }

    /// A warning to show before rolling, rather than an interruption during.
    var foldWarning: String? {
        guard foldPosition.mayObscureControls, !state.isCapturing else { return nil }
        return "The device is partly folded. Open it fully so the controls stay clear of the hinge."
    }

    // MARK: - Lifecycle

    /// Checks permission, cleans up old temporary captures and configures capture.
    func begin() async {
        // Abandoned captures from a previous crash are removed before a new
        // take, never during one.
        try? store.cleanUpAbandonedTemporaryFiles()

        let snapshot = await permissions.snapshot()
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
    func end() async {
        countdownTask?.cancel()
        tickerTask?.cancel()
        await captureService.tearDown()
        captureTask?.cancel()
    }

    // MARK: - Operator actions

    /// Record button. Starts a countdown, or rolls immediately if the operator
    /// has already counted down.
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
        Task { await captureService.stopRecording() }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        try? engine.cancelCountdown()
    }

    func addMarker() {
        guard engine.addMarker(at: clock.now) != nil else { return }
    }

    func nextQuestionTapped() {
        engine.goToNextQuestion(at: clock.now)
    }

    func previousQuestionTapped() {
        engine.goToPreviousQuestion(at: clock.now)
    }

    func selectQuestion(at index: Int) {
        engine.goToQuestion(index, at: clock.now)
    }

    func updateDisplayOptions(_ options: SubjectDisplayOptions) {
        engine.updateDisplayOptions(options)
    }

    func dismissAlert() {
        alert = nil
    }

    /// Clears a finished take so another can be recorded with the same deck.
    func startAnotherTake() async {
        completedRecording = nil
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

        startTicker()
        Task { await captureService.startRecording(toPath: temporaryPath) }
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
            // Rebase the timeline onto the real first byte so every marker
            // offset matches the finished file.
            engine.noteCaptureStarted(at: clock.now)

        case .recordingFinished(let path, let duration):
            await finishRecording(temporaryPath: path, duration: duration)

        case .recordingFailed(let failure):
            // A mid-recording failure is reported with whatever elapsed time is
            // known, and any partial file is left on disk.
            applyFailure(failure, duration: engine.duration(now: clock.now))

        case .interrupted(let reason):
            applyInterruption(reason)

        case .interruptionEnded:
            // Deliberately does not resume automatically. Restarting capture
            // without the operator asking would produce a second file they did
            // not intend and did not see begin.
            break

        case .audioLevel(let level):
            engine.applyAudioLevel(level)
        }
    }

    /// Moves the captured file into permanent storage.
    ///
    /// The only path to a "saved" claim, and it runs only in response to the
    /// operating system reporting a finalised file.
    private func finishRecording(temporaryPath: String, duration: TimeInterval) async {
        tickerTask?.cancel()
        let startedAt = engine.captureStartedAt ?? clock.now

        do {
            let stored = try store.store(temporaryPath: temporaryPath, startedAt: startedAt)
            try engine.confirmSaved(fileName: stored.fileName, duration: duration)
        } catch let error as RecordingStoreError {
            // The file is still on disk. Keep its path so the operator can
            // recover the interview.
            let preserved = FileManager.default.fileExists(atPath: temporaryPath) ? temporaryPath : nil
            try? engine.failSave(reason: error.reasonText, preservedPath: preserved, duration: duration)
        } catch {
            let preserved = FileManager.default.fileExists(atPath: temporaryPath) ? temporaryPath : nil
            try? engine.failSave(
                reason: error.localizedDescription,
                preservedPath: preserved,
                duration: duration
            )
        }

        await persistResult()
    }

    private func applyFailure(_ failure: RecordingFailure, duration: TimeInterval = 0) {
        tickerTask?.cancel()
        countdownTask?.cancel()
        try? engine.fail(failure, duration: duration)
        alert = SessionAlert(
            title: "Recording problem",
            message: failure.operatorMessage,
            offersSettings: failure == .cameraPermissionDenied || failure == .microphonePermissionDenied
        )
        Task { await persistResult() }
    }

    private func applyInterruption(_ reason: InterruptionReason) {
        guard engine.canApply(.interrupt(reason)) else { return }
        tickerTask?.cancel()
        countdownTask?.cancel()
        try? engine.interrupt(reason, at: clock.now)

        alert = SessionAlert(
            title: "Recording interrupted",
            message: reason.operatorMessage + " Any video captured so far has been kept.",
            offersSettings: false
        )
        Task { await persistResult() }
    }

    /// Writes the outcome to the library.
    ///
    /// Every terminal outcome is recorded, including failures and
    /// interruptions, so a lost interview leaves a trace the operator can act
    /// on rather than vanishing.
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
    /// Whether a "Open Settings" button is useful for this problem.
    let offersSettings: Bool
}
