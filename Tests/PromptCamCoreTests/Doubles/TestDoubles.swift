import Foundation
@testable import PromptCamCore

// MARK: - Capture

/// A capture pipeline the tests drive by hand.
///
/// Lets camera failure, microphone failure, interruption, mid-recording
/// failure and successful finalisation all be exercised with no hardware.
final class FakeCaptureService: CaptureService, @unchecked Sendable {
    enum Call: Equatable {
        case prepare(CaptureDirection)
        case startRecording(String)
        case stopRecording
        case tearDown
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private let continuation: AsyncStream<CaptureEvent>.Continuation
    let events: AsyncStream<CaptureEvent>

    /// What `prepare` should emit.
    var prepareOutcome: CaptureEvent = .ready
    /// What `startRecording` should emit immediately, if anything.
    var startOutcome: CaptureEvent? = .recordingStarted

    init() {
        var capturedContinuation: AsyncStream<CaptureEvent>.Continuation!
        events = AsyncStream { capturedContinuation = $0 }
        continuation = capturedContinuation
    }

    var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    private func record(_ call: Call) {
        lock.lock(); _calls.append(call); lock.unlock()
    }

    func prepare(direction: CaptureDirection) async {
        record(.prepare(direction))
        continuation.yield(prepareOutcome)
    }

    func startRecording(toPath path: String) async {
        record(.startRecording(path))
        if let startOutcome { continuation.yield(startOutcome) }
    }

    func stopRecording() async {
        record(.stopRecording)
    }

    func tearDown() async {
        record(.tearDown)
        continuation.finish()
    }

    /// Pushes an arbitrary event, as the real pipeline would.
    func emit(_ event: CaptureEvent) {
        continuation.yield(event)
    }
}

// MARK: - Permissions

/// A permission service with scripted answers.
final class FakePermissionService: PermissionService, @unchecked Sendable {
    private let lock = NSLock()
    private var statuses: [CapturePermission: PermissionStatus]
    /// What each permission becomes after being requested.
    private var afterRequest: [CapturePermission: PermissionStatus]
    private(set) var requestedPermissions: [CapturePermission] = []

    init(
        camera: PermissionStatus = .authorized,
        microphone: PermissionStatus = .authorized,
        cameraAfterRequest: PermissionStatus? = nil,
        microphoneAfterRequest: PermissionStatus? = nil
    ) {
        statuses = [.camera: camera, .microphone: microphone]
        afterRequest = [
            .camera: cameraAfterRequest ?? camera,
            .microphone: microphoneAfterRequest ?? microphone
        ]
    }

    func status(for permission: CapturePermission) async -> PermissionStatus {
        lock.lock(); defer { lock.unlock() }
        return statuses[permission] ?? .notDetermined
    }

    @discardableResult
    func request(_ permission: CapturePermission) async -> PermissionStatus {
        lock.lock()
        requestedPermissions.append(permission)
        let resolved = afterRequest[permission] ?? .denied
        statuses[permission] = resolved
        lock.unlock()
        return resolved
    }

    func snapshot() async -> PermissionSnapshot {
        PermissionSnapshot(
            camera: await status(for: .camera),
            microphone: await status(for: .microphone)
        )
    }
}

// MARK: - Repositories

/// An in-memory deck store, so persistence and reload can be tested without a
/// database.
final class InMemoryDeckRepository: DeckRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID: DeckModel] = [:]
    private var seeded = false
    /// When set, every write throws, to exercise save-failure paths.
    var writeError: Error?

    init(initial: [DeckModel] = []) {
        for deck in initial { storage[deck.id] = deck }
    }

    func loadDecks() async throws -> [DeckModel] {
        lock.lock(); defer { lock.unlock() }
        return storage.values.sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ deck: DeckModel) async throws {
        if let writeError { throw writeError }
        lock.lock(); storage[deck.id] = deck; lock.unlock()
    }

    func delete(deckID: UUID) async throws {
        if let writeError { throw writeError }
        lock.lock(); storage[deckID] = nil; lock.unlock()
    }

    func seedSampleDeckIfNeeded(now: Date) async throws {
        lock.lock()
        let alreadySeeded = seeded
        seeded = true
        lock.unlock()
        guard !alreadySeeded else { return }
        try await save(DeckModel.sampleTestimonialDeck(now: now))
    }
}

