import Foundation

/// Switches for capabilities that are **not yet verified**.
///
/// The rule this enforces: a capability stays off until
/// `docs/VERIFICATION_LEDGER.md` records it as verified at the required tier.
/// That is what stops PromptCam shipping a feature that only appears to work.
public struct FeatureFlags: Equatable, Sendable {

    /// Show a mirrored live camera preview on the subject surface.
    ///
    /// **Default: false.** Whether an independent live preview can be embedded
    /// in the camera scene accessory, and how it performs, is unverified for
    /// this project. Ledger status: REQUIRES_MAC, then REQUIRES_PHYSICAL_DUO.
    ///
    /// Enable only after UAT case 16 passes on real hardware.
    public var subjectLivePreviewEnabled: Bool

    /// Play a subtle cue on the subject surface when the question changes.
    public var subjectQuestionChangeCue: Bool

    /// Observe hinge state.
    ///
    /// **Default: false.** PromptCam does not need hinge angle as a primary
    /// interaction; the supplied Apple guidance recommends reserved-region and
    /// arrangement APIs for layout instead. Kept as a flag so the observer can
    /// be switched on for diagnostics during Mac validation without shipping it.
    public var hingeObservationEnabled: Bool

    public init(
        subjectLivePreviewEnabled: Bool = false,
        subjectQuestionChangeCue: Bool = true,
        hingeObservationEnabled: Bool = false
    ) {
        self.subjectLivePreviewEnabled = subjectLivePreviewEnabled
        self.subjectQuestionChangeCue = subjectQuestionChangeCue
        self.hingeObservationEnabled = hingeObservationEnabled
    }

    /// The shipping configuration.
    public static let `default` = FeatureFlags()

    /// Configuration for tests that exercise the preview path.
    public static let livePreviewEnabledForTesting = FeatureFlags(subjectLivePreviewEnabled: true)
}
