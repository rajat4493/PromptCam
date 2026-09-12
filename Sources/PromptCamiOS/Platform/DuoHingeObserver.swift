import SwiftUI
import PromptCamCore

/// High-level fold position, expressed in PromptCam's own terms.
///
/// Kept as a local enum so no part of the app outside this file depends on the
/// supplied hinge types.
enum FoldPosition: Equatable, Sendable {
    /// The platform does not report hinge state, or reporting is switched off.
    case unknown
    case closed
    /// Partly folded, with the hinge angle in degrees.
    case partiallyOpen(degrees: Double)
    case fullyOpen

    /// Whether the operator's controls are likely to be awkward to reach.
    ///
    /// The only thing PromptCam actually does with hinge state in V0: warn
    /// rather than re-lay-out, because reserved regions and standard adaptive
    /// containers are the supported way to handle layout.
    var mayObscureControls: Bool {
        if case .partiallyOpen = self { return true }
        return false
    }
}

/// Observes fold position, when the platform offers it.
///
/// ## Status: REQUIRES_MAC, then REQUIRES_PHYSICAL_DUO
///
/// PromptCam does **not** need hinge angle as a primary interaction, and the
/// supplied guidance recommends reserved-region and arrangement APIs for layout
/// instead. This observer exists only so that:
///
///  - a partially-folded device can warn the operator before a take rather than
///    during one, and
///  - hinge data is available for diagnostics during Mac and device validation.
///
/// It is additionally gated by `FeatureFlags.hingeObservationEnabled`, which is
/// off by default, so nothing in the shipping app depends on it.
///
/// REQUIRES_MAC_VALIDATION — confirm the modifier name `onHingeChange`, the
/// two-argument `(previousContext, currentContext)` closure shape, that
/// `currentContext.hinge` is optional, and the spelling and type of
/// `hinge.status` and `hinge.angle`. UIKit's `UIHingeInteraction` is the
/// alternative if the SwiftUI modifier does not resolve.
struct HingeObservationModifier: ViewModifier {
    let isEnabled: Bool
    let onChange: (FoldPosition) -> Void

    func body(content: Content) -> some View {
        #if PROMPTCAM_DUO
        if isEnabled {
            // REQUIRES_MAC_VALIDATION — supplied API surface, never compiled.
            content.onHingeChange { _, currentContext in
                guard let hinge = currentContext.hinge else {
                    onChange(.unknown)
                    return
                }
                switch hinge.status {
                case .closed:
                    onChange(.closed)
                case .partiallyOpen:
                    // REQUIRES_MAC_VALIDATION — `hinge.angle` is expected to be
                    // a SwiftUI `Angle`, not a number: Apple's own example
                    // passes it straight to a function taking `Angle`, and
                    // `Double(_:)` has no initialiser for it. `.degrees` is the
                    // accessor to confirm. If it turns out to be a numeric type
                    // after all, use it directly and delete this conversion.
                    onChange(.partiallyOpen(degrees: hinge.angle.degrees))
                default:
                    // `.fullyOpen` and any future case: treat as fully open
                    // rather than guessing at an unknown case's meaning.
                    onChange(.fullyOpen)
                }
            }
        } else {
            content
        }
        #else
        // Baseline build: the platform reports nothing, and the app is told so
        // explicitly rather than assuming a pose.
        content.task { onChange(.unknown) }
        #endif
    }
}

extension View {
    func promptCamHingeObservation(
        isEnabled: Bool,
        onChange: @escaping (FoldPosition) -> Void
    ) -> some View {
        modifier(HingeObservationModifier(isEnabled: isEnabled, onChange: onChange))
    }
}
