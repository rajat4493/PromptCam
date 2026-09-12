import SwiftUI
import PromptCamCore

/// What the interviewee sees.
///
/// STATICALLY_REVIEWED — REQUIRES_MAC, then REQUIRES_PHYSICAL_DUO for the
/// readability criterion.
///
/// ## Design constraints, and why
///
///  - **Rendered only from `SubjectSnapshot`.** That type cannot carry upcoming
///    questions, the deck name, notes or controls, so director-only information
///    cannot appear here even by mistake.
///  - **Readable at 1–2 m.** Near-black background, pure white text, the
///    largest built-in type style, and `minimumScaleFactor` so a long question
///    shrinks rather than truncating. Nothing decorative competes with the text.
///  - **Non-interactive.** The supplied guidance describes the camera scene
///    accessory as supplementary, non-interactive content. There is deliberately
///    not a single tappable element in this view, and that is also the right
///    product decision: the interviewee must not be able to change anything.
///  - **No live preview.** `options.showsLivePreview` is stripped upstream
///    unless a feature flag marks the capability verified. Rather than faking a
///    preview, this view shows an honest placeholder only when the option is
///    genuinely on.
struct SubjectPromptView: View {
    let snapshot: SubjectSnapshot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.Palette.subjectCanvas.ignoresSafeArea()

            content
                // Interactive foreground content stays inside the safe area.
                // Only the background above extends past it.
                .padding(.horizontal, Theme.Space.section)
                .padding(.vertical, Theme.Space.loose)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The subject surface is always dark, whatever the system appearance.
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        if let remaining = snapshot.countdownRemaining, snapshot.options.showsCountdown {
            countdown(remaining: remaining)
        } else if snapshot.hasPresentableContent {
            question
        } else {
            waiting
        }
    }

    // MARK: - Countdown

    private func countdown(remaining: Int) -> some View {
        VStack(spacing: Theme.Space.loose) {
            Text(remaining == 0 ? "Go" : "\(remaining)")
                .font(Theme.TypeScale.subjectCountdown)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.subjectText)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                // Counts down out loud for a subject using VoiceOver.
                .accessibilityLabel(remaining == 0 ? "Recording now" : "Starting in \(remaining)")

            Text("Get ready")
                .font(Theme.TypeScale.subjectMeta)
                .foregroundStyle(Theme.Palette.subjectText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Question

    private var question: some View {
        VStack(alignment: .leading, spacing: Theme.Space.loose) {
            header

            if snapshot.options.showsQuestion, let text = snapshot.questionText {
                Text(text)
                    .font(Theme.TypeScale.subjectQuestion)
                    .foregroundStyle(Theme.Palette.subjectText)
                    // A long question shrinks rather than truncating: a cut-off
                    // question is worse than a slightly smaller one.
                    .minimumScaleFactor(0.5)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // A subtle cross-fade marks the change without animating
                    // motion, and is suppressed under Reduce Motion.
                    .id(snapshot.questionRevision)
                    .transition(reduceMotion ? .identity : .opacity)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.25),
                        value: snapshot.questionRevision
                    )
            }

            Spacer(minLength: 0)

            if snapshot.options.showsSubjectInstruction {
                Text("Look at the camera and answer in your own words.")
                    .font(Theme.TypeScale.subjectMeta)
                    .foregroundStyle(Theme.Palette.subjectText.opacity(0.6))
            }

            if snapshot.options.showsLivePreview {
                livePreviewPlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Space.comfortable) {
            if let number = snapshot.questionNumber, snapshot.questionCount > 0 {
                Text("Question \(number) of \(snapshot.questionCount)")
                    .font(Theme.TypeScale.subjectMeta)
                    .foregroundStyle(Theme.Palette.subjectText.opacity(0.55))
            }

            Spacer(minLength: 0)

            if snapshot.options.showsRecordingStatus, snapshot.isRecording {
                RecordingStatusBadge(state: .recording, isProminent: true)
            }
        }
    }

    /// Shown only when live preview is genuinely enabled, which requires the
    /// capability to have been verified on hardware.
    ///
    /// This is **not** a fake preview. It says plainly that the preview is not
    /// available, so it can never be mistaken for a working camera feed.
    private var livePreviewPlaceholder: some View {
        HStack(spacing: Theme.Space.regular) {
            Image(systemName: "video.slash")
                .font(.title2)
            Text("Preview unavailable")
                .font(Theme.TypeScale.subjectMeta)
        }
        .foregroundStyle(Theme.Palette.subjectText.opacity(0.5))
        .padding(Theme.Space.comfortable)
        .frame(maxWidth: .infinity)
        .background(Theme.Palette.surface, in: .rect(cornerRadius: Theme.Radius.panel))
    }

    // MARK: - Waiting

    /// Shown when there is nothing meaningful to display.
    ///
    /// Never an empty black screen: an interviewee looking at a blank panel
    /// assumes the app is broken.
    private var waiting: some View {
        VStack(spacing: Theme.Space.comfortable) {
            Image(systemName: "text.bubble")
                .font(.system(size: 56))
                .foregroundStyle(Theme.Palette.subjectText.opacity(0.35))
            Text("Ready when you are")
                .font(Theme.TypeScale.subjectQuestion)
                .foregroundStyle(Theme.Palette.subjectText.opacity(0.65))
                .minimumScaleFactor(0.5)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
#Preview("Question") {
    SubjectPromptView(
        snapshot: SubjectSnapshot(
            questionText: "What was going wrong before you found us?",
            questionNumber: 2,
            questionCount: 6,
            countdownRemaining: nil,
            isRecording: true,
            questionRevision: 1,
            options: .default
        )
    )
}

#Preview("Countdown") {
    SubjectPromptView(
        snapshot: SubjectSnapshot(
            questionText: "What was going wrong before you found us?",
            questionNumber: 2,
            questionCount: 6,
            countdownRemaining: 3,
            isRecording: false,
            questionRevision: 1,
            options: .default
        )
    )
}

#Preview("Waiting") {
    SubjectPromptView(snapshot: .empty)
}
#endif
