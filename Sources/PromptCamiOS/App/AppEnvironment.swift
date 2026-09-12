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

    /// The live capture service.
    ///
    /// One instance for the app's lifetime so the preview layer and the
    /// recorder share a session, and so the camera is opened once.
    let captureService: AVFoundationCaptureService

    init(modelContext: ModelContext) {
        self.capabilities = DuoCapabilityProvider.current()
        self.flags = .default
        self.store = RecordingFileStore()
        self.permissions = AVPermissionService()
        self.deckRepository = SwiftDataDeckRepository(context: modelContext)
        self.recordingRepository = SwiftDataRecordingRepository(context: modelContext)
        self.captureService = AVFoundationCaptureService()
    }

    func makeDeckLibraryModel() -> DeckLibraryModel {
        DeckLibraryModel(repository: deckRepository)
    }

    func makeRecordingsLibraryModel() -> RecordingsLibraryModel {
        RecordingsLibraryModel(repository: recordingRepository, store: store)
    }

    func makeSessionModel(
        deck: DeckModel,
        options: SubjectDisplayOptions
    ) -> DirectorSessionModel {
        DirectorSessionModel(
            deckName: deck.displayName,
            questions: deck.sessionQuestionTexts,
            displayOptions: options,
            capabilities: capabilities,
            flags: flags,
            captureService: captureService,
            store: store,
            recordings: recordingRepository,
            permissions: permissions
        )
    }
}
