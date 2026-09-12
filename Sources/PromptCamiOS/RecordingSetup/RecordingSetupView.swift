import SwiftUI
import UIKit
import PromptCamCore

/// The screen between "I picked a deck" and "we're rolling".
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
///
/// Does three jobs: let the operator review the running order, choose what the
/// subject sees, and resolve permissions *before* the camera screen rather than
/// with a system prompt over the viewfinder.
struct RecordingSetupView: View {
    let deck: DeckModel
    let capabilities: DeviceCapabilities
    let flags: FeatureFlags
    let permissions: AVPermissionService
    /// Called with the operator's chosen options when they are ready to record.
    let onStart: (SubjectDisplayOptions) -> Void

    @State private var options = SubjectDisplayOptions.default
    @State private var permissionSnapshot: PermissionSnapshot?
    @State private var isRequesting = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            runningOrderSection
            subjectDisplaySection
            permissionSection
            startSection
        }
        .navigationTitle("Get ready")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshPermissions() }
    }

    // MARK: - Running order

    private var runningOrderSection: some View {
        Section {
            ForEach(Array(deck.sessionQuestionTexts.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.regular) {
                    Text("\(index + 1)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                    Text(text)
                }
            }
        } header: {
            Text("Running order")
        } footer: {
            Text("You can move between questions while recording. Each change is timestamped.")
        }
    }

    // MARK: - Subject display

    @ViewBuilder
    private var subjectDisplaySection: some View {
        // Hidden entirely on a device with no subject surface, rather than
        // shown as a set of dead switches.
        if capabilities.supportsSubjectAccessory {
            Section {
                Toggle("Current question", isOn: $options.showsQuestion)
                Toggle("Countdown", isOn: $options.showsCountdown)
                Toggle("Recording status", isOn: $options.showsRecordingStatus)
                Toggle("Short instruction", isOn: $options.showsSubjectInstruction)

                if flags.subjectLivePreviewEnabled {
                    Toggle("Mirrored preview", isOn: $options.showsLivePreview)
                }
            } header: {
                Text("What the subject sees")
            } footer: {
                subjectDisplayFooter
            }
        } else {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: Theme.Space.tight) {
                        Text("Director overlay").font(.subheadline.weight(.medium))
                        Text("This device shows the current question to you in the camera view. On a device with a second display, PromptCam can show it to the person you're interviewing instead.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "iphone")
                }
            }
        }
    }

    @ViewBuilder
    private var subjectDisplayFooter: some View {
        if flags.subjectLivePreviewEnabled {
            Text("The subject never sees upcoming questions or your controls.")
        } else {
            // Honest about the preview rather than hiding the limitation.
            Text("The subject never sees upcoming questions or your controls. A mirrored camera preview is not available in this version.")
        }
    }

    // MARK: - Permissions

    @ViewBuilder
    private var permissionSection: some View {
        if let snapshot = permissionSnapshot, !snapshot.canRecord {
            Section {
                ForEach(snapshot.blocking, id: \.self) { permission in
                    permissionRow(permission, status: status(for: permission, in: snapshot))
                }
            } header: {
                Text("Permissions needed")
            }
        }
    }

    private func permissionRow(_ permission: CapturePermission, status: PermissionStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.snug) {
            Label(permission.displayName, systemImage: permission == .camera ? "camera" : "mic")
                .font(.subheadline.weight(.medium))

            Text(permission.rationale)
                .font(.footnote)
                .foregroundStyle(.secondary)

            // The recovery path differs by status, which is why
            // `PermissionStatus` distinguishes denied from restricted.
            switch status {
            case .notDetermined:
                Button("Allow \(permission.displayName.lowercased())") {
                    Task { await request(permission) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequesting)

            case .denied:
                VStack(alignment: .leading, spacing: Theme.Space.tight) {
                    Text("Access was turned down. Open Settings › PromptCam and switch \(permission.displayName) on.")
                        .font(.footnote)
                    Button("Open Settings") { openSettings() }
                        .buttonStyle(.bordered)
                }

            case .restricted:
                Text("\(permission.displayName) access is blocked by a restriction on this device, such as Screen Time or a device-management profile. It cannot be changed in PromptCam.")
                    .font(.footnote)
                    .foregroundStyle(Theme.Palette.warning)

            case .authorized:
                EmptyView()
            }
        }
    }

    // MARK: - Start

    private var startSection: some View {
        Section {
            Button {
                onStart(options)
            } label: {
                Label("Start interview", systemImage: "video.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Palette.recording)
            .disabled(!canStart)
        } footer: {
            if !deck.isRecordable {
                Text("Add a question to this deck before recording.")
            } else if permissionSnapshot?.canRecord == false {
                Text("Grant camera and microphone access to start.")
            }
        }
    }

    private var canStart: Bool {
        deck.isRecordable && (permissionSnapshot?.canRecord ?? false)
    }

    // MARK: - Helpers

    private func status(for permission: CapturePermission, in snapshot: PermissionSnapshot) -> PermissionStatus {
        permission == .camera ? snapshot.camera : snapshot.microphone
    }

    private func refreshPermissions() async {
        permissionSnapshot = await permissions.snapshot()
    }

    private func request(_ permission: CapturePermission) async {
        isRequesting = true
        await permissions.request(permission)
        await refreshPermissions()
        isRequesting = false
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
