import AVFoundation
import Foundation
import SwiftData
import PromptCamCore

/// The app's dependency container.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
///
/// Everything hardware-dependent is reached through a protocol so it can be
/// replaced in a test or a preview: capture, permissions, storage and the deck
/// and recording repositories. Capability comes from `DuoCapabilityProvider`,
/// which performs no device detection.
@MainActor
final class AppEnvironment {
    let capabilities: DeviceCapabilities
    let flags: FeatureFlags
    let store: RecordingFileStore
    let permissions: AVPermissionService
    let deckRepository: any DeckRepository
    let recordingRepository: any RecordingRepository


    init(modelContext: ModelContext) {
        self.capabilities = DuoCapabilityProvider.current()
        self.flags = .default
        self.store = RecordingFileStore()
        self.permissions = AVPermissionService()
        self.deckRepository = SwiftDataDeckRepository(context: modelContext)
        self.recordingRepository = SwiftDataRecordingRepository(context: modelContext)
    }

    func makeDeckLibraryModel() -> DeckLibraryModel {
        DeckLibraryModel(repository: deckRepository)
    }

    func makeRecordingsLibraryModel() -> RecordingsLibraryModel {
        RecordingsLibraryModel(repository: recordingRepository, store: store)
    }

    /// One interview, with the capture pipeline it owns.
    ///
    /// `CaptureService.events` is a single-consumer `AsyncStream`, and
    /// `tearDown()` finishes that stream — so a service cannot be reused across
    /// takes, and two session models sharing one service would compete for the
    /// same events. Each session therefore gets its own pipeline, and hands
    /// back its own `AVCaptureSession` for the preview layer.
    struct PreparedSession: Identifiable {
        let id = UUID()
        let model: DirectorSessionModel
        let previewSession: AVCaptureSession
    }

    func makeSession(
        deck: DeckModel,
        options: SubjectDisplayOptions
    ) -> PreparedSession {
        let capture = AVFoundationCaptureService()
        let model = DirectorSessionModel(
            deckName: deck.displayName,
            questions: deck.sessionQuestionTexts,
            displayOptions: options,
            capabilities: capabilities,
            flags: flags,
            captureService: capture,
            store: store,
            recordings: recordingRepository,
            permissions: permissions
        )
        return PreparedSession(model: model, previewSession: capture.captureSession)
    }
}
