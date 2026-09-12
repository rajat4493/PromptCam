import Testing
import Foundation
@testable import PromptCamCore

@Suite("Session engine: markers and timestamp accuracy")
struct MarkerTests {

    @Test("A marker records the exact offset from the start of capture")
    func markerOffsetIsExact() throws {
        let clock = ManualSessionClock()
        let start = clock.now
        var engine = try InterviewSessionEngine.recording(startedAt: start)

        clock.advance(by: 12.5)
        let marker = engine.addMarker(at: clock.now)

        #expect(marker != nil)
        #expect(marker?.offset == 12.5)
    }

    @Test("Several markers keep their individual offsets")
    func multipleMarkerOffsets() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)

        for seconds in [3.0, 7.25, 30.0, 61.5] {
            clock.set(to: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
            engine.addMarker(at: clock.now)
        }

        #expect(engine.markers.map(\.offset) == [3.0, 7.25, 30.0, 61.5])
    }

    @Test("Markers are auto-numbered when no label is given")
    func markerDefaultLabels() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)

        clock.advance(by: 1)
        engine.addMarker(at: clock.now)
        clock.advance(by: 1)
        engine.addMarker(at: clock.now)
        clock.advance(by: 1)
        engine.addMarker(label: "Great quote", at: clock.now)

        #expect(engine.markers.map(\.label) == ["Marker 1", "Marker 2", "Great quote"])
    }

    @Test("A whitespace-only label falls back to the auto number")
    func whitespaceLabelFallsBack() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        clock.advance(by: 1)

        let marker = engine.addMarker(label: "   \n ", at: clock.now)
        #expect(marker?.label == "Marker 1")
    }

    @Test("A marker is refused when not recording, rather than stored at zero")
    func markerRefusedWhenNotRecording() throws {
        var engine = InterviewSessionEngine(deckName: "D", questions: ["Q1"])

        #expect(engine.addMarker(at: Date()) == nil)

        try engine.prepare()
        #expect(engine.addMarker(at: Date()) == nil)

        try engine.markPrepared()
        try engine.startCountdown(seconds: 3)
        #expect(engine.addMarker(at: Date()) == nil)

        #expect(engine.markers.isEmpty)
    }

    @Test("A marker is refused after the take has stopped")
    func markerRefusedAfterStop() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        clock.advance(by: 5)
        try engine.stop()

        #expect(engine.addMarker(at: clock.now) == nil)
        #expect(engine.markers.isEmpty)
    }

    @Test("Capture-start confirmation rebases marker offsets to the real first byte")
    func rebaseOnConfirmedStart() throws {
        let clock = ManualSessionClock()
        let buttonPress = clock.now
        var engine = try InterviewSessionEngine.recordingPendingConfirmation(startedAt: buttonPress)

        // The pipeline took 400 ms to actually start writing.
        clock.advance(by: 0.4)
        engine.noteCaptureStarted(at: clock.now)

        clock.advance(by: 10)
        let marker = engine.addMarker(at: clock.now)

        // 10 s from the first byte, not 10.4 s from the button press.
        #expect(marker?.offset == 10.0)
    }

    @Test("No marker may be taken during the capture start-up window")
    func markerRefusedBeforeConfirmation() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recordingPendingConfirmation(startedAt: clock.now)

        // The state is `.recording`, but nothing has been written yet, so an
        // offset would point at no file — and would be invalidated by the
        // rebase that confirmation performs.
        #expect(engine.state.isCapturing)
        #expect(engine.isCaptureConfirmed == false)
        #expect(engine.canAddMarker == false)

        clock.advance(by: 2)
        #expect(engine.addMarker(at: clock.now) == nil)
        #expect(engine.markers.isEmpty)

        engine.noteCaptureStarted(at: clock.now)
        #expect(engine.canAddMarker)
        #expect(engine.addMarker(at: clock.now) != nil)
    }

    @Test("Confirmation records the question actually on screen at offset zero")
    func confirmationRecordsOpeningQuestion() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recordingPendingConfirmation(
            questions: ["First", "Second", "Third"],
            startedAt: clock.now
        )
        #expect(engine.questionChanges.isEmpty)

        // The operator moves on during start-up.
        clock.advance(by: 2)
        #expect(engine.goToNextQuestion(at: clock.now))
        #expect(engine.questionChanges.isEmpty, "Nothing is timestamped before there is a file")

        clock.advance(by: 1)
        engine.noteCaptureStarted(at: clock.now)

        #expect(engine.questionChanges.map(\.offset) == [0])
        #expect(engine.questionChanges.map(\.text) == ["Second"])
    }

    @Test("A confirmation arriving after a stop is ignored")
    func confirmationAfterStopIgnored() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        let original = engine.captureStartedAt
        clock.advance(by: 10)
        try engine.stop()

        clock.advance(by: 30)
        engine.noteCaptureStarted(at: clock.now)

        // Rebasing now would corrupt every offset already measured.
        #expect(engine.captureStartedAt == original)
    }
}

