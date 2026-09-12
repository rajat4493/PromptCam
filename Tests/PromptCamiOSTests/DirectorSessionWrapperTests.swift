import Testing
import Foundation
import PromptCamCore
@testable import PromptCam

/// Tests for the **iOS wrapper**, not for orchestration.
///
/// Orchestration lives in `InterviewSessionCoordinator` in `PromptCamCore` and
/// is covered by `SessionCoordinatorTests`, which run under `swift test` with
/// no Xcode and no simulator. Duplicating those scenarios here would test the
/// same logic through an indirection and would only run on a Mac.
///
/// What this target is genuinely for is everything the wrapper alone owns:
/// mirroring coordinator state into `@Observable` properties, consuming the
/// capture event stream, and tearing down cleanly. Later it is also the right
/// home for tests of `Sources/PromptCamiOS/Platform` once those APIs are
/// confirmed on a Mac.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC. Never compiled or executed.
@MainActor
@Suite("Director session wrapper")
struct DirectorSessionWrapperTests {

    private func makeModel(
        questions: [String] = ["Q1", "Q2"],
        camera: PermissionStatus = .authorized,
        microphone: PermissionStatus = .authorized
    ) -> (DirectorSessionModel, ScriptedCaptureService, InMemoryRecordings) {
        let capture = ScriptedCaptureService()
        let recordings = InMemoryRecordings()
        let model = DirectorSessionModel(
            deckName: "Test deck",
            questions: questions,
            displayOptions: .default,
            capabilities: .ordinaryPhone,
            flags: .default,
            captureService: capture,
            store: RecordingFileStore(),
            recordings: recordings,
            permissions: StubPermissions(camera: camera, microphone: microphone)
        )
        return (model, capture, recordings)
    }

    @Test("Initial mirrored state matches a fresh session")
    func initialState() {
        let (model, _, _) = makeModel()

        #expect(model.state == .idle)
        #expect(model.elapsed == 0)
        #expect(model.markerCount == 0)
        #expect(model.currentQuestion == "Q1")
        #expect(model.nextQuestion == "Q2")
        #expect(model.questionPosition == "1 of 2")
        #expect(model.canAddMarker == false)
        #expect(model.alert == nil)
        // An ordinary phone offers no subject surface, so no Duo-only control
        // may appear — not even disabled.
        #expect(model.showsSubjectControls == false)
    }

    @Test("A deck with no questions still produces usable mirrored state")
    func emptyDeck() {
        let (model, _, _) = makeModel(questions: [])
        #expect(model.currentQuestion == nil)
        #expect(model.questionPosition == "No questions")
        #expect(model.canGoToNextQuestion == false)
        #expect(model.canGoToPreviousQuestion == false)
    }

    @Test("Question navigation updates the mirrored properties")
    func navigationMirrors() {
        let (model, _, _) = makeModel(questions: ["First", "Second", "Third"])

        model.nextQuestionTapped()
        #expect(model.currentQuestion == "Second")
        #expect(model.nextQuestion == "Third")
        #expect(model.questionPosition == "2 of 3")
        #expect(model.canGoToPreviousQuestion)

        model.previousQuestionTapped()
        #expect(model.currentQuestion == "First")
        #expect(model.canGoToPreviousQuestion == false)
    }

    @Test("Denied permission surfaces an alert offering Settings")
    func deniedPermissionMirrorsAlert() async {
        let (model, capture, _) = makeModel(camera: .denied)

        await model.begin()

        #expect(model.state == .failed(.cameraPermissionDenied))
        #expect(model.alert != nil)
        #expect(model.alert?.offersSettings == true)
        #expect(capture.prepareCount == 0, "The camera must not be configured")
        await model.end()
    }

    @Test("The subject snapshot mirrors and carries no director-only content")
    func subjectSnapshotMirrors() {
        let (model, _, _) = makeModel(questions: ["Visible", "UPCOMING"])

        #expect(model.subjectSnapshot.questionText == "Visible")
        #expect(model.subjectSnapshot.questionCount == 2)
        // The director can see what is next; the snapshot type cannot carry it.
        #expect(model.nextQuestion == "UPCOMING")
    }

    @Test("An accessory callback never changes recording state")
    func accessoryCallbacksAreInert() {
        let (model, _, _) = makeModel()
        let before = model.state

        model.subjectAccessoryAvailabilityChanged(true)
        model.subjectAccessoryPresentationChanged(true)
        model.subjectAccessoryPresentationChanged(false)

        #expect(model.state == before)
    }

    @Test("A fold warning appears only when partly folded and not recording")
    func foldWarning() {
        let (model, _, _) = makeModel()
        #expect(model.foldWarning == nil)

        model.foldPositionChanged(.partiallyOpen(degrees: 95))
        #expect(model.foldWarning != nil)

        model.foldPositionChanged(.fullyOpen)
        #expect(model.foldWarning == nil)
    }

    @Test("end() tears the pipeline down and can be called twice safely")
    func endIsIdempotent() async {
        let (model, capture, _) = makeModel()
        await model.begin()

        await model.end()
        await model.end()

        #expect(capture.tearDownCount >= 1)
    }
}

// MARK: - Doubles
//
// Local to this target. `PromptCamCoreTests` has its own; duplicating a handful
// of stubs is better than making a test-support product just to share them.

private final class ScriptedCaptureService: CaptureService, @unchecked Sendable {
    let events: AsyncStream<CaptureEvent>
    private let continuation: AsyncStream<CaptureEvent>.Continuation
    private let lock = NSLock()
    private var _prepareCount = 0
    private var _tearDownCount = 0

    init() {
        var captured: AsyncStream<CaptureEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured
    }

    var prepareCount: Int { lock.lock(); defer { lock.unlock() }; return _prepareCount }
    var tearDownCount: Int { lock.lock(); defer { lock.unlock() }; return _tearDownCount }

    func prepare(direction: CaptureDirection) async {
        lock.lock(); _prepareCount += 1; lock.unlock()
        continuation.yield(.ready)
    }
    func startRecording(toPath path: String) async {}
    func stopRecording() async {}
    func tearDown() async {
        lock.lock(); _tearDownCount += 1; lock.unlock()
        continuation.finish()
    }
    func emit(_ event: CaptureEvent) { continuation.yield(event) }
}

private struct StubPermissions: PermissionService {
    let camera: PermissionStatus
    let microphone: PermissionStatus

    func status(for permission: CapturePermission) async -> PermissionStatus {
        permission == .camera ? camera : microphone
    }
    @discardableResult
    func request(_ permission: CapturePermission) async -> PermissionStatus {
        await status(for: permission)
    }
}

private final class InMemoryRecordings: RecordingRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [InterviewRecordingModel] = []

    func loadRecordings() async throws -> [InterviewRecordingModel] {
        lock.lock(); defer { lock.unlock() }; return items
    }
    func save(_ recording: InterviewRecordingModel) async throws {
        lock.lock(); defer { lock.unlock() }
        if let index = items.firstIndex(where: { $0.id == recording.id }) {
            items[index] = recording
        } else {
            items.append(recording)
        }
    }
    func delete(recordingID: UUID) async throws {
        lock.lock(); defer { lock.unlock() }
        items.removeAll { $0.id == recordingID }
    }
}
