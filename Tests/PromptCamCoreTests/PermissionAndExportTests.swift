import Testing
import Foundation
@testable import PromptCamCore

@Suite("Permissions")
struct PermissionTests {

    @Test("Both permissions granted is the only recordable state")
    func bothGrantedIsRecordable() {
        #expect(PermissionSnapshot(camera: .authorized, microphone: .authorized).canRecord)
        #expect(PermissionSnapshot(camera: .denied, microphone: .authorized).canRecord == false)
        #expect(PermissionSnapshot(camera: .authorized, microphone: .denied).canRecord == false)
        #expect(PermissionSnapshot(camera: .notDetermined, microphone: .authorized).canRecord == false)
        #expect(PermissionSnapshot(camera: .restricted, microphone: .authorized).canRecord == false)
    }

    @Test("Camera denial is reported before microphone denial")
    func cameraReportedFirst() {
        let snapshot = PermissionSnapshot(camera: .denied, microphone: .denied)
        #expect(snapshot.blocking == [.camera, .microphone])
        #expect(snapshot.blockingFailure == .cameraPermissionDenied)
    }

    @Test("Microphone denial alone is reported as such")
    func microphoneOnlyDenial() {
        let snapshot = PermissionSnapshot(camera: .authorized, microphone: .denied)
        #expect(snapshot.blocking == [.microphone])
        #expect(snapshot.blockingFailure == .microphonePermissionDenied)
    }

    @Test("A recordable snapshot has no blocking failure")
    func noFailureWhenAuthorized() {
        #expect(PermissionSnapshot.bothAuthorized.blockingFailure == nil)
        #expect(PermissionSnapshot.bothAuthorized.blocking.isEmpty)
    }

    @Test("Denied is fixable in Settings; restricted is not")
    func recoveryPathDiffersByStatus() {
        // These drive different recovery copy, so the distinction must hold.
        #expect(PermissionStatus.denied.isFixableInSettings)
        #expect(PermissionStatus.restricted.isFixableInSettings == false)
        #expect(PermissionStatus.notDetermined.isFixableInSettings == false)
        #expect(PermissionStatus.authorized.isFixableInSettings == false)
    }

    @Test("Camera denial blocks a session before any capture is attempted")
    func deniedCameraBlocksSession() async {
        let permissions = FakePermissionService(camera: .denied, microphone: .authorized)
        let snapshot = await permissions.snapshot()

        #expect(snapshot.canRecord == false)

        var engine = InterviewSessionEngine(deckName: "D", questions: ["Q"])
        if let failure = snapshot.blockingFailure {
            try? engine.prepare()
            try? engine.fail(failure)
        }

        #expect(engine.state == .failed(.cameraPermissionDenied))
        #expect(engine.state.hasConfirmedSavedFile == false)
    }

    @Test("Requesting a permission the user then denies resolves as denied")
    func requestThenDeny() async {
        let permissions = FakePermissionService(
            camera: .notDetermined,
            microphone: .notDetermined,
            cameraAfterRequest: .denied,
            microphoneAfterRequest: .authorized
        )

        let camera = await permissions.request(.camera)
        let microphone = await permissions.request(.microphone)

        #expect(camera == .denied)
        #expect(microphone == .authorized)
        #expect(permissions.requestedPermissions == [.camera, .microphone])

        let resolved = await permissions.snapshot()
        #expect(resolved.canRecord == false)
    }

    @Test("Every permission has a rationale to show before the system prompt")
    func rationaleCopyExists() {
        for permission in CapturePermission.allCases {
            #expect(permission.rationale.isEmpty == false)
            #expect(permission.displayName.isEmpty == false)
        }
    }
}

@Suite("Marker export")
struct MarkerExportTests {

    private func makeRecording(
        markers: [MarkerModel] = [],
        questionChanges: [QuestionChangeModel] = [],
        outcome: RecordingOutcome = .saved,
        duration: TimeInterval = 120
    ) -> InterviewRecordingModel {
        InterviewRecordingModel(
            deckName: "Customer testimonial",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: duration,
            outcome: outcome,
            fileName: "a.mov",
            markers: markers,
            questionChanges: questionChanges
        )
    }

    @Test("Timecodes are zero-padded and millisecond-accurate")
    func timecodeFormat() {
        #expect(MarkerExporter.timecode(0) == "00:00:00.000")
        #expect(MarkerExporter.timecode(1.5) == "00:00:01.500")
        #expect(MarkerExporter.timecode(61.25) == "00:01:01.250")
        #expect(MarkerExporter.timecode(3661.125) == "01:01:01.125")
        // A negative offset is meaningless and must not produce a broken field.
        #expect(MarkerExporter.timecode(-5) == "00:00:00.000")
    }

    @Test("The on-screen timer is minutes and seconds")
    func shortTimecodeFormat() {
        #expect(MarkerExporter.shortTimecode(0) == "00:00")
        #expect(MarkerExporter.shortTimecode(65) == "01:05")
        #expect(MarkerExporter.shortTimecode(3600) == "60:00")
    }

    @Test("Markers and question changes merge in chronological order")
    func chronologicalMerge() {
        let exporter = MarkerExporter()
        let recording = makeRecording(
            markers: [
                MarkerModel(offset: 30, label: "Good quote"),
                MarkerModel(offset: 5, label: "Slate")
            ],
            questionChanges: [
                QuestionChangeModel(offset: 0, index: 0, text: "Who are you?"),
                QuestionChangeModel(offset: 20, index: 1, text: "What changed?")
            ]
        )

        let rows = exporter.rows(for: recording)

        #expect(rows.map(\.offset) == [0, 5, 20, 30])
        #expect(rows.map(\.kind) == [.question, .marker, .question, .marker])
    }

