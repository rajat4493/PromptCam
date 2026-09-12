import Foundation
import Observation
import PromptCamCore

/// SwiftUI's view of one interview.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
///
/// ## Deliberately thin
///
/// All orchestration lives in `InterviewSessionCoordinator` in `PromptCamCore`,
/// because that is the layer that can be tested. This class does exactly three
/// things the Core layer cannot:
///
///  1. schedules the timers the coordinator's timeout methods need,
///  2. consumes the capture event stream,
///  3. mirrors coordinator state into `@Observable` stored properties so
///     SwiftUI re-renders.
///
/// **No decision about recording belongs here.** If you find yourself adding an
/// `if` about state, files or failures, it belongs in the coordinator with a
/// test beside it — that separation is what the recording-lifecycle defects
/// came from lacking.
@MainActor
@Observable
final class DirectorSessionModel {

    // MARK: - Mirrored state
    //
    // Stored rather than computed: `@Observable` tracks stored-property access,
    // and the coordinator is a plain class it cannot observe.

    private(set) var state: RecordingState = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var alert: SessionAlertContent?
    private(set) var audioLevel: Double = 0
    private(set) var markerCount: Int = 0
    private(set) var currentQuestion: String?
    private(set) var nextQuestion: String?
    private(set) var questionPosition: String = ""
    private(set) var subjectSnapshot: SubjectSnapshot = .empty
    private(set) var showsSubjectControls = false
    private(set) var canAddMarker = false
    private(set) var canStartRecording = false
    private(set) var canStopRecording = false
    private(set) var canGoToNextQuestion = false
    private(set) var canGoToPreviousQuestion = false
    private(set) var blocksDismissal = false
    private(set) var completedRecording: InterviewRecordingModel?

    /// Whether the operator has switched the subject surface on.
    var isSubjectAccessoryEnabled: Bool = true

    /// Fold position, when the platform reports it. Used only to warn.
    private(set) var foldPosition: FoldPosition = .unknown

    /// Exposed for the few places the view needs configuration rather than state.
    let flags: FeatureFlags

    var formattedElapsed: String { MarkerExporter.shortTimecode(elapsed) }

    var foldWarning: String? {
        guard foldPosition.mayObscureControls, !state.isCapturing else { return nil }
        return "The device is partly folded. Open it fully so the controls stay clear of the hinge."
    }

    // MARK: - Dependencies

    private let coordinator: InterviewSessionCoordinator
    private let captureService: any CaptureService
    private let permissions: AVPermissionService

    private var captureTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var startupWatchdogTask: Task<Void, Never>?
    private var finalisationTask: Task<Void, Never>?

    /// How long to wait for the platform to confirm capture has begun.
    private let captureStartTimeout: Duration = .seconds(8)
    /// How long to wait for a completion callback before preserving the file
    /// anyway. The bounded backstop described in the coordinator.
    private let finalisationTimeout: Duration = .seconds(10)

    init(
        deckName: String,
        questions: [String],
        displayOptions: SubjectDisplayOptions,
        capabilities: DeviceCapabilities,
        flags: FeatureFlags,
        captureService: any CaptureService,
        store: any RecordingStore,
        recordings: any RecordingRepository,
        permissions: AVPermissionService,
        clock: any SessionClock = SystemSessionClock()
    ) {
        self.flags = flags
        self.captureService = captureService
        self.permissions = permissions
        self.coordinator = InterviewSessionCoordinator(
            deckName: deckName,
            questions: questions,
            displayOptions: displayOptions,
            capabilities: capabilities,
            flags: flags,
            captureService: captureService,
            store: store,
            recordings: recordings,
            clock: clock
        )
        refresh()
    }

    // MARK: - Lifecycle

    func begin() async {
        startConsumingCaptureEvents()
        await coordinator.begin(permissions: await permissions.snapshot())
        refresh()
    }

    func end() async {
        countdownTask?.cancel(); countdownTask = nil
        tickerTask?.cancel(); tickerTask = nil
        startupWatchdogTask?.cancel(); startupWatchdogTask = nil
        finalisationTask?.cancel(); finalisationTask = nil

        await coordinator.end()

        captureTask?.cancel()
        captureTask = nil
        refresh()
    }

    // MARK: - Operator actions

    func tapRecord() {
        Task {
            let startedCountdown = await coordinator.tapRecord()
            refresh()
            if startedCountdown {
                scheduleCountdown()
            } else if state.isCapturing {
                startCaptureTimers()
            }
        }
    }

