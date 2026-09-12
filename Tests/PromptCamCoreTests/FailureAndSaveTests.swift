import Testing
import Foundation
@testable import PromptCamCore

@Suite("Save integrity: no false success")
struct SaveIntegrityTests {

    @Test("A failed save is never reported as saved")
    func failedSaveIsNeverSaved() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            startedAt: clock.now,
            temporaryPath: "/tmp/keep-me.mov"
        )
        clock.advance(by: 30)
        try engine.stop()

        try engine.failSave(reason: "disk full", preservedPath: "/tmp/keep-me.mov", duration: 30)

        #expect(engine.state.hasConfirmedSavedFile == false)
        #expect(engine.state.savedFileName == nil)

        let result = engine.resultSnapshot()
        #expect(result?.outcome == .saveFailed)
        #expect(result?.outcome.isPlayable == false)
        #expect(result?.fileName == nil)
        // The captured file is kept so the interview is not lost.
        #expect(result?.preservedFilePath == "/tmp/keep-me.mov")
    }

    @Test("Only an OS-confirmed save produces a playable recording")
    func onlyConfirmedSaveIsPlayable() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        clock.advance(by: 10)
        try engine.stop()
        try engine.confirmSaved(fileName: "good.mov", duration: 10)

        let result = engine.resultSnapshot()
        #expect(result?.outcome == .saved)
        #expect(result?.outcome.isPlayable == true)
        #expect(result?.fileName == "good.mov")
    }

    @Test("A result cannot be persisted while the session is still in flight")
    func noResultWhileInFlight() throws {
        var engine = InterviewSessionEngine(deckName: "D", questions: ["Q"])
        #expect(engine.resultSnapshot() == nil)

        try engine.prepare()
        #expect(engine.resultSnapshot() == nil)

        try engine.markPrepared()
        try engine.beginRecording(at: Date())
        #expect(engine.resultSnapshot() == nil)

        try engine.stop()
        // Still finishing: the OS has not confirmed anything yet.
        #expect(engine.resultSnapshot() == nil)

        try engine.confirmSaved(fileName: "a.mov", duration: 5)
        #expect(engine.resultSnapshot() != nil)
    }

    @Test("Outcome playability is the single gate for offering playback")
    func playabilityGate() {
        #expect(RecordingOutcome.saved.isPlayable)
        #expect(RecordingOutcome.saveFailed.isPlayable == false)
        #expect(RecordingOutcome.interrupted.isPlayable == false)
        #expect(RecordingOutcome.failed.isPlayable == false)
    }

    @Test("A store failure leaves the captured file on disk")
    func storeFailurePreservesFileOnDisk() throws {
        let store = TestRecordingStore()
        let temporaryPath = try store.makeTemporaryPath()
        try store.writeFakeCapture(at: temporaryPath)
        store.storeError = .moveFailed("simulated")

        #expect(throws: RecordingStoreError.self) {
            _ = try store.store(temporaryPath: temporaryPath, startedAt: Date())
        }

        // The rule that matters: the operator's footage is still there.
        #expect(FileManager.default.fileExists(atPath: temporaryPath))
    }

    @Test("A successful store moves the file into the recordings directory")
    func successfulStoreMovesFile() throws {
        let store = TestRecordingStore()
        let temporaryPath = try store.makeTemporaryPath()
        try store.writeFakeCapture(at: temporaryPath)

        let stored = try store.store(temporaryPath: temporaryPath, startedAt: Date())

        #expect(FileManager.default.fileExists(atPath: stored.path))
        #expect(FileManager.default.fileExists(atPath: temporaryPath) == false)
        #expect(stored.path.hasSuffix(stored.fileName))
    }

    @Test("Storing a missing capture fails loudly instead of inventing a recording")
    func missingCaptureFails() {
        let store = TestRecordingStore()
        #expect(throws: RecordingStoreError.temporaryFileMissing) {
            _ = try store.store(temporaryPath: "/tmp/does-not-exist-\(UUID()).mov", startedAt: Date())
        }
    }

    @Test("Temporary cleanup removes abandoned captures but never stored recordings")
    func cleanupSpareStoredRecordings() throws {
        let store = TestRecordingStore()

        let abandoned = try store.makeTemporaryPath()
        try store.writeFakeCapture(at: abandoned)
        // Only files old enough to be genuinely abandoned are swept.
        try store.backdate(path: abandoned, by: 7200)

        let keeper = try store.makeTemporaryPath()
        try store.writeFakeCapture(at: keeper)
        let stored = try store.store(temporaryPath: keeper, startedAt: Date())

        try store.cleanUpAbandonedTemporaryFiles(excluding: [], olderThan: 3600)

        #expect(FileManager.default.fileExists(atPath: abandoned) == false)
        #expect(FileManager.default.fileExists(atPath: stored.path))
    }
}

