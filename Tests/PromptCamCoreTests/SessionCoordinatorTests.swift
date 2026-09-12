import Testing
import Foundation
@testable import PromptCamCore

/// Orchestration tests against the **real** `InterviewSessionCoordinator`.
///
/// The earlier regression suite only reached `InterviewSessionEngine` and a
/// duplicate store, which is precisely why the lifecycle defects survived it:
/// the orchestration was in the iOS layer and could not be exercised at all.
/// These tests script exact capture-event sequences — including the
/// out-of-order arrivals that caused each defect — against the production
/// coordinator, the real `FakeCaptureService` call log, and a store backed by a
/// real temporary directory.
///
/// `STATICALLY_REVIEWED`: written, never executed. No Swift toolchain is
/// reachable here. See docs/VERIFICATION_LEDGER.md A3.

@MainActor
private struct Harness {
    let coordinator: InterviewSessionCoordinator
    let capture: FakeCaptureService
    let store: TestRecordingStore
    let recordings: InMemoryRecordingRepository
    let clock: ManualSessionClock

    init(questions: [String] = ["Q1", "Q2", "Q3"]) {
        let capture = FakeCaptureService()
        let store = TestRecordingStore()
        let recordings = InMemoryRecordingRepository()
        let clock = ManualSessionClock()
        self.capture = capture
        self.store = store
        self.recordings = recordings
        self.clock = clock
        self.coordinator = InterviewSessionCoordinator(
            deckName: "Test deck",
            questions: questions,
            captureService: capture,
            store: store,
            recordings: recordings,
            clock: clock
        )
    }

    /// Prepares, then drives the countdown to zero so capture begins.
    func rollNow() async {
        await coordinator.begin(permissions: .bothAuthorized)
        await coordinator.handle(.ready)
        _ = await coordinator.tapRecord()
        for _ in 0..<3 { _ = await coordinator.countdownTick() }
    }

    /// The path the capture service was asked to record to.
    var capturedPath: String? {
        for call in capture.calls {
            if case .startRecording(let path) = call { return path }
        }
        return nil
    }

    var stopCount: Int {
        capture.calls.filter { $0 == .stopRecording }.count
    }

    func writeCaptureFile() throws {
        guard let path = capturedPath else { return }
        try store.writeFakeCapture(at: path)
    }
}

@Suite("Orchestration: capture start-up timeout")
@MainActor
struct CaptureStartupTimeoutTests {

    @Test("A timeout stops the pipeline — it must not leave capture running")
    func timeoutRequestsStop() async throws {
        let h = Harness()
        await h.rollNow()
        #expect(h.coordinator.state == .recording)
        #expect(h.stopCount == 0)

        await h.coordinator.captureStartTimedOut()

        // The defect: the old watchdog failed the session but never stopped
        // the pipeline, so a late start began an unattended recording.
        #expect(h.stopCount == 1, "The watchdog must ask the pipeline to stop")
        #expect(h.coordinator.state.isTerminal)
        #expect(h.coordinator.state.hasConfirmedSavedFile == false)
    }

