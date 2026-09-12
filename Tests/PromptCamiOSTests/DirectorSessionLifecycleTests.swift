import Foundation
import Testing
@testable import PromptCam
import PromptCamCore

/// These tests compile inside the iOS project, not the platform-independent
/// Swift package. They exercise the real DirectorSessionModel event ordering
/// with scripted services so the asynchronous seam is covered directly.
@MainActor
@Suite("Director session lifecycle regressions")
struct DirectorSessionLifecycleTests {

    @Test("Startup timeout requests stop and a delayed start is stopped again")
    func timeoutThenDelayedStart() async throws {
        let fixture = try Fixture(
            startEvent: nil,
            startTimeout: .milliseconds(30),
            finalisationTimeout: .seconds(2)
        )
        await fixture.startTake()

        try await eventually { fixture.model.state.isTerminal }
        #expect(fixture.capture.stopCount >= 1)

        fixture.capture.emit(.recordingStarted)
        try await eventually { fixture.capture.stopCount >= 2 }
        #expect(fixture.model.state.isTerminal)
    }

    @Test("Runtime error still accepts and reconciles the later completed file")
    func runtimeErrorThenCompletion() async throws {
        let fixture = try Fixture(startEvent: .recordingStarted)
        await fixture.startTake()
        try await eventually { fixture.model.canAddMarker }

        let path = try #require(fixture.capture.recordingPath)
        try Data("partial-video".utf8).write(to: URL(fileURLWithPath: path))
        fixture.capture.emit(.runtimeError(.captureFailed("simulated runtime error")))
        try await eventually { fixture.model.state.isTerminal }

        fixture.capture.emit(.recordingFinished(path: path, duration: 4))
        try await eventually {
            fixture.repository.items.first?.preservedFilePath != nil
        }

        #expect(fixture.repository.items.count == 1)
        #expect(fixture.repository.items[0].outcome == .failed)
        let recovered = try #require(fixture.repository.items[0].preservedFilePath)
        #expect(FileManager.default.fileExists(atPath: recovered))
        #expect(recovered.contains("Recovery"))
    }

    @Test("A duplicate completion cannot file or persist twice")
    func duplicateCompletion() async throws {
        let fixture = try Fixture(startEvent: .recordingStarted)
        await fixture.startTake()
        try await eventually { fixture.model.canAddMarker }

        let path = try #require(fixture.capture.recordingPath)
        try Data("video".utf8).write(to: URL(fileURLWithPath: path))
        fixture.model.tapStop()
        fixture.capture.emit(.recordingFinished(path: path, duration: 3))
        fixture.capture.emit(.recordingFinished(path: path, duration: 3))

        try await eventually { fixture.repository.items.first?.outcome == .saved }
        #expect(fixture.repository.items.count == 1)
        let storedFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.store.recordingsDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(storedFiles.count == 1)
    }

    @Test("Interruption without completion records a protected fallback path")
    func interruptionWithoutCompletion() async throws {
        let fixture = try Fixture(
            startEvent: .recordingStarted,
            finalisationTimeout: .milliseconds(30)
        )
        await fixture.startTake()
        try await eventually { fixture.model.canAddMarker }

        let path = try #require(fixture.capture.recordingPath)
        try Data("partial".utf8).write(to: URL(fileURLWithPath: path))
        fixture.capture.emit(.interrupted(.backgrounded))

        try await eventually {
            fixture.repository.items.first?.preservedFilePath == path
        }
        #expect(fixture.capture.tearDownCount >= 1)

        // A new session's aggressive sweep must still protect the path recorded
        // by the repository, even though it could not be moved without a final
        // AVFoundation callback.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-7_200)],
            ofItemAtPath: path
        )
        await fixture.model.startAnotherTake()
        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test("Markers and timeline entries cannot precede the first byte")
    func noPreStartTimestamps() async throws {
        let fixture = try Fixture(startEvent: nil)
        await fixture.startTake()
        try await eventually { fixture.capture.recordingPath != nil }

        fixture.model.addMarker()
        fixture.model.nextQuestionTapped()
        #expect(fixture.model.engine.markers.isEmpty)
        #expect(fixture.model.engine.questionChanges.isEmpty)

        fixture.capture.emit(.recordingStarted)
        try await eventually { fixture.model.canAddMarker }
        fixture.model.addMarker()
        #expect(fixture.model.engine.markers.count == 1)
    }