@Suite("Capture failures")
struct CaptureFailureTests {

    @Test("Camera initialisation failure ends the session as failed, not saved")
    func cameraInitialisationFailure() throws {
        var engine = InterviewSessionEngine(deckName: "D", questions: ["Q"])
        try engine.prepare()

        try engine.fail(.cameraUnavailable("no device found"))

        #expect(engine.state == .failed(.cameraUnavailable("no device found")))
        #expect(engine.state.hasConfirmedSavedFile == false)
        // Nothing was ever captured, so there is no result to file.
        #expect(engine.resultSnapshot() == nil)
    }

    @Test("Microphone initialisation failure is reported distinctly from the camera")
    func microphoneInitialisationFailure() throws {
        var engine = InterviewSessionEngine(deckName: "D", questions: ["Q"])
        try engine.prepare()

        try engine.fail(.microphoneUnavailable("in use by another app"))

        #expect(engine.state == .failed(.microphoneUnavailable("in use by another app")))
        if case .failed(let failure) = engine.state {
            #expect(failure.operatorMessage.contains("microphone"))
        } else {
            Issue.record("Expected a failed state")
        }
    }

    @Test("A mid-recording capture failure keeps what is known about the take")
    func midRecordingFailure() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            startedAt: clock.now,
            temporaryPath: "/tmp/partial.mov"
        )
        clock.advance(by: 42)
        engine.addMarker(label: "before the failure", at: clock.now)

        try engine.fail(.captureFailed("pipeline error"), duration: 42)

        let result = engine.resultSnapshot()
        #expect(result?.outcome == .failed)
        #expect(result?.duration == 42)
        #expect(result?.markers.count == 1)
        #expect(result?.outcome.isPlayable == false)
    }

    @Test("Every failure has operator-facing copy")
    func failureMessagesExist() {
        let failures: [RecordingFailure] = [
            .cameraUnavailable("x"),
            .microphoneUnavailable("x"),
            .cameraPermissionDenied,
            .microphonePermissionDenied,
            .captureFailed("x"),
            .saveFailed(reason: "x", preservedPath: nil),
            .saveFailed(reason: "x", preservedPath: "/tmp/y.mov"),
            .insufficientStorage
        ]
        for failure in failures {
            #expect(failure.operatorMessage.isEmpty == false)
        }
    }

    @Test("A save failure that kept the file says so in the copy")
    func preservedFileMentionedInCopy() {
        let kept = RecordingFailure.saveFailed(reason: "disk full.", preservedPath: "/tmp/a.mov")
        let lost = RecordingFailure.saveFailed(reason: "disk full.", preservedPath: nil)

        #expect(kept.operatorMessage.contains("kept"))
        #expect(lost.operatorMessage.contains("kept") == false)
    }
}

@Suite("Interruption and backgrounding")
struct InterruptionTests {