    @Test("A delayed recordingStarted after a timeout is stopped, not adopted")
    func delayedStartAfterTimeoutIsStopped() async throws {
        let h = Harness()
        await h.rollNow()
        await h.coordinator.captureStartTimedOut()
        let stopsAfterTimeout = h.stopCount

        // The pipeline finally reports it started — after the session ended.
        await h.coordinator.handle(.recordingStarted)

        #expect(h.stopCount == stopsAfterTimeout + 1,
                "A late start on a terminal session must be stopped immediately")
        #expect(h.coordinator.state.isTerminal)
        // It must NOT be treated as a live take.
        #expect(h.coordinator.state.isCapturing == false)
        #expect(h.coordinator.canAddMarker == false)
    }

    @Test("A timeout leaves file reconciliation open for a late completion")
    func timeoutKeepsReconciliationOpen() async throws {
        let h = Harness()
        await h.rollNow()
        try h.writeCaptureFile()

        await h.coordinator.captureStartTimedOut()
        #expect(h.coordinator.hasReconciledFile == false,
                "The file must stay untouched while the writer may still hold it")
        #expect(h.coordinator.isAwaitingFinalisation)

        // The completion callback eventually arrives with a real file.
        let path = try #require(h.capturedPath)
        await h.coordinator.handle(.recordingFinished(path: path, duration: 3))

        #expect(h.coordinator.hasReconciledFile)
        let stored = try await h.recordings.loadRecordings()
        #expect(stored.count == 1)
        #expect(stored[0].outcome.isPlayable == false, "A timed-out take is not a save")
        #expect(stored[0].preservedFilePath != nil, "The file must be recoverable")
    }

    @Test("The finalisation timeout is the backstop when no completion arrives")
    func finalisationTimeoutPreservesFile() async throws {
        let h = Harness()
        await h.rollNow()
        try h.writeCaptureFile()
        await h.coordinator.captureStartTimedOut()

        #expect(h.coordinator.hasReconciledFile == false)
        await h.coordinator.finalisationTimedOut()

        #expect(h.coordinator.hasReconciledFile)
        let stored = try await h.recordings.loadRecordings()
        #expect(stored[0].preservedFilePath != nil)
        // And it survives a subsequent sweep, because it left the temp folder.
        try h.store.cleanUpAbandonedTemporaryFiles(excluding: [], olderThan: 0)
        let path = try #require(stored[0].preservedFilePath)
        #expect(FileManager.default.fileExists(atPath: path))
    }
}

@Suite("Orchestration: runtime error then completion")
@MainActor
struct RuntimeErrorThenCompletionTests {

    @Test("A runtime error does NOT touch the file — the writer may still hold it")
    func runtimeErrorLeavesFileAlone() async throws {
        let h = Harness()
        await h.rollNow()
        await h.coordinator.handle(.recordingStarted)
        try h.writeCaptureFile()
        let path = try #require(h.capturedPath)

        await h.coordinator.handle(.runtimeError(.captureFailed("pipeline error")))

        // Outcome recorded...
        #expect(h.coordinator.hasPersistedOutcome)
        #expect(h.coordinator.state.isTerminal)
        // ...but the file is untouched and not yet exposed.
        #expect(h.coordinator.hasReconciledFile == false)
        #expect(FileManager.default.fileExists(atPath: path),
                "The capture must still be where the writer left it")
        let stored = try await h.recordings.loadRecordings()
        #expect(stored[0].preservedFilePath == nil,
                "A file that may still be open must not be offered for recovery")
    }

    @Test("The completion after a runtime error is NOT discarded")
    func completionAfterRuntimeErrorIsReconciled() async throws {
        let h = Harness()
        await h.rollNow()
        await h.coordinator.handle(.recordingStarted)
        try h.writeCaptureFile()
        let path = try #require(h.capturedPath)

        await h.coordinator.handle(.runtimeError(.captureFailed("pipeline error")))
        // This is the defect the old `hasFinalised` flag caused: the completed
        // file arrived and was thrown away.
        await h.coordinator.handle(.recordingFinished(path: path, duration: 12))

        #expect(h.coordinator.hasReconciledFile)
        let stored = try await h.recordings.loadRecordings()
        #expect(stored.count == 1, "One row, updated — not two")
        #expect(stored[0].outcome.isPlayable == false)
        let preserved = try #require(stored[0].preservedFilePath,
                                     "The completed file must become recoverable")
        #expect(FileManager.default.fileExists(atPath: preserved))
    }

    @Test("A final recordingFailed may reconcile immediately")
    func finalFailureReconcilesImmediately() async throws {
        let h = Harness()
        await h.rollNow()
        await h.coordinator.handle(.recordingStarted)
        try h.writeCaptureFile()

        // `.recordingFailed` comes from the completion callback: file is closed.
        await h.coordinator.handle(.recordingFailed(.captureFailed("write failed")))

        #expect(h.coordinator.hasReconciledFile)
        let stored = try await h.recordings.loadRecordings()
        #expect(stored[0].outcome.isPlayable == false)
        #expect(stored[0].preservedFilePath != nil)
    }
}

@Suite("Orchestration: duplicate and stray completions")
@MainActor
struct DuplicateCompletionTests {