@Suite("Session engine: question navigation")
struct QuestionNavigationTests {

    @Test("Question changes during recording are timestamped")
    func questionChangesTimestamped() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            questions: ["Q1", "Q2", "Q3"],
            startedAt: clock.now
        )

        clock.advance(by: 20)
        #expect(engine.goToNextQuestion(at: clock.now))
        clock.advance(by: 35)
        #expect(engine.goToNextQuestion(at: clock.now))

        // Offset 0 is the question that was on screen when capture began.
        #expect(engine.questionChanges.map(\.offset) == [0, 20, 55])
        #expect(engine.questionChanges.map(\.index) == [0, 1, 2])
        #expect(engine.questionChanges.map(\.text) == ["Q1", "Q2", "Q3"])
    }

    @Test("Navigation past the ends is refused and changes nothing")
    func navigationBounds() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            questions: ["Only one"],
            startedAt: clock.now
        )

        #expect(engine.goToNextQuestion(at: clock.now) == false)
        #expect(engine.goToPreviousQuestion(at: clock.now) == false)
        #expect(engine.currentQuestionIndex == 0)
        #expect(engine.questionChanges.count == 1)  // just the offset-0 entry
    }

    @Test("Re-selecting the current question is not recorded as a change")
    func sameQuestionIsNoOp() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        clock.advance(by: 5)

        #expect(engine.goToQuestion(0, at: clock.now) == false)
        #expect(engine.questionChanges.count == 1)
        #expect(engine.questionRevision == 0)
    }

    @Test("Going backwards is allowed and recorded")
    func backwardsNavigation() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)

        clock.advance(by: 10)
        engine.goToNextQuestion(at: clock.now)
        clock.advance(by: 10)
        #expect(engine.goToPreviousQuestion(at: clock.now))

        #expect(engine.currentQuestionIndex == 0)
        #expect(engine.questionChanges.map(\.index) == [0, 1, 0])
    }

    @Test("Navigating before recording moves the cursor but records nothing")
    func navigationBeforeRecording() throws {
        var engine = InterviewSessionEngine(deckName: "D", questions: ["Q1", "Q2"])
        try engine.prepare()

        #expect(engine.goToNextQuestion(at: Date()))
        #expect(engine.currentQuestionIndex == 1)
        #expect(engine.questionChanges.isEmpty)
    }

    @Test("Question revision increases on each real change, for the subject cue")
    func revisionCounter() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(startedAt: clock.now)
        #expect(engine.questionRevision == 0)

        engine.goToNextQuestion(at: clock.now)
        #expect(engine.questionRevision == 1)
        engine.goToNextQuestion(at: clock.now)
        #expect(engine.questionRevision == 2)
        engine.goToNextQuestion(at: clock.now)   // refused, out of range
        #expect(engine.questionRevision == 2)
    }
}

@Suite("Session engine: subject surface synchronisation and privacy")
struct SubjectSurfaceTests {