    private func eventually(
        attempts: Int = 200,
        condition: @MainActor () -> Bool
    ) async throws {
        for _ in 0..<attempts {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Condition did not become true before timeout")
    }
}

@MainActor
private final class Fixture {
    let capture: ScriptedCaptureService
    let store: RecordingFileStore
    let repository = LifecycleRecordingRepository()
    let model: DirectorSessionModel
    private let root: URL

    init(
        startEvent: CaptureEvent?,
        startTimeout: Duration = .seconds(2),
        finalisationTimeout: Duration = .seconds(2)
    ) throws {
        capture = ScriptedCaptureService(startEvent: startEvent)
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptCam-iOS-tests-\(UUID().uuidString)", isDirectory: true)
        store = RecordingFileStore(baseDirectory: root)
        model = DirectorSessionModel(
            deckName: "Interview",
            questions: ["First?", "Second?"],
            displayOptions: .default,
            capabilities: .ordinaryPhone,
            flags: .default,
            captureService: capture,
            store: store,
            recordings: repository,
            permissions: AuthorizedPermissions(),
            countdownSeconds: 1,
            captureStartTimeout: startTimeout,
            captureFinalisationTimeout: finalisationTimeout
        )
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func startTake() async {
        await model.begin()
        // Let the ready event reach the model before tapping Record.
        for _ in 0..<20 where model.state == .idle {
            await Task.yield()
        }
        model.tapRecord()
        try? await Task.sleep(for: .milliseconds(1_100))
    }
}

private final class ScriptedCaptureService: CaptureService, @unchecked Sendable {
    let events: AsyncStream<CaptureEvent>
    private let continuation: AsyncStream<CaptureEvent>.Continuation
    private let startEvent: CaptureEvent?
    private let lock = NSLock()
    private var _stopCount = 0
    private var _tearDownCount = 0
    private var _recordingPath: String?

    init(startEvent: CaptureEvent?) {
        self.startEvent = startEvent
        var captured: AsyncStream<CaptureEvent>.Continuation!
        events = AsyncStream { captured = $0 }
        continuation = captured
    }

    var stopCount: Int { lock.withLock { _stopCount } }
    var tearDownCount: Int { lock.withLock { _tearDownCount } }
    var recordingPath: String? { lock.withLock { _recordingPath } }

    func prepare(direction: CaptureDirection) async { continuation.yield(.ready) }

    func startRecording(toPath path: String) async {
        lock.withLock { _recordingPath = path }
        if let startEvent { continuation.yield(startEvent) }
    }

    func stopRecording() async { lock.withLock { _stopCount += 1 } }
    func tearDown() async { lock.withLock { _tearDownCount += 1 } }
    func emit(_ event: CaptureEvent) { continuation.yield(event) }
}

private struct AuthorizedPermissions: PermissionService {
    func status(for permission: CapturePermission) async -> PermissionStatus { .authorized }
    func request(_ permission: CapturePermission) async -> PermissionStatus { .authorized }
}

@MainActor
private final class LifecycleRecordingRepository: RecordingRepository {
    private(set) var items: [InterviewRecordingModel] = []

    func loadRecordings() async throws -> [InterviewRecordingModel] { items }

    func save(_ recording: InterviewRecordingModel) async throws {
        if let index = items.firstIndex(where: { $0.id == recording.id }) {
            items[index] = recording
        } else {
            items.append(recording)
        }
    }

    func delete(recordingID: UUID) async throws {
        items.removeAll { $0.id == recordingID }
    }
}