    @Test("A duplicate completion does not double-file or duplicate the row")
    func duplicateCompletionIsIdempotent() async throws {
        let h = Harness()
        await h.rollNow()
        await h.coordinator.handle(.recordingStarted)
        try h.writeCaptureFile()
        let path = try #require(h.capturedPath)

        await h.coordinator.tapStop()
        await h.coordinator.handle(.recordingFinished(path: path, duration: 10))
        #expect(h.coordinator.state.hasConfirmedSavedFile)

        let fileNameAfterFirst = h.coordinator.state.savedFileName

        // The same callback again, and a third time for good measure.
        await h.coordinator.handle(.recordingFinished(path: path, duration: 10))
        await h.coordinator.handle(.recordingFinished(path: path, duration: 10))

        #expect(h.coordinator.state.savedFileName == fileNameAfterFirst)
        let stored = try await h.recordings.loadRecordings()
        #expect(stored.count == 1)
        #expect(stored[0].outcome == .saved)
    }

    @Test("A completion after a successful save cannot downgrade the outcome")
    func completionAfterSaveCannotDowngrade() async throws {
        let h = Harness()
        await h.rollNow()
        await h.coordinator.handle(.recordingStarted)
        try h.writeCaptureFile()
        let path = try #require(h.capturedPath)
        await h.coordinator.tapStop()
        await h.coordinator.handle(.recordingFinished(path: path, duration: 10))

        await h.coordinator.handle(.runtimeError(.captureFailed("late noise")))

        #expect(h.coordinator.state.hasConfirmedSavedFile,
                "A saved take must stay saved")
        let stored = try await h.recordings.loadRecordings()
        #expect(stored[0].outcome == .saved)
        #expect(stored[0].preservedFilePath == nil)
    }
}

@Suite("Orchestration: interruption")
@MainActor
struct InterruptionOrchestrationTests {

    @Test("An interruption asks the pipeline to finalise, then reconciles")
    func interruptionRequestsStopThenReconciles() async throws {
        let h = Harness()
        await h.rollNow()
        await h.coordinator.handle(.recordingStarted)
        try h.writeCaptureFile()
        let path = try #require(h.capturedPath)
        h.clock.advance(by: 25)

        await h.coordinator.handle(.interrupted(.audioSessionLost))

        #expect(h.coordinator.state == .interrupted(reason: .audioSessionLost))
        #expect(h.stopCount == 1, "The pipeline must be asked to finalise what it has")
        #expect(h.coordinator.hasPersistedOutcome)
        #expect(h.coordinator.hasReconciledFile == false)

        await h.coordinator.handle(.recordingFinished(path: path, duration: 25))

        let stored = try await h.recordings.loadRecordings()
        #expect(stored.count == 1, "Reconciliation updates the row, never adds one")
        #expect(stored[0].outcome == .interrupted)
        #expect(stored[0].outcome.isPlayable == false)
        #expect(stored[0].preservedFilePath != nil)
    }

    @Test("An interruption with no completion still leaves a visible record")
    func interruptionWithoutCompletion() async throws {
        let h = Harness()
        await h.rollNow()
        await h.coordinator.handle(.recordingStarted)
        try h.writeCaptureFile()
        h.clock.advance(by: 18)

        await h.coordinator.handle(.interrupted(.backgrounded))
        // No completion callback ever arrives.

        let stored = try await h.recordings.loadRecordings()
        #expect(stored.count == 1, "The interview must not vanish")
        #expect(stored[0].outcome == .interrupted)
        #expect(stored[0].duration == 18)

        // The backstop then makes the file recoverable.
        await h.coordinator.finalisationTimedOut()
        let reconciled = try await h.recordings.loadRecordings()
        #expect(reconciled[0].preservedFilePath != nil)
    }
}

@Suite("Orchestration: stop during start-up")
@MainActor
struct StopDuringStartupOrchestrationTests {

