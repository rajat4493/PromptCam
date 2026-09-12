import Testing
import Foundation
@testable import PromptCamCore

/// Regression tests for the recording-safety defects found in review of
/// commit f272a18. Each suite names the defect it locks down.
///
/// These are `STATICALLY_REVIEWED` like every other test here — no Swift
/// toolchain is reachable in the authoring environment. See
/// docs/VERIFICATION_LEDGER.md A3.

@Suite("Regression: a preserved recording survives the next session's cleanup")
struct PreservedFileSurvivesCleanupTests {

    @Test("Cleanup no longer deletes every capture in the temporary directory")
    func cleanupSkipsRecentFiles() throws {
        let store = TestRecordingStore()
        let recent = try store.makeTemporaryPath()
        try store.writeFakeCapture(at: recent)

        // The old behaviour deleted this unconditionally.
        try store.cleanUpAbandonedTemporaryFiles(excluding: [], olderThan: 3600)

        #expect(FileManager.default.fileExists(atPath: recent))
    }

    @Test("Cleanup skips a capture that is in flight, however old it looks")
    func cleanupSkipsActiveCapture() throws {
        let store = TestRecordingStore()
        let active = try store.makeTemporaryPath()
        try store.writeFakeCapture(at: active)
        try store.backdate(path: active, by: 7200)

        try store.cleanUpAbandonedTemporaryFiles(excluding: [active], olderThan: 3600)

        #expect(FileManager.default.fileExists(atPath: active))
    }

    @Test("Cleanup does remove a genuinely abandoned capture")
    func cleanupRemovesOldUnreferencedFile() throws {
        let store = TestRecordingStore()
        let abandoned = try store.makeTemporaryPath()
        try store.writeFakeCapture(at: abandoned)
        try store.backdate(path: abandoned, by: 7200)

        try store.cleanUpAbandonedTemporaryFiles(excluding: [], olderThan: 3600)

        #expect(FileManager.default.fileExists(atPath: abandoned) == false)
    }

    @Test("A preserved file moves out of the sweeper's reach entirely")
    func preservedFileLeavesTemporaryDirectory() throws {
        let store = TestRecordingStore()
        let temporary = try store.makeTemporaryPath()
        try store.writeFakeCapture(at: temporary)

        let preserved = try store.preserveForRecovery(temporaryPath: temporary)

        // It is no longer where it was, and it is no longer in Temp at all.
        #expect(FileManager.default.fileExists(atPath: temporary) == false)
        #expect(FileManager.default.fileExists(atPath: preserved))
        #expect(
            URL(fileURLWithPath: preserved).deletingLastPathComponent().standardizedFileURL
                != store.temporaryDirectory.standardizedFileURL
        )

        // The decisive assertion: even an aggressive sweep cannot touch it.
        try store.cleanUpAbandonedTemporaryFiles(excluding: [], olderThan: 0)
        #expect(FileManager.default.fileExists(atPath: preserved))
    }

    @Test("Preserving an already-preserved file is idempotent")
    func preserveIsIdempotent() throws {
        let store = TestRecordingStore()
        let temporary = try store.makeTemporaryPath()
        try store.writeFakeCapture(at: temporary)

        let once = try store.preserveForRecovery(temporaryPath: temporary)
        let twice = try store.preserveForRecovery(temporaryPath: once)

        // The path the library recorded must not change underneath it.
        #expect(once == twice)
        #expect(FileManager.default.fileExists(atPath: once))
    }

    @Test("A failed preserve leaves the file at its original path")
    func failedPreserveKeepsOriginal() throws {
        let store = TestRecordingStore()
        let temporary = try store.makeTemporaryPath()
        try store.writeFakeCapture(at: temporary)
        store.preserveError = .preserveFailed("simulated")

        #expect(throws: RecordingStoreError.self) {
            _ = try store.preserveForRecovery(temporaryPath: temporary)
        }
        // Worse place to be, but the interview still exists.
        #expect(FileManager.default.fileExists(atPath: temporary))
    }
}