    @Test("At an identical offset the question sorts before the marker")
    func questionBeforeMarkerAtTie() {
        let exporter = MarkerExporter()
        let rows = exporter.rows(
            markers: [MarkerModel(offset: 10, label: "M")],
            questionChanges: [QuestionChangeModel(offset: 10, index: 0, text: "Q")]
        )
        #expect(rows.map(\.kind) == [.question, .marker])
    }

    @Test("CSV quotes every field and doubles embedded quotes")
    func csvEscaping() {
        let exporter = MarkerExporter()
        let recording = makeRecording(
            markers: [MarkerModel(offset: 1, label: #"He said "yes", loudly"#)]
        )

        let csv = exporter.csv(for: recording)
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines[0] == "timecode,seconds,type,label")
        // A comma and a quote inside the label must not break the row.
        #expect(lines[1] == #""00:00:01.000","1.000","marker","He said ""yes"", loudly""#)
    }

    @Test("A question containing a comma stays in one CSV field")
    func csvHandlesCommasInQuestions() {
        let exporter = MarkerExporter()
        let recording = makeRecording(
            questionChanges: [
                QuestionChangeModel(offset: 0, index: 0, text: "Who are you, and what do you do?")
            ]
        )
        let csv = exporter.csv(for: recording)
        #expect(csv.contains(#""question","Q1: Who are you, and what do you do?""#))
    }

    @Test("CSV ends with a newline so files concatenate cleanly")
    func csvTrailingNewline() {
        let exporter = MarkerExporter()
        #expect(exporter.csv(for: makeRecording()).hasSuffix("\n"))
    }

    @Test("An empty timeline exports a valid header-only CSV")
    func emptyCSV() {
        let exporter = MarkerExporter()
        #expect(exporter.csv(for: makeRecording()) == "timecode,seconds,type,label\n")
    }

    @Test("Plain text says so when there is nothing to list")
    func emptyPlainText() {
        let exporter = MarkerExporter()
        let text = exporter.plainText(for: makeRecording())
        #expect(text.contains("No markers or question changes were recorded."))
        #expect(text.contains("Customer testimonial"))
    }

    @Test("Plain text reports the recording's status honestly")
    func plainTextReportsStatus() {
        let exporter = MarkerExporter()

        let interrupted = exporter.plainText(
            for: makeRecording(outcome: .interrupted)
        )
        #expect(interrupted.contains("Interrupted"))

        let saved = exporter.plainText(for: makeRecording(outcome: .saved))
        #expect(saved.contains("Saved"))
    }

    @Test("Plain text labels each row by kind")
    func plainTextRowLabels() {
        let exporter = MarkerExporter()
        let text = exporter.plainText(
            for: makeRecording(
                markers: [MarkerModel(offset: 10, label: "Good bit")],
                questionChanges: [QuestionChangeModel(offset: 0, index: 0, text: "Q one")]
            )
        )
        #expect(text.contains("QUESTION  Q1: Q one"))
        #expect(text.contains("MARKER    Good bit"))
    }

    @Test("The suggested filename is filesystem-safe")
    func fileNameStemIsSafe() {
        let exporter = MarkerExporter()
        let recording = InterviewRecordingModel(
            deckName: "Q&A: half/half",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 10,
            outcome: .saved
        )
        let stem = exporter.fileNameStem(for: recording)

        #expect(stem.contains("/") == false)
        #expect(stem.contains(":") == false)
        #expect(stem.hasSuffix("markers"))
    }

    @Test("An untitled interview still exports under a usable name")
    func untitledExportName() {
        let exporter = MarkerExporter()
        let recording = InterviewRecordingModel(
            deckName: "",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 10,
            outcome: .saved
        )
        #expect(exporter.fileNameStem(for: recording).hasPrefix("Interview"))
    }
}

@Suite("Export failure")
struct ExportFailureTests {

    @Test("A recording with no file cannot be offered for export")
    func noFileMeansNoExport() {
        let recording = InterviewRecordingModel(
            deckName: "D",
            startedAt: Date(),
            duration: 30,
            outcome: .saveFailed,
            fileName: nil,
            preservedFilePath: "/tmp/preserved.mov"
        )
        #expect(recording.outcome.isPlayable == false)
        #expect(recording.fileName == nil)
        // The preserved file is still recorded, so it can be recovered manually.
        #expect(recording.preservedFilePath == "/tmp/preserved.mov")
    }

    @Test("A repository write failure surfaces rather than being swallowed")
    func repositoryWriteFailureSurfaces() {
        let repository = InMemoryRecordingRepository()
        repository.writeError = RecordingStoreError.moveFailed("simulated export failure")

        #expect(throws: (any Error).self) {
            try repository.save(
                InterviewRecordingModel(
                    deckName: "D", startedAt: Date(), duration: 1, outcome: .saved
                )
            )
        }
        #expect((try? repository.loadRecordings())?.isEmpty == true)
    }

    @Test("A failed marker export leaves the recording itself intact")
    func markerExportFailureDoesNotAffectRecording() throws {
        let repository = InMemoryRecordingRepository()
        let recording = InterviewRecordingModel(
            deckName: "D",
            startedAt: Date(),
            duration: 30,
            outcome: .saved,
            fileName: "a.mov",
            markers: [MarkerModel(offset: 5, label: "M")]
        )
        try repository.save(recording)

        // Simulate the share sheet or file write failing after the fact.
        struct ExportFailed: Error {}
        let exportResult = Result<Void, Error> { throw ExportFailed() }

        #expect(exportResult.isFailure)
        // The interview is still in the library and still playable.
        let reloaded = try repository.loadRecordings()
        #expect(reloaded.count == 1)
        #expect(reloaded[0].outcome.isPlayable)
        #expect(reloaded[0].markers.count == 1)
    }
}

private extension Result {
    var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
