import SwiftUI
import PromptCamCore

/// The app's shell.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
///
/// Uses `TabView` — one of the standard adaptive containers — rather than a
/// bespoke layout, so it adapts across size classes and device configurations
/// without PromptCam guessing at geometry.
struct RootView: View {
    let environment: AppEnvironment
    let isUsingEphemeralStore: Bool

    @State private var pendingDeck: DeckModel?
    @State private var activeSession: ActiveSession?
    @State private var selectedTab = Tab.decks

    enum Tab: Hashable {
        case decks
        case interviews
    }

    /// A configured, running interview.
    struct ActiveSession: Identifiable {
        let id = UUID()
        let model: DirectorSessionModel
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Decks", systemImage: "list.bullet.rectangle", value: Tab.decks) {
                NavigationStack {
                    VStack(spacing: 0) {
                        if isUsingEphemeralStore {
                            ephemeralStoreBanner
                        }
                        DeckListView(model: environment.makeDeckLibraryModel()) { deck in
                            pendingDeck = deck
                        }
                    }
                    .navigationDestination(item: $pendingDeck) { deck in
                        RecordingSetupView(
                            deck: deck,
                            capabilities: environment.capabilities,
                            flags: environment.flags,
                            permissions: environment.permissions
                        ) { options in
                            activeSession = ActiveSession(
                                model: environment.makeSessionModel(deck: deck, options: options)
                            )
                        }
                    }
                }
            }

            Tab("Interviews", systemImage: "film", value: Tab.interviews) {
                NavigationStack {
                    RecordingsListView(model: environment.makeRecordingsLibraryModel())
                }
            }
        }
        .fullScreenCover(item: $activeSession) { session in
            DirectorSessionView(
                model: session.model,
                previewSession: environment.captureService.captureSession
            ) {
                Task {
                    await session.model.end()
                    activeSession = nil
                    pendingDeck = nil
                    // Land on the library so a finished interview is visible
                    // immediately rather than having to be hunted for.
                    selectedTab = .interviews
                }
            }
        }
    }

    /// Tells the user plainly that nothing will be kept this session.
    private var ephemeralStoreBanner: some View {
        HStack(spacing: Theme.Space.snug) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Storage is unavailable, so decks and interviews won't be kept after you close PromptCam.")
                .font(.footnote)
        }
        .foregroundStyle(.white)
        .padding(Theme.Space.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.warning)
    }
}