@Suite("Regression: a late file never becomes a false save")
struct LateFileReconciliationTests {

    @Test("An interrupted session cannot be talked into claiming a save")
    func interruptedSessionRejectsSaveConfirmation() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            startedAt: clock.now,
            temporaryPath: "/tmp/partial.mov"
        )
        clock.advance(by: 20)
        try engine.interrupt(.audioSessionLost, at: clock.now)

        // This is what the old code attempted when the completion callback
        // arrived after the interruption.
        #expect(throws: InvalidTransition.self) {
            try engine.confirmSaved(fileName: "late.mov", duration: 20)
        }
        #expect(engine.state == .interrupted(reason: .audioSessionLost))
        #expect(engine.state.hasConfirmedSavedFile == false)
    }

    @Test("A late file is attached for recovery without changing the outcome")
    func attachRecoveredFileKeepsOutcome() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            startedAt: clock.now,
            temporaryPath: "/tmp/partial.mov"
        )
        clock.advance(by: 20)
        try engine.interrupt(.captureSessionInterrupted, at: clock.now)

        let attached = engine.attachRecoveredFile(path: "/recovery/Recovered-1.mov", duration: 20)

        #expect(attached)
        #expect(engine.state == .interrupted(reason: .captureSessionInterrupted))
        let result = engine.resultSnapshot()
        #expect(result?.outcome == .interrupted)
        #expect(result?.outcome.isPlayable == false)
        #expect(result?.fileName == nil)
        // The recovery path replaces the temporary one, which gets swept.
        #expect(result?.preservedFilePath == "/recovery/Recovered-1.mov")
    }

    @Test("A saved session refuses a recovered-file attachment")
    func savedSessionRejectsAttachment() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        clock.advance(by: 10)
        try engine.stop()
        try engine.confirmSaved(fileName: "good.mov", duration: 10)

        // Not a back door: a completed take must not acquire a "recovery" file.
        #expect(engine.attachRecoveredFile(path: "/recovery/x.mov", duration: 10) == false)
        #expect(engine.resultSnapshot()?.preservedFilePath == nil)
        #expect(engine.resultSnapshot()?.fileName == "good.mov")
    }

    @Test("An in-flight session refuses a recovered-file attachment")
    func inFlightSessionRejectsAttachment() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        #expect(engine.attachRecoveredFile(path: "/recovery/x.mov", duration: 5) == false)
    }

    @Test("Reconciliation updates the same library row rather than adding one")
    func reconciliationUpsertsOneRow() async throws {
        let repository = InMemoryRecordingRepository()
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            startedAt: clock.now,
            temporaryPath: "/tmp/partial.mov"
        )
        clock.advance(by: 20)
        try engine.interrupt(.backgrounded, at: clock.now)

        // First persist, as the session ends.
        let first = engine.resultSnapshot()!.makeRecordingModel()
        try await repository.save(first)

        // Then the late file arrives and the row is persisted again.
        engine.attachRecoveredFile(path: "/recovery/Recovered-1.mov", duration: 20)
        let second = engine.resultSnapshot()!.makeRecordingModel()
        try await repository.save(second)

        let stored = try await repository.loadRecordings()
        #expect(stored.count == 1, "A late reconciliation must not duplicate the interview")
        #expect(first.id == second.id)
        #expect(stored[0].preservedFilePath == "/recovery/Recovered-1.mov")
        #expect(stored[0].outcome == .interrupted)
    }

    @Test("The session's result identity is stable across repeated snapshots")
    func resultIdentityIsStable() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        clock.advance(by: 5)
        try engine.stop()
        try engine.confirmSaved(fileName: "a.mov", duration: 5)

        let a = engine.resultSnapshot()!.makeRecordingModel()
        let b = engine.resultSnapshot()!.makeRecordingModel()
        #expect(a.id == b.id)
        #expect(a.id == engine.resultIdentifier)
    }
}

@Suite("Regression: stop during capture start-up")
struct StopDuringStartupTests {