    @Test("The subject snapshot always matches the engine's current question")
    func snapshotTracksQuestion() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            questions: ["First question", "Second question", "Third question"],
            capabilities: .fullyCapable,
            startedAt: clock.now
        )

        #expect(engine.subjectSnapshot().questionText == "First question")
        #expect(engine.subjectSnapshot().questionNumber == 1)
        #expect(engine.subjectSnapshot().questionCount == 3)

        engine.goToNextQuestion(at: clock.now)

        #expect(engine.subjectSnapshot().questionText == "Second question")
        #expect(engine.subjectSnapshot().questionNumber == 2)
    }

    @Test("The subject snapshot reflects countdown and recording state")
    func snapshotTracksState() throws {
        var engine = InterviewSessionEngine(
            deckName: "D",
            questions: ["Q1"],
            capabilities: .fullyCapable
        )
        try engine.prepare()
        try engine.markPrepared()

        try engine.startCountdown(seconds: 3)
        #expect(engine.subjectSnapshot().countdownRemaining == 3)
        #expect(engine.subjectSnapshot().isRecording == false)

        try engine.tickCountdown()
        #expect(engine.subjectSnapshot().countdownRemaining == 2)

        try engine.tickCountdown()
        try engine.tickCountdown()
        try engine.beginRecording(at: Date())

        #expect(engine.subjectSnapshot().countdownRemaining == nil)
        #expect(engine.subjectSnapshot().isRecording)
    }

    @Test("The subject snapshot cannot carry the next question or the deck")
    func snapshotHasNoDirectorInformation() throws {
        let clock = ManualSessionClock()
        let engine = try InterviewSessionEngine.recording(
            questions: ["Current", "UPCOMING SECRET", "Also upcoming"],
            capabilities: .fullyCapable,
            startedAt: clock.now
        )

        let snapshot = engine.subjectSnapshot()

        // The director can see what is next; the subject snapshot cannot carry it.
        #expect(engine.nextQuestion == "UPCOMING SECRET")
        #expect(snapshot.questionText == "Current")

        // Everything the snapshot exposes, enumerated — there is nowhere for
        // an upcoming question or a deck name to hide.
        let exposedText = [
            snapshot.questionText ?? "",
            snapshot.questionNumber.map(String.init) ?? "",
            String(snapshot.questionCount),
            snapshot.countdownRemaining.map(String.init) ?? ""
        ].joined(separator: " ")

        #expect(exposedText.contains("UPCOMING SECRET") == false)
        #expect(exposedText.contains("Test deck") == false)
    }

    @Test("Disabling question display blanks it on the subject surface only")
    func questionDisplayCanBeDisabled() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            questions: ["Q1"],
            capabilities: .fullyCapable,
            startedAt: clock.now
        )

        engine.updateDisplayOptions(SubjectDisplayOptions(showsQuestion: false))

        #expect(engine.subjectSnapshot().questionText == nil)
        // The director still has it.
        #expect(engine.currentQuestion == "Q1")
    }

    @Test("A snapshot with nothing to show reports that, so no empty screen appears")
    func emptySnapshotDetected() throws {
        var engine = InterviewSessionEngine(
            deckName: "D",
            questions: [],
            capabilities: .fullyCapable
        )
        engine.updateDisplayOptions(
            SubjectDisplayOptions(
                showsQuestion: true, showsCountdown: true, showsRecordingStatus: true
            )
        )
        #expect(engine.subjectSnapshot().hasPresentableContent == false)

        var recording = try InterviewSessionEngine.recording(
            questions: ["Real question"],
            capabilities: .fullyCapable,
            startedAt: Date()
        )
        #expect(recording.subjectSnapshot().hasPresentableContent)
        recording.updateDisplayOptions(
            SubjectDisplayOptions(
                showsQuestion: false, showsCountdown: false, showsRecordingStatus: false
            )
        )
        #expect(recording.subjectSnapshot().hasPresentableContent == false)
    }

    @Test("Live preview stays off unless the feature flag verifies it")
    func livePreviewGated() {
        let requested = SubjectDisplayOptions(showsLivePreview: true)

        // Default flags: unverified, so the option is stripped.
        let defaultEngine = InterviewSessionEngine(
            deckName: "D", questions: ["Q"],
            capabilities: .fullyCapable,
            flags: .default,
            displayOptions: requested
        )
        #expect(defaultEngine.displayOptions.showsLivePreview == false)
        #expect(defaultEngine.subjectSnapshot().options.showsLivePreview == false)

        // Only an explicitly verified configuration lets it through.
        let verifiedEngine = InterviewSessionEngine(
            deckName: "D", questions: ["Q"],
            capabilities: .fullyCapable,
            flags: .livePreviewEnabledForTesting,
            displayOptions: requested
        )
        #expect(verifiedEngine.displayOptions.showsLivePreview)
    }

    @Test("The UI cannot re-enable live preview behind the flag's back")
    func livePreviewCannotBeReEnabled() {
        var engine = InterviewSessionEngine(
            deckName: "D", questions: ["Q"],
            capabilities: .fullyCapable,
            flags: .default
        )
        engine.updateDisplayOptions(SubjectDisplayOptions(showsLivePreview: true))
        #expect(engine.displayOptions.showsLivePreview == false)
    }
}

@Suite("Session engine: accessory availability")
struct AccessoryAvailabilityTests {