final class InMemoryRecordingRepository: RecordingRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID: InterviewRecordingModel] = [:]
    var writeError: Error?

    func loadRecordings() async throws -> [InterviewRecordingModel] {
        lock.lock(); defer { lock.unlock() }
        return storage.values.sorted { $0.startedAt > $1.startedAt }
    }

    func save(_ recording: InterviewRecordingModel) async throws {
        if let writeError { throw writeError }
        lock.lock(); storage[recording.id] = recording; lock.unlock()
    }

    func delete(recordingID: UUID) async throws {
        lock.lock(); storage[recordingID] = nil; lock.unlock()
    }
}

// MARK: - Recording store

/// A recording store backed by a real temporary directory.
///
/// Used so "save failure must preserve the file" can be asserted against the
/// actual file system rather than a mock.
final class TestRecordingStore: RecordingStore, @unchecked Sendable {
    let root: URL
    /// When set, `store` throws this and must leave the temporary file alone.
    var storeError: RecordingStoreError?

    init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PromptCamTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    var recordingsDirectory: URL { root.appendingPathComponent("Recordings", isDirectory: true) }
    var temporaryDirectory: URL { root.appendingPathComponent("Temp", isDirectory: true) }
    var recoveryDirectory: URL { root.appendingPathComponent("Recovery", isDirectory: true) }
    var recordingsDirectoryPath: String { recordingsDirectory.path }

    /// When set, `preserveForRecovery` throws, leaving the file where it was.
    var preserveError: RecordingStoreError?

    func makeTemporaryPath() throws -> String {
        temporaryDirectory.appendingPathComponent("capture-\(UUID().uuidString).mov").path
    }

    func store(temporaryPath: String, startedAt: Date) throws -> StoredRecording {
        guard FileManager.default.fileExists(atPath: temporaryPath) else {
            throw RecordingStoreError.temporaryFileMissing
        }
        if let storeError { throw storeError }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let fileName = "Interview-\(formatter.string(from: startedAt)).mov"
        let destination = recordingsDirectory.appendingPathComponent(fileName)
        try FileManager.default.moveItem(atPath: temporaryPath, toPath: destination.path)
        return StoredRecording(path: destination.path, fileName: fileName)
    }

    func preserveForRecovery(temporaryPath: String) throws -> String {
        guard FileManager.default.fileExists(atPath: temporaryPath) else {
            throw RecordingStoreError.temporaryFileMissing
        }
        if let preserveError { throw preserveError }

        let source = URL(fileURLWithPath: temporaryPath)
        if source.deletingLastPathComponent().standardizedFileURL
            == recoveryDirectory.standardizedFileURL {
            return temporaryPath
        }
        let destination = recoveryDirectory
            .appendingPathComponent("Recovered-\(UUID().uuidString).mov")
        try FileManager.default.moveItem(at: source, to: destination)
        return destination.path
    }

    func preservedFileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func cleanUpAbandonedTemporaryFiles(
        excluding activePaths: Set<String>,
        olderThan age: TimeInterval
    ) throws {
        let contents = try FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        let cutoff = Date().addingTimeInterval(-age)
        let active = Set(activePaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })

        for url in contents {
            guard !active.contains(url.standardizedFileURL.path) else { continue }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let modified, modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Backdates a file so age-based cleanup can be tested without waiting.
    func backdate(path: String, by seconds: TimeInterval) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-seconds)],
            ofItemAtPath: path
        )
    }

    /// Creates a stand-in captured file so store paths can be exercised.
    func writeFakeCapture(at path: String, bytes: Int = 1024) throws {
        let data = Data(repeating: 0x1A, count: bytes)
        try data.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Subject display

final class FakeSubjectDisplayObserver: SubjectDisplayAvailabilityObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var _availability: SubjectDisplayAvailability

    init(availability: SubjectDisplayAvailability = .unsupported) {
        _availability = availability
    }

    var availability: SubjectDisplayAvailability {
        lock.lock(); defer { lock.unlock() }
        return _availability
    }

    func set(_ value: SubjectDisplayAvailability) {
        lock.lock(); _availability = value; lock.unlock()
    }
}

// MARK: - Helpers

extension InterviewSessionEngine {
    /// Builds an engine already prepared and recording, for tests that care
    /// about what happens *during* a take.
    static func recording(
        questions: [String] = ["Q1", "Q2", "Q3"],
        capabilities: DeviceCapabilities = .ordinaryPhone,
        flags: FeatureFlags = .default,
        startedAt: Date,
        temporaryPath: String = "/tmp/promptcam-test.mov"
    ) throws -> InterviewSessionEngine {
        var engine = InterviewSessionEngine(
            deckName: "Test deck",
            questions: questions,
            capabilities: capabilities,
            flags: flags
        )
        try engine.prepare()
        try engine.markPrepared()
        try engine.beginRecording(at: startedAt, temporaryPath: temporaryPath)
        return engine
    }
}