    func tapStop() {
        Task {
            await coordinator.tapStop()
            tickerTask?.cancel()
            refresh()
            // Stop does not mean the file is ready; arm the backstop in case the
            // completion callback never arrives.
            scheduleFinalisationTimeout()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        coordinator.cancelCountdown()
        refresh()
    }

    func addMarker() {
        _ = coordinator.addMarker()
        refresh()
    }

    func nextQuestionTapped() { _ = coordinator.goToNextQuestion(); refresh() }
    func previousQuestionTapped() { _ = coordinator.goToPreviousQuestion(); refresh() }
    func selectQuestion(at index: Int) { _ = coordinator.goToQuestion(index); refresh() }

    func updateDisplayOptions(_ options: SubjectDisplayOptions) {
        coordinator.updateDisplayOptions(options)
        refresh()
    }

    func dismissAlert() {
        coordinator.dismissAlert()
        refresh()
    }

    func startAnotherTake() async {
        coordinator.reset()
        refresh()
        await begin()
    }

    // MARK: - Accessory and hinge callbacks

    func subjectAccessoryAvailabilityChanged(_ isAvailable: Bool) {
        coordinator.updateSubjectAvailability(
            isAvailable
                ? (subjectSnapshotIsPresented ? .presented : .availableNotEnabled)
                : .unavailable
        )
        refresh()
    }

    func subjectAccessoryPresentationChanged(_ isPresented: Bool) {
        // Losing the subject surface never stops the interview.
        coordinator.updateSubjectAvailability(isPresented ? .presented : .unavailable)
        refresh()
    }

    func foldPositionChanged(_ position: FoldPosition) {
        foldPosition = position
    }

    private var subjectSnapshotIsPresented: Bool {
        coordinator.engine.subjectAvailability == .presented
    }

    // MARK: - Timers
    //
    // The only genuinely platform-specific part of orchestration: turning
    // wall-clock time into calls the coordinator can be tested against.

    private func scheduleCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let self else { return }

                let began = await self.coordinator.countdownTick()
                self.refresh()
                if began {
                    self.startCaptureTimers()
                    return
                }
                if self.state.countdownRemaining == nil { return }
            }
        }
    }

    private func startCaptureTimers() {
        startTicker()
        scheduleStartupWatchdog()
    }

    private func startTicker() {
        tickerTask?.cancel()
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.coordinator.refreshElapsed()
                self.elapsed = self.coordinator.elapsed
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func scheduleStartupWatchdog() {
        startupWatchdogTask?.cancel()
        startupWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: self?.captureStartTimeout ?? .seconds(8))
            if Task.isCancelled { return }
            guard let self else { return }

            await self.coordinator.captureStartTimedOut()
            self.tickerTask?.cancel()
            self.refresh()
            // The coordinator has asked the pipeline to stop; give the
            // completion callback a bounded window before preserving the file.
            self.scheduleFinalisationTimeout()
        }
    }

    private func scheduleFinalisationTimeout() {
        finalisationTask?.cancel()
        finalisationTask = Task { [weak self] in
            try? await Task.sleep(for: self?.finalisationTimeout ?? .seconds(10))
            if Task.isCancelled { return }
            guard let self else { return }
            await self.coordinator.finalisationTimedOut()
            self.refresh()
        }
    }

    // MARK: - Capture events

    private func startConsumingCaptureEvents() {
        guard captureTask == nil else { return }
        captureTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.captureService.events {
                if Task.isCancelled { return }
                await self.coordinator.handle(event)

                switch event {
                case .recordingStarted:
                    self.startupWatchdogTask?.cancel()
                    self.startupWatchdogTask = nil
                case .recordingFinished, .recordingFailed:
                    self.finalisationTask?.cancel()
                    self.finalisationTask = nil
                    self.tickerTask?.cancel()
                case .runtimeError, .interrupted:
                    self.tickerTask?.cancel()
                    self.scheduleFinalisationTimeout()
                default:
                    break
                }
                self.refresh()
            }
        }
    }

    // MARK: - Mirroring

    /// Copies coordinator state into the observable properties.
    ///
    /// Called after every interaction. Cheap — all value reads — and keeps a
    /// single place where the view's idea of the session is refreshed.
    private func refresh() {
        let engine = coordinator.engine
        state = coordinator.state
        elapsed = coordinator.elapsed
        alert = coordinator.alert
        audioLevel = engine.audioLevel
        markerCount = engine.markers.count
        currentQuestion = engine.currentQuestion
        nextQuestion = engine.nextQuestion
        questionPosition = engine.questionCount > 0
            ? "\(engine.currentQuestionIndex + 1) of \(engine.questionCount)"
            : "No questions"
        subjectSnapshot = coordinator.subjectSnapshot
        showsSubjectControls = engine.showsSubjectDisplayControls
        canAddMarker = coordinator.canAddMarker
        canStartRecording = coordinator.canStartRecording
        canStopRecording = coordinator.canStopRecording
        canGoToNextQuestion = engine.canGoToNextQuestion
        canGoToPreviousQuestion = engine.canGoToPreviousQuestion
        blocksDismissal = coordinator.blocksDismissal
        completedRecording = coordinator.persistedRecording
    }
}