    @Test("An accessory becoming available shows the subject controls")
    func accessoryBecomesAvailable() {
        var engine = InterviewSessionEngine(
            deckName: "D", questions: ["Q"],
            capabilities: .fullyCapable
        )
        #expect(engine.subjectAvailability == .unavailable)
        #expect(engine.showsSubjectDisplayControls == false)

        engine.updateSubjectAvailability(.availableNotEnabled)
        #expect(engine.showsSubjectDisplayControls)

        engine.updateSubjectAvailability(.presented)
        #expect(engine.subjectAvailability.isPresented)
    }

    @Test("An accessory disappearing mid-recording does NOT end the take")
    func accessoryDisappearsWhileRecording() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            capabilities: .fullyCapable,
            startedAt: clock.now
        )
        engine.updateSubjectAvailability(.presented)
        #expect(engine.state == .recording)

        clock.advance(by: 30)
        engine.updateSubjectAvailability(.unavailable)

        // Losing the subject screen is not a reason to lose the interview.
        #expect(engine.state == .recording)
        #expect(engine.showsSubjectDisplayControls == false)

        // And the take still finishes normally.
        clock.advance(by: 10)
        try engine.stop()
        try engine.confirmSaved(fileName: "a.mov", duration: 40)
        #expect(engine.state.hasConfirmedSavedFile)
    }

    @Test("Markers and question changes continue after the accessory is lost")
    func timelineSurvivesAccessoryLoss() throws {
        let clock = ManualSessionClock()
        var engine = try InterviewSessionEngine.recording(
            capabilities: .fullyCapable,
            startedAt: clock.now
        )
        engine.updateSubjectAvailability(.presented)

        clock.advance(by: 10)
        engine.updateSubjectAvailability(.unavailable)

        clock.advance(by: 5)
        #expect(engine.addMarker(at: clock.now)?.offset == 15)
        #expect(engine.goToNextQuestion(at: clock.now))
        #expect(engine.questionChanges.last?.offset == 15)
    }

    @Test("An accessory can reappear during the same take")
    func accessoryReappears() throws {
        var engine = try InterviewSessionEngine.recording(
            capabilities: .fullyCapable,
            startedAt: Date()
        )
        engine.updateSubjectAvailability(.presented)
        engine.updateSubjectAvailability(.unavailable)
        engine.updateSubjectAvailability(.presented)

        #expect(engine.subjectAvailability == .presented)
        #expect(engine.state == .recording)
    }
}

@Suite("Session engine: ordinary iPhone fallback")
struct FallbackTests {

    @Test("A device with no accessory support reports unsupported, not merely unavailable")
    func unsupportedDevice() {
        let engine = InterviewSessionEngine(
            deckName: "D", questions: ["Q"],
            capabilities: .ordinaryPhone
        )
        #expect(engine.subjectAvailability == .unsupported)
        // Duo-only controls are hidden entirely rather than shown disabled.
        #expect(engine.showsSubjectDisplayControls == false)
    }

    @Test("A spurious availability callback cannot light up controls on an ordinary phone")
    func spuriousAvailabilityIgnored() {
        var engine = InterviewSessionEngine(
            deckName: "D", questions: ["Q"],
            capabilities: .ordinaryPhone
        )

        engine.updateSubjectAvailability(.presented)

        #expect(engine.subjectAvailability == .unsupported)
        #expect(engine.showsSubjectDisplayControls == false)
    }

    @Test("A full interview records end to end on an ordinary phone")
    func fullInterviewOnOrdinaryPhone() throws {
        let clock = ManualSessionClock()
        var engine = InterviewSessionEngine(
            deckName: "Street interviews",
            questions: ["Q1", "Q2"],
            capabilities: .ordinaryPhone
        )

        try engine.prepare()
        try engine.markPrepared()
        try engine.beginRecording(at: clock.now, temporaryPath: "/tmp/t.mov")

        clock.advance(by: 15)
        engine.addMarker(label: "Good bit", at: clock.now)
        engine.goToNextQuestion(at: clock.now)

        clock.advance(by: 25)
        try engine.stop()
        try engine.confirmSaved(fileName: "interview.mov", duration: 40)

        let result = engine.resultSnapshot()
        #expect(result?.outcome == .saved)
        #expect(result?.fileName == "interview.mov")
        #expect(result?.duration == 40)
        #expect(result?.markers.count == 1)
        #expect(result?.questionChanges.count == 2)
    }
}