    @Test("A stop before capture is confirmed is queued, not dropped")
    func stopBeforeStartIsQueued() async throws {
        let h = Harness()
        await h.rollNow()
        #expect(h.coordinator.state == .recording)

        await h.coordinator.tapStop()

        #expect(h.coordinator.state == .finishing)
        #expect(h.coordinator.isStopPending, "The stop must be remembered")
        #expect(h.stopCount == 0, "Stopping an output that has not started does nothing")

        // The pipeline confirms it started; the queued stop fires now.
        await h.coordinator.handle(.recordingStarted)
        #expect(h.stopCount == 1, "The queued stop must be honoured on confirmation")
        #expect(h.coordinator.isStopPending == false)
    }

    @Test("The queued-stop path still reaches a confirmed save")
    func queuedStopStillSaves() async throws {
        let h = Harness()
        await h.rollNow()
        try h.writeCaptureFile()
        let path = try #require(h.capturedPath)

        await h.coordinator.tapStop()
        await h.coordinator.handle(.recordingStarted)
        await h.coordinator.handle(.recordingFinished(path: path, duration: 1.5))

        #expect(h.coordinator.state.hasConfirmedSavedFile)
        let stored = try await h.recordings.loadRecordings()
        #expect(stored[0].outcome == .saved)
    }
}

@Suite("Orchestration: no timeline before capture is confirmed")
@MainActor
struct TimelineGatingTests {

    @Test("Markers are refused during the start-up window")
    func markersRefusedBeforeConfirmation() async throws {
        let h = Harness()
        await h.rollNow()

        // State is `.recording`, but nothing is on disk yet.
        #expect(h.coordinator.state.isCapturing)
        #expect(h.coordinator.canAddMarker == false,
                "A marker in the start-up window points at no file")
        #expect(h.coordinator.addMarker() == nil)

        await h.coordinator.handle(.recordingStarted)
        #expect(h.coordinator.canAddMarker)
        #expect(h.coordinator.addMarker() != nil)
    }

    @Test("A question change during start-up is reflected at offset zero, not mis-stamped")
    func questionChangeDuringStartup() async throws {
        let h = Harness(questions: ["First", "Second", "Third"])
        await h.rollNow()

        // The operator moves on before the first byte lands.
        h.clock.advance(by: 2)
        #expect(h.coordinator.goToNextQuestion())
        #expect(h.coordinator.engine.currentQuestion == "Second")
        #expect(h.coordinator.engine.questionChanges.isEmpty,
                "Nothing may be timestamped before there is a file")

        // Capture confirms; the question actually on screen is recorded at zero.
        h.clock.advance(by: 1)
        await h.coordinator.handle(.recordingStarted)

        #expect(h.coordinator.engine.questionChanges.map(\.offset) == [0])
        #expect(h.coordinator.engine.questionChanges.map(\.text) == ["Second"])
    }

    @Test("Offsets measure from the confirmed first byte, not the button press")
    func offsetsMeasureFromFirstByte() async throws {
        let h = Harness()
        await h.rollNow()

        // 4 seconds of camera start-up latency.
        h.clock.advance(by: 4)
        await h.coordinator.handle(.recordingStarted)

        h.clock.advance(by: 10)
        let marker = h.coordinator.addMarker(label: "ten seconds in")
        #expect(marker?.offset == 10, "Not 14 — the button press is not the start of the file")
    }

    @Test("The elapsed timer reports zero until capture is confirmed")
    func elapsedZeroUntilConfirmed() async throws {
        let h = Harness()
        await h.rollNow()

        h.clock.advance(by: 5)
        h.coordinator.refreshElapsed()
        #expect(h.coordinator.elapsed == 0,
                "A timer counting up while nothing is written tells the operator a lie")

        await h.coordinator.handle(.recordingStarted)
        h.clock.advance(by: 3)
        h.coordinator.refreshElapsed()
        #expect(h.coordinator.elapsed == 3)
    }
}

@Suite("Orchestration: the sweeper cannot break a recovery promise")
@MainActor
struct CleanupProtectionTests {

