import SwiftUI
import PromptCamCore

/// PromptCam's small internal design system.
///
/// Deliberately small: spacing, type, colour and the recording-state palette.
/// Anything that a standard SwiftUI component already does well is left to the
/// standard component.
enum Theme {

    // MARK: - Spacing

    /// A 4-point base scale. Named by role, not by number, so a change of mind
    /// about density is one edit.
    enum Space {
        static let hairline: CGFloat = 2
        static let tight: CGFloat = 4
        static let snug: CGFloat = 8
        static let regular: CGFloat = 12
        static let comfortable: CGFloat = 16
        static let loose: CGFloat = 24
        static let section: CGFloat = 32
    }

    enum Radius {
        static let control: CGFloat = 12
        static let panel: CGFloat = 16
        static let pill: CGFloat = 999
    }

    /// Minimum hit target. Matches Apple's 44-point guidance; the record button
    /// is deliberately larger because it is used under pressure.
    enum HitTarget {
        static let minimum: CGFloat = 44
        static let record: CGFloat = 72
    }

    // MARK: - Colour

    /// The camera interface is dark regardless of system appearance: a light
    /// interface next to a viewfinder is hard to read and reflects on the
    /// subject's face.
    enum Palette {
        static let canvas = Color.black
        /// Panels that sit over the viewfinder.
        static let surface = Color.white.opacity(0.08)
        static let surfaceStrong = Color.white.opacity(0.14)
        static let separator = Color.white.opacity(0.16)

        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.7)
        static let textTertiary = Color.white.opacity(0.45)

        /// Recording red. Also used for the hardware-style status dot.
        static let recording = Color(red: 0.93, green: 0.21, blue: 0.21)
        static let countdown = Color(red: 1.0, green: 0.76, blue: 0.20)
        static let ready = Color(red: 0.28, green: 0.79, blue: 0.45)
        static let warning = Color(red: 1.0, green: 0.66, blue: 0.16)
        static let failure = Color(red: 1.0, green: 0.35, blue: 0.30)

        /// The subject surface is near-black with pure white text: the highest
        /// contrast available, because it must read at 1–2 m.
        static let subjectCanvas = Color.black
        static let subjectText = Color.white
    }

    // MARK: - Typography

    enum TypeScale {
        /// Director-facing question text. Prominent but not shouting.
        static let directorQuestion = Font.system(.title3, design: .rounded, weight: .semibold)
        static let directorLabel = Font.system(.caption, design: .rounded, weight: .medium)
        static let timer = Font.system(.title3, design: .monospaced, weight: .semibold)
        static let controlLabel = Font.system(.footnote, design: .rounded, weight: .medium)

        /// Subject-facing question text.
        ///
        /// Uses a **relative** text style so Dynamic Type and the accessibility
        /// sizes still apply — a hardcoded point size would be unreadable for
        /// anyone who needs larger text. `.largeTitle` is the largest built-in
        /// style, scaled up via `minimumScaleFactor` in the view when a long
        /// question needs to fit.
        static let subjectQuestion = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let subjectMeta = Font.system(.title3, design: .rounded, weight: .semibold)
        static let subjectCountdown = Font.system(size: 140, weight: .bold, design: .rounded)
    }

    // MARK: - Recording state presentation

    /// One place that decides how each recording state looks and reads, so the
    /// director surface and the subject surface can never describe the same
    /// state differently.
    struct StatePresentation {
        let label: String
        let color: Color
        let symbolName: String
        /// Whether the indicator should pulse. Suppressed under Reduce Motion
        /// by the view that renders it.
        let pulses: Bool
    }

    static func presentation(for state: RecordingState) -> StatePresentation {
        switch state {
        case .idle:
            return StatePresentation(label: "Not ready", color: Palette.textTertiary,
                                     symbolName: "circle.dashed", pulses: false)
        case .preparing:
            return StatePresentation(label: "Ready", color: Palette.ready,
                                     symbolName: "checkmark.circle.fill", pulses: false)
        case .countdown(let remaining):
            return StatePresentation(label: "Starting in \(remaining)", color: Palette.countdown,
                                     symbolName: "timer", pulses: false)
        case .recording:
            return StatePresentation(label: "Recording", color: Palette.recording,
                                     symbolName: "record.circle.fill", pulses: true)
        case .finishing:
            return StatePresentation(label: "Saving", color: Palette.countdown,
                                     symbolName: "arrow.down.circle", pulses: false)
        case .saved:
            return StatePresentation(label: "Saved", color: Palette.ready,
                                     symbolName: "checkmark.circle.fill", pulses: false)
        case .failed:
            return StatePresentation(label: "Failed", color: Palette.failure,
                                     symbolName: "exclamationmark.triangle.fill", pulses: false)
        case .interrupted:
            return StatePresentation(label: "Interrupted", color: Palette.warning,
                                     symbolName: "exclamationmark.circle.fill", pulses: false)
        }
    }
}

// MARK: - Shared building blocks

/// A panel that sits over the viewfinder.
struct DirectorPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(Theme.Space.regular)
            .background(Theme.Palette.surface, in: .rect(cornerRadius: Theme.Radius.panel))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.panel)
                    .stroke(Theme.Palette.separator, lineWidth: 1)
            )
    }
}

/// The recording-state pill, shared by the director and subject surfaces.
struct RecordingStatusBadge: View {
    let state: RecordingState
    /// Larger variant for the subject surface, which is read from further away.
    var isProminent: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        let presentation = Theme.presentation(for: state)

        HStack(spacing: Theme.Space.snug) {
            Circle()
                .fill(presentation.color)
                .frame(width: isProminent ? 20 : 10, height: isProminent ? 20 : 10)
                .opacity(shouldPulse(presentation) && isPulsing ? 0.35 : 1)
                .animation(
                    shouldPulse(presentation)
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )

            Text(presentation.label)
                .font(isProminent ? Theme.TypeScale.subjectMeta : Theme.TypeScale.directorLabel)
                .foregroundStyle(Theme.Palette.textPrimary)
        }
        .padding(.horizontal, isProminent ? Theme.Space.comfortable : Theme.Space.regular)
        .padding(.vertical, isProminent ? Theme.Space.regular : Theme.Space.snug)
        .background(Theme.Palette.surfaceStrong, in: .rect(cornerRadius: Theme.Radius.pill))
        .onAppear { isPulsing = shouldPulse(presentation) }
        .onChange(of: state) { _, newState in
            isPulsing = shouldPulse(Theme.presentation(for: newState))
        }
        // One combined announcement rather than two unlabelled elements.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.label)
    }

    private func shouldPulse(_ presentation: Theme.StatePresentation) -> Bool {
        presentation.pulses && !reduceMotion
    }
}
