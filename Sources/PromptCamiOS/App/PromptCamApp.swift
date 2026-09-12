import SwiftData
import SwiftUI
import PromptCamCore

/// The application entry point.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
///
/// A SwiftUI `App` with a `WindowGroup` already satisfies the iOS 27
/// requirement that applications adopt the scene-based life cycle.
@main
struct PromptCamApp: App {

    /// How storage resolved at launch.
    private enum Storage {
        /// The on-disk store opened normally.
        case persistent(ModelContainer)
        /// The on-disk store failed, so an in-memory store is being used. The
        /// user is told, because nothing will be kept.
        case ephemeral(ModelContainer)
        /// Storage could not be opened at all.
        case unavailable(String)
    }

    private let storage: Storage

    init() {
        do {
            storage = .persistent(try PromptCamSchema.makeContainer())
        } catch {
            // Degrade to memory rather than crashing on launch, but never
            // pretend the user's decks are safe.
            do {
                storage = .ephemeral(try PromptCamSchema.makeEphemeralContainer())
            } catch {
                storage = .unavailable(error.localizedDescription)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            switch storage {
            case .persistent(let container):
                root(container: container, isEphemeral: false)
            case .ephemeral(let container):
                root(container: container, isEphemeral: true)
            case .unavailable(let message):
                StorageFailureView(message: message)
            }
        }
    }

    private func root(container: ModelContainer, isEphemeral: Bool) -> some View {
        RootView(
            environment: AppEnvironment(modelContext: container.mainContext),
            isUsingEphemeralStore: isEphemeral
        )
        .modelContainer(container)
    }
}

/// Shown when storage cannot be opened at all.
///
/// An honest dead end rather than a crash, with something the user can act on.
struct StorageFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("PromptCam can't start", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            VStack(spacing: Theme.Space.regular) {
                Text("Local storage could not be opened, so decks and recordings cannot be saved.")
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Restarting the device, or freeing up storage space, usually resolves this.")
                    .font(.footnote)
            }
        }
    }
}
