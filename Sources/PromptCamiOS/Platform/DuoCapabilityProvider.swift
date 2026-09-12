import SwiftUI
import PromptCamCore

/// Builds a `DeviceCapabilities` description for the running device.
///
/// ## What this deliberately does NOT do
///
/// It never reads a model name, a marketing name, a `utsname` machine string or
/// a screen dimension. The supplied Apple guidance is explicit that iPhone Duo
/// must not be identified that way, and doing so would also break every future
/// device. Capability here means "did the platform hand us the API", nothing more.
///
/// Size classes, scene geometry, safe areas and reserved regions are consumed at
/// the point of layout (see `DuoReservedRegionLayout` and the director view),
/// not turned into a device guess here.
enum DuoCapabilityProvider {

    /// The capabilities this build can actually offer.
    static func current() -> DeviceCapabilities {
        #if PROMPTCAM_DUO
        // REQUIRES_MAC_VALIDATION
        // Confirm the real availability floor for the camera scene accessory,
        // reserved regions and hinge APIs. The supplied guidance says iPhone Duo
        // runs iOS 27 and that Xcode 27.1 / the iOS 27.1 SDK provide the
        // intended behaviour, but the exact @available annotation for each
        // symbol is unconfirmed. Do not widen this guard on a guess.
        if #available(iOS 27.0, *) {
            return DeviceCapabilities(
                supportsSubjectAccessory: true,
                reportsReservedRegions: true,
                reportsHingeState: true,
                supportsMultipleCaptureDirections: true
            )
        }
        return .ordinaryPhone
        #else
        // Baseline build: no Duo symbols are referenced at all, and the session
        // is told the subject surface is unsupported. This is what makes the
        // ordinary-iPhone fallback the honest default rather than a degraded
        // version of an unproven feature.
        return .ordinaryPhone
        #endif
    }
}
