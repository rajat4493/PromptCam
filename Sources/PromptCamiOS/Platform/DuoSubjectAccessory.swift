import SwiftUI
import PromptCamCore

/// Attaches the subject-facing surface to the director's view.
///
/// ## Status: REQUIRES_MAC, then REQUIRES_DUO_SIMULATOR, then REQUIRES_PHYSICAL_DUO
///
/// This is the single most important unverified boundary in PromptCam. Two
/// different API shapes are in play and only one of them has been seen in
/// published documentation:
///
/// **Supplied by the product owner** (used when `PROMPTCAM_DUO` is enabled) —
/// `CameraCaptureAccessory`, described as the camera-application scene
/// accessory, with availability constrained to: the app being full-screen on
/// the inner display, an active camera-capture session, and the system's own
/// decision, which can change at any time.
///
/// ```swift
/// CameraView(model: model)
///     .sceneAccessory {
///         CameraCaptureAccessory(isEnabled: $model.isEnabled) {
///             SubjectPromptView(model: model)
///         }
///         .onAvailabilityChange { newValue in model.isAvailable = newValue }
///     }
/// ```
///
/// **Independently found in Apple's published iOS 27.0 documentation** —
/// `ExternalNonInteractiveAccessory`, the same `sceneAccessory` /
/// `onAvailabilityChange` shape, but documented for external displays and
/// AirPlay rather than a foldable's outer display. It is recorded here as a
/// fallback because it is the one variant whose declaration has actually been
/// read, so if `CameraCaptureAccessory` does not resolve on the Mac it is the
/// obvious next thing to try.
///
/// REQUIRES_MAC_VALIDATION — confirm, in this order:
///   1. Does `CameraCaptureAccessory` exist, and in which module?
///   2. Is its initialiser `init(isEnabled: Binding<Bool>, content:)`?
///   3. Does it conform to the protocol `sceneAccessory(content:)` requires?
///   4. What is the real `@available` annotation?
///   5. Does availability in fact require an active capture session?
/// Record every answer in `docs/APPLE_API_CORRECTIONS.md`.
struct SubjectAccessoryModifier<AccessoryContent: View>: ViewModifier {

    /// Whether the operator has switched the subject surface on.
    @Binding var isEnabled: Bool

    /// Called whenever the system changes availability.
    ///
    /// The session must treat this as the *only* source of availability truth.
    /// Named `availabilityChanged` rather than `onAvailabilityChange` so it can
    /// never be mistaken for Apple's modifier of that name.
    let availabilityChanged: (Bool) -> Void

    /// Called when the accessory's content actually appears or disappears.
    let presentationChanged: (Bool) -> Void

    /// What the subject sees. Built by the caller from a `SubjectSnapshot`, so
    /// no director-only state can reach it.
    @ViewBuilder let accessoryContent: () -> AccessoryContent

    func body(content: Content) -> some View {
        #if PROMPTCAM_DUO
        // REQUIRES_MAC_VALIDATION — supplied API surface, never compiled.
        content
            .sceneAccessory {
                CameraCaptureAccessory(isEnabled: $isEnabled) {
                    accessoryContent()
                        .onAppear { presentationChanged(true) }
                        .onDisappear { presentationChanged(false) }
                }
                .onAvailabilityChange { newValue in
                    availabilityChanged(newValue)
                }
            }
        #else
        // Baseline build.
        //
        // This is a deliberate no-op, not a stand-in implementation. It does
        // NOT open a second window, mirror the screen, or render the subject
        // content anywhere — substituting a generic second window for the
        // camera accessory would misrepresent an unproven capability.
        //
        // It reports `false` once so the session settles into "no subject
        // surface" and the director UI hides its Duo-only controls cleanly.
        content
            .task {
                availabilityChanged(false)
                presentationChanged(false)
            }
        #endif
    }
}

extension View {
    /// Declares PromptCam's subject-facing accessory.
    ///
    /// Safe to call unconditionally: with `PROMPTCAM_DUO` off it resolves to the
    /// no-op above and the app behaves as an ordinary iPhone camera app.
    func promptCamSubjectAccessory<Content: View>(
        isEnabled: Binding<Bool>,
        availabilityChanged: @escaping (Bool) -> Void,
        presentationChanged: @escaping (Bool) -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(
            SubjectAccessoryModifier(
                isEnabled: isEnabled,
                availabilityChanged: availabilityChanged,
                presentationChanged: presentationChanged,
                accessoryContent: content
            )
        )
    }
}
