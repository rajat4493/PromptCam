import AVFoundation
import SwiftUI
import UIKit
import PromptCamCore

/// The operator's console.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC.
///
/// ## Adaptive layout, as required
///
///  - Uses `horizontalSizeClass` / `verticalSizeClass` rather than device
///    checks, so an open inner display reporting regular size classes gets the
///    side-by-side layout automatically, and a compact outer display or an
///    ordinary iPhone gets the stacked one.
///  - Reads `reservedRegions` through `ReservedRegionReader` and places the
///    control cluster in the largest region-free band, so the record button
///    never straddles a hinge.
///  - Uses `bounds.inset(by: safeAreaInsets)` semantics via SwiftUI's own safe
///    area handling; no inset is ever assumed to be symmetric.
///  - Never references `UIScreen.main`.
struct DirectorSessionView: View {
    @State private var model: DirectorSessionModel
    /// The capture session to preview. `nil` when running without a camera.
    let previewSession: AVCaptureSession?
    let onClose: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.openURL) private var openURL

    init(
        model: DirectorSessionModel,
        previewSession: AVCaptureSession?,
        onClose: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.previewSession = previewSession
        self.onClose = onClose
    }

    /// Side by side only when there is genuinely room in both axes.
    private var prefersSideBySide: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

    var body: some View {
        GeometryReader { proxy in
            let reserved = ReservedRegionReader.regions(from: proxy)

            ZStack {
                Theme.Palette.canvas.ignoresSafeArea()

                DirectorArrangement(prefersSideBySide: prefersSideBySide) {
                    viewfinder
                } secondary: {
                    console(reserved: reserved, bounds: proxy.frame(in: .local))
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await model.begin() }
        // Swipe-to-dismiss is disabled while a take is live, so a stray gesture
        // cannot end an interview.
        .interactiveDismissDisabled(model.blocksDismissal)
        .promptCamHingeObservation(
            isEnabled: model.engine.flags.hingeObservationEnabled,
            onChange: { model.foldPositionChanged($0) }
        )
        // Declares the subject-facing surface. Safe to attach unconditionally:
        // without the Duo build flag this resolves to a no-op that reports
        // "unavailable" and renders nothing anywhere.
        .promptCamSubjectAccessory(
            isEnabled: Binding(
                get: { model.isSubjectAccessoryEnabled },
                set: { model.isSubjectAccessoryEnabled = $0 }
            ),
            availabilityChanged: { model.subjectAccessoryAvailabilityChanged($0) },
            presentationChanged: { model.subjectAccessoryPresentationChanged($0) }
        ) {
            SubjectPromptView(snapshot: model.subjectSnapshot)
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(
                get: { model.alert != nil },
                set: { if !$0 { model.dismissAlert() } }
            ),
            presenting: model.alert
        ) { alert in
            if alert.offersSettings {
                Button("Open Settings") { openSettings() }
            }
            Button("OK", role: .cancel) { model.dismissAlert() }
        } message: { alert in
            Text(alert.message)
        }
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        ZStack(alignment: .top) {
            if let previewSession {
                CameraPreviewView(session: previewSession)
                    .ignoresSafeArea()
            } else {
                // Honest placeholder. The Simulator has no camera, and saying so
                // is better than a black rectangle the tester has to interpret.
                ZStack {
                    Theme.Palette.canvas
                    VStack(spacing: Theme.Space.regular) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 44))
                        Text("No camera available")
                            .font(Theme.TypeScale.controlLabel)
                    }
                    .foregroundStyle(Theme.Palette.textTertiary)
                }
                .ignoresSafeArea()
            }

            statusOverlay
                .padding(Theme.Space.comfortable)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusOverlay: some View {
        HStack(alignment: .top, spacing: Theme.Space.regular) {
            RecordingStatusBadge(state: model.state)

            if model.state.isCapturing || model.state == .finishing {
                Text(model.formattedElapsed)
                    .font(Theme.TypeScale.timer)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .padding(.horizontal, Theme.Space.regular)
                    .padding(.vertical, Theme.Space.snug)
                    .background(Theme.Palette.surfaceStrong, in: .rect(cornerRadius: Theme.Radius.pill))
                    .accessibilityLabel("Recording time")
                    .accessibilityValue(model.formattedElapsed)
            }

            Spacer(minLength: 0)

            AudioLevelMeter(level: model.audioLevel, isActive: model.state.isCapturing)
                .padding(.horizontal, Theme.Space.regular)
                .padding(.vertical, Theme.Space.snug)
                .background(Theme.Palette.surfaceStrong, in: .rect(cornerRadius: Theme.Radius.pill))

            closeButton
        }
    }

    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .frame(width: Theme.HitTarget.minimum, height: Theme.HitTarget.minimum)
                .background(Theme.Palette.surfaceStrong, in: .circle)
        }
        .foregroundStyle(Theme.Palette.textPrimary)
        // Cannot leave mid-take by accident. Stop first.
        .disabled(model.blocksDismissal)
        .opacity(model.blocksDismissal ? 0.3 : 1)
        .accessibilityLabel("Close interview")
        .accessibilityHint(model.blocksDismissal ? "Stop recording first" : "")
    }

    // MARK: - Console

    private func console(reserved: ReservedRegionSet, bounds: CGRect) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.regular) {
            if let warning = model.foldWarning {
                foldWarningBanner(warning)
            }

            questionPanel
            transportControls
        }
        .padding(Theme.Space.comfortable)
        // Keeps the controls out of hinge and occlusion regions. With no
        // reserved regions reported this is the full area, so the layout is
        // identical on an ordinary iPhone.
        .padding(.bottom, bottomInsetAvoidingReservedRegions(reserved: reserved, bounds: bounds))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(prefersSideBySide ? Theme.Palette.surface : Color.clear)
    }

    /// Extra bottom padding that lifts the controls clear of a reserved region
    /// crossing the lower part of the layout.
    private func bottomInsetAvoidingReservedRegions(
        reserved: ReservedRegionSet,
        bounds: CGRect
    ) -> CGFloat {
        guard !reserved.isEmpty else { return 0 }
        let safeBand = reserved.largestSafeBand(in: bounds)
        // If the safe band ends above the layout's bottom edge, pad by the gap.
        return max(0, bounds.maxY - safeBand.maxY)
    }

    private func foldWarningBanner(_ text: String) -> some View {
        HStack(spacing: Theme.Space.snug) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text).font(Theme.TypeScale.controlLabel)
        }
        .foregroundStyle(Theme.Palette.warning)
        .padding(Theme.Space.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: .rect(cornerRadius: Theme.Radius.control))
    }

    private var questionPanel: some View {
        DirectorPanel {
            VStack(alignment: .leading, spacing: Theme.Space.snug) {
                HStack {
                    Text(model.questionPosition)
                        .font(Theme.TypeScale.directorLabel)
                        .foregroundStyle(Theme.Palette.textSecondary)

                    Spacer(minLength: 0)

                    if model.showsSubjectControls {
                        subjectDisplayToggle
                    }
                }

                Text(model.currentQuestion ?? "No question selected")
                    .font(Theme.TypeScale.directorQuestion)
                    .foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Director-only. Never reaches the subject surface, because
                // `SubjectSnapshot` has no field that could carry it.
                if let next = model.nextQuestion {
                    Label {
                        Text(next).lineLimit(1)
                    } icon: {
                        Image(systemName: "arrow.turn.down.right")
                    }
                    .font(Theme.TypeScale.controlLabel)
                    .foregroundStyle(Theme.Palette.textTertiary)
                }
            }
        }
    }

    /// Shown only when the system reports a subject surface is available.
    /// Hidden entirely otherwise — never shown disabled, never an empty panel.
    private var subjectDisplayToggle: some View {
        Toggle(isOn: Binding(
            get: { model.isSubjectAccessoryEnabled },
            set: { model.isSubjectAccessoryEnabled = $0 }
        )) {
            Label("Subject screen", systemImage: "rectangle.on.rectangle")
                .font(Theme.TypeScale.controlLabel)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .tint(Theme.Palette.ready)
        .accessibilityHint("Shows the current question on the subject-facing display")
    }

    private var transportControls: some View {
        // A grid rather than a fixed row, so the controls wrap instead of
        // shrinking below the minimum hit target on a narrow or folded layout.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Space.regular) { controlCluster }
            VStack(spacing: Theme.Space.regular) {
                HStack(spacing: Theme.Space.regular) { questionNavigationButtons }
                HStack(spacing: Theme.Space.regular) { recordAndMarkerButtons }
            }
        }
    }

    @ViewBuilder
    private var controlCluster: some View {
        questionNavigationButtons
        recordAndMarkerButtons
    }

    @ViewBuilder
    private var questionNavigationButtons: some View {
        Button {
            model.previousQuestionTapped()
        } label: {
            Image(systemName: "chevron.left")
                .frame(width: Theme.HitTarget.minimum, height: Theme.HitTarget.minimum)
        }
        .buttonStyle(.bordered)
        .disabled(!model.engine.canGoToPreviousQuestion)
        .accessibilityLabel("Previous question")

        Button {
            model.nextQuestionTapped()
        } label: {
            Image(systemName: "chevron.right")
                .frame(width: Theme.HitTarget.minimum, height: Theme.HitTarget.minimum)
        }
        .buttonStyle(.bordered)
        .disabled(!model.engine.canGoToNextQuestion)
        .accessibilityLabel("Next question")
    }

    @ViewBuilder
    private var recordAndMarkerButtons: some View {
        Spacer(minLength: 0)

        recordButton

        Button {
            model.addMarker()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "bookmark.fill")
                if model.markerCount > 0 {
                    Text("\(model.markerCount)")
                        .font(.caption2.monospacedDigit())
                }
            }
            .frame(width: Theme.HitTarget.minimum, height: Theme.HitTarget.minimum)
        }
        .buttonStyle(.bordered)
        .disabled(!model.canAddMarker)
        .accessibilityLabel("Add marker")
        .accessibilityValue("\(model.markerCount) markers")
    }

    @ViewBuilder
    private var recordButton: some View {
        if model.state.countdownRemaining != nil {
            Button(role: .destructive) {
                model.cancelCountdown()
            } label: {
                Text("Cancel")
                    .font(Theme.TypeScale.controlLabel)
                    .frame(width: Theme.HitTarget.record, height: Theme.HitTarget.record)
                    .background(Theme.Palette.countdown.opacity(0.25), in: .circle)
                    .overlay(Circle().stroke(Theme.Palette.countdown, lineWidth: 3))
            }
            .accessibilityLabel("Cancel countdown")
        } else if model.state.isCapturing {
            Button {
                model.tapStop()
            } label: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.Palette.textPrimary)
                    .frame(width: 28, height: 28)
                    .frame(width: Theme.HitTarget.record, height: Theme.HitTarget.record)
                    .background(Theme.Palette.recording, in: .circle)
            }
            .disabled(!model.canStopRecording)
            .accessibilityLabel("Stop recording")
        } else {
            Button {
                model.tapRecord()
            } label: {
                Circle()
                    .fill(Theme.Palette.recording)
                    .frame(width: 56, height: 56)
                    .frame(width: Theme.HitTarget.record, height: Theme.HitTarget.record)
                    .overlay(Circle().stroke(Theme.Palette.textPrimary.opacity(0.8), lineWidth: 3))
            }
            .disabled(!model.canStartRecording)
            .accessibilityLabel("Start recording")
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}