    @Test("Stop is legal before capture is confirmed, and reaches finishing")
    func stopBeforeCaptureConfirmed() throws {
        var engine = InterviewSessionEngine(deckName: "D", questions: ["Q"])
        try engine.prepare()
        try engine.markPrepared()
        try engine.beginRecording(at: Date(), temporaryPath: "/tmp/a.mov")

        // `.recordingStarted` has NOT arrived yet — this is the race window.
        #expect(engine.captureStartedAt != nil)
        #expect(engine.canApply(.stop))

        try engine.stop()
        #expect(engine.state == .finishing)
    }

    @Test("A capture confirmed after a stop request still finalises cleanly")
    func confirmationAfterStopRequest() throws {
        let clock = ManualSessionClock()
        var engine = InterviewSessionEngine(deckName: "D", questions: ["Q"])
        try engine.prepare()
        try engine.markPrepared()
        try engine.beginRecording(at: clock.now, temporaryPath: "/tmp/a.mov")
        try engine.stop()

        // The queued stop is honoured and the file completes.
        try engine.confirmSaved(fileName: "a.mov", duration: 0.5)

        #expect(engine.state.hasConfirmedSavedFile)
        #expect(engine.resultSnapshot()?.outcome == .saved)
    }

    @Test("noteCaptureStarted is ignored once the session has left recording")
    func noteCaptureStartedAfterStopIsIgnored() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        let original = engine.captureStartedAt
        try engine.stop()

        clock.advance(by: 60)
        engine.noteCaptureStarted(at: clock.now)

        // Rebasing after stop would corrupt every marker offset.
        #expect(engine.captureStartedAt == original)
    }

    @Test("A capture that never starts can still be failed, not left hanging")
    func captureThatNeverStartsCanFail() throws {
        var engine = InterviewSessionEngine(deckName: "D", questions: ["Q"])
        try engine.prepare()
        try engine.markPrepared()
        try engine.beginRecording(at: Date(), temporaryPath: "/tmp/a.mov")
        try engine.stop()

        // The watchdog's escape hatch: `.finishing` must accept a failure, or a
        // pipeline that never reports completion strands the session forever.
        #expect(engine.canApply(.fail(.captureFailed("did not start"))))
        try engine.fail(.captureFailed("did not start"))
        #expect(engine.state == .failed(.captureFailed("did not start")))
        #expect(engine.state.isTerminal)
    }
}

@Suite("Regression: a reset session is safe to reuse")
struct SessionReuseTests {

    @Test("Reset clears the recovered path so it cannot leak into the next take")
    func resetClearsRecoveredPath() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            startedAt: clock.now,
            temporaryPath: "/tmp/partial.mov"
        )
        clock.advance(by: 10)
        try engine.interrupt(.backgrounded, at: clock.now)
        engine.attachRecoveredFile(path: "/recovery/old.mov", duration: 10)

        try engine.reset()

        #expect(engine.recoveredFilePath == nil)
        #expect(engine.temporaryCapturePath == nil)
        #expect(engine.resultSnapshot() == nil)
    }

    @Test("A second take after a reset records its own outcome")
    func secondTakeAfterReset() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            startedAt: clock.now,
            temporaryPath: "/tmp/one.mov"
        )
        clock.advance(by: 10)
        try engine.interrupt(.audioSessionLost, at: clock.now)
        try engine.reset()

        try engine.prepare()
        try engine.markPrepared()
        try engine.beginRecording(at: clock.now, temporaryPath: "/tmp/two.mov")
        clock.advance(by: 15)
        engine.addMarker(label: "second take", at: clock.now)
        try engine.stop()
        try engine.confirmSaved(fileName: "two.mov", duration: 15)

        let result = engine.resultSnapshot()
        #expect(result?.outcome == .saved)
        #expect(result?.fileName == "two.mov")
        #expect(result?.markers.map(\.label) == ["second take"])
        #expect(result?.preservedFilePath == nil)
    }
}