    @Test("A path an existing library row points at is never swept")
    func libraryReferencedPathIsProtected() async throws {
        let h = Harness()

        // A previous session left a recoverable file, recorded in the library.
        let orphan = try h.store.makeTemporaryPath()
        try h.store.writeFakeCapture(at: orphan)
        try h.store.backdate(path: orphan, by: 7200)
        try await h.recordings.save(
            InterviewRecordingModel(
                deckName: "Earlier interview",
                startedAt: Date(timeIntervalSince1970: 1),
                duration: 20,
                outcome: .interrupted,
                preservedFilePath: orphan
            )
        )

        // Starting a new session sweeps abandoned captures.
        await h.coordinator.begin(permissions: .bothAuthorized)

        #expect(FileManager.default.fileExists(atPath: orphan),
                "A recorded preservedFilePath is a promise the sweeper must not break")
    }

    @Test("A genuinely orphaned capture is still swept")
    func unreferencedOldCaptureIsSwept() async throws {
        let h = Harness()
        let abandoned = try h.store.makeTemporaryPath()
        try h.store.writeFakeCapture(at: abandoned)
        try h.store.backdate(path: abandoned, by: 7200)

        await h.coordinator.begin(permissions: .bothAuthorized)

        #expect(FileManager.default.fileExists(atPath: abandoned) == false)
    }
}

@Suite("Orchestration: permissions and the happy path")
@MainActor
struct CoordinatorHappyPathTests {

    @Test("Denied permission fails before any capture is attempted")
    func deniedPermissionBlocksCapture() async throws {
        let h = Harness()
        await h.coordinator.begin(
            permissions: PermissionSnapshot(camera: .denied, microphone: .authorized)
        )

        #expect(h.coordinator.state == .failed(.cameraPermissionDenied))
        #expect(h.coordinator.alert?.offersSettings == true)
        #expect(h.capture.calls.contains(where: {
            if case .prepare = $0 { return true } else { return false }
        }) == false, "The camera must not be configured when permission is denied")
    }

    @Test("A complete take records, saves, and files one library row")
    func completeTake() async throws {
        let h = Harness(questions: ["Q1", "Q2"])
        await h.rollNow()
        await h.coordinator.handle(.recordingStarted)
        try h.writeCaptureFile()
        let path = try #require(h.capturedPath)

        h.clock.advance(by: 15)
        _ = h.coordinator.addMarker(label: "good bit")
        _ = h.coordinator.goToNextQuestion()
        h.clock.advance(by: 25)

        await h.coordinator.tapStop()
        await h.coordinator.handle(.recordingFinished(path: path, duration: 40))

        #expect(h.coordinator.state.hasConfirmedSavedFile)
        let stored = try await h.recordings.loadRecordings()
        #expect(stored.count == 1)
        #expect(stored[0].outcome == .saved)
        #expect(stored[0].duration == 40)
        #expect(stored[0].markers.map(\.offset) == [15])
        #expect(stored[0].questionChanges.map(\.offset) == [0, 15])
        // The capture left the temporary directory.
        #expect(FileManager.default.fileExists(atPath: path) == false)
    }

    @Test("A store failure preserves the file and never claims a save")
    func storeFailurePreservesAndDoesNotClaimSave() async throws {
        let h = Harness()
        await h.rollNow()
        await h.coordinator.handle(.recordingStarted)
        try h.writeCaptureFile()
        let path = try #require(h.capturedPath)
        h.store.storeError = .moveFailed("disk full")

        await h.coordinator.tapStop()
        await h.coordinator.handle(.recordingFinished(path: path, duration: 30))

        #expect(h.coordinator.state.hasConfirmedSavedFile == false)
        let stored = try await h.recordings.loadRecordings()
        #expect(stored[0].outcome == .saveFailed)
        let preserved = try #require(stored[0].preservedFilePath)
        #expect(FileManager.default.fileExists(atPath: preserved))
    }

    @Test("Accessory loss during a take changes nothing about recording")
    func accessoryLossDoesNotAffectCapture() async throws {
        let h = Harness()
        await h.rollNow()
        await h.coordinator.handle(.recordingStarted)
        try h.writeCaptureFile()

        h.coordinator.updateSubjectAvailability(.unavailable)

        #expect(h.coordinator.state == .recording)
        #expect(h.coordinator.canAddMarker)
        h.clock.advance(by: 5)
        #expect(h.coordinator.addMarker() != nil)
    }
}