    @Test("An interrupted recording is flagged, and its partial file is preserved")
    func interruptionPreservesPartialFile() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            startedAt: clock.now,
            temporaryPath: "/tmp/partial.mov"
        )
        clock.advance(by: 18)

        try engine.interrupt(.audioSessionLost, at: clock.now)

        #expect(engine.state == .interrupted(reason: .audioSessionLost))
        let result = engine.resultSnapshot()
        #expect(result?.outcome == .interrupted)
        #expect(result?.outcome.isPlayable == false)
        #expect(result?.duration == 18)
        // Never silently deleted.
        #expect(result?.preservedFilePath == "/tmp/partial.mov")
    }

    @Test("Backgrounding during recording is an interruption, not a save")
    func backgroundingDuringRecording() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        clock.advance(by: 7.5)

        try engine.interrupt(.backgrounded, at: clock.now)

        #expect(engine.state.hasConfirmedSavedFile == false)
        #expect(engine.resultSnapshot()?.outcome == .interrupted)
        #expect(engine.resultSnapshot()?.duration == 7.5)
    }

    @Test("The duration freezes at the moment of interruption")
    func durationFreezesOnInterruption() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        clock.advance(by: 12)
        try engine.interrupt(.captureSessionInterrupted, at: clock.now)

        // Time keeps passing; the recorded duration must not.
        clock.advance(by: 600)
        #expect(engine.duration(now: clock.now) == 12)
    }

    @Test("Markers taken before an interruption are retained")
    func markersRetainedThroughInterruption() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        clock.advance(by: 5)
        engine.addMarker(label: "A", at: clock.now)
        clock.advance(by: 5)
        engine.addMarker(label: "B", at: clock.now)

        try engine.interrupt(.audioSessionLost, at: clock.now)

        #expect(engine.resultSnapshot()?.markers.map(\.label) == ["A", "B"])
        #expect(engine.resultSnapshot()?.markers.map(\.offset) == [5, 10])
    }

    @Test("Every interruption reason has operator-facing copy")
    func interruptionMessagesExist() {
        for reason in [
            InterruptionReason.audioSessionLost,
            .captureSessionInterrupted,
            .backgrounded,
            .resourcePressure
        ] {
            #expect(reason.operatorMessage.isEmpty == false)
        }
    }

    @Test("Resetting after an interruption clears the session for a new take")
    func resetAfterInterruption() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        clock.advance(by: 5)
        engine.addMarker(at: clock.now)
        try engine.interrupt(.backgrounded, at: clock.now)

        try engine.reset()

        #expect(engine.state == .idle)
        #expect(engine.markers.isEmpty)
        #expect(engine.questionChanges.isEmpty)
        #expect(engine.currentQuestionIndex == 0)
        #expect(engine.duration(now: clock.now) == 0)
        #expect(engine.resultSnapshot() == nil)
    }
}

@Suite("Duration reporting")
struct DurationTests {

    @Test("Duration grows while recording")
    func durationGrowsWhileRecording() throws {
        let clock = ManualSessionClock()
        let engine = try InterviewSessionEngine.recording(startedAt: clock.now)

        clock.advance(by: 5)
        #expect(engine.duration(now: clock.now) == 5)
        clock.advance(by: 10)
        #expect(engine.duration(now: clock.now) == 15)
    }

    @Test("Duration is zero before capture begins")
    func durationZeroBeforeCapture() throws {
        var engine = InterviewSessionEngine(deckName: "D", questions: ["Q"])
        try engine.prepare()
        try engine.markPrepared()
        try engine.startCountdown(seconds: 3)

        #expect(engine.duration(now: Date()) == 0)
    }

    @Test("Duration stays zero during the capture start-up window")
    func durationZeroUntilConfirmed() throws {
        let clock = ManualSessionClock()
        let engine = try InterviewSessionEngine.recordingPendingConfirmation(startedAt: clock.now)

        clock.advance(by: 6)
        // The state is `.recording`, but nothing is being written, so a timer
        // counting up would be telling the operator a comfortable lie.
        #expect(engine.duration(now: clock.now) == 0)
    }

    @Test("Duration freezes at the confirmed value after saving")
    func durationFreezesAfterSave() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        clock.advance(by: 20)
        try engine.stop()
        try engine.confirmSaved(fileName: "a.mov", duration: 20.25)

        clock.advance(by: 500)
        #expect(engine.duration(now: clock.now) == 20.25)
    }
}
