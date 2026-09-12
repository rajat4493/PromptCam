import Foundation

/// A platform-independent description of what the host device can do for
/// PromptCam.
///
/// This is deliberately a **description**, not a detection. Nothing in
/// `PromptCamCore` asks what device it is running on. The iOS layer builds one
/// of these from documented capability APIs (size classes, scene geometry,
/// reserved regions, scene-accessory availability) and hands it in.
///
/// Rules this type encodes:
///  - No model-name strings.
///  - No fixed screen dimensions.
///  - Absence of a capability is a first-class value, not a nil to be guessed at.
public struct DeviceCapabilities: Equatable, Sendable {

    /// Whether the platform build supports the camera scene accessory API at all.
    ///
    /// False on an older iOS, or when the SDK symbol is unavailable.
    public let supportsSubjectAccessory: Bool

    /// Whether the platform reports reserved regions (hinge, division,
    /// occlusion) that layout must avoid.
    public let reportsReservedRegions: Bool

    /// Whether the platform can report hinge state.
    public let reportsHingeState: Bool

    /// Whether more than one camera direction is selectable.
    public let supportsMultipleCaptureDirections: Bool

    public init(
        supportsSubjectAccessory: Bool,
        reportsReservedRegions: Bool,
        reportsHingeState: Bool,
        supportsMultipleCaptureDirections: Bool
    ) {
        self.supportsSubjectAccessory = supportsSubjectAccessory
        self.reportsReservedRegions = reportsReservedRegions
        self.reportsHingeState = reportsHingeState
        self.supportsMultipleCaptureDirections = supportsMultipleCaptureDirections
    }

    /// An ordinary iPhone with no second surface: the fallback baseline.
    ///
    /// PromptCam must be fully functional in exactly this configuration.
    public static let ordinaryPhone = DeviceCapabilities(
        supportsSubjectAccessory: false,
        reportsReservedRegions: false,
        reportsHingeState: false,
        supportsMultipleCaptureDirections: true
    )

    /// A device that offers everything. Used by tests, never by detection.
    public static let fullyCapable = DeviceCapabilities(
        supportsSubjectAccessory: true,
        reportsReservedRegions: true,
        reportsHingeState: true,
        supportsMultipleCaptureDirections: true
    )

    /// The availability a session should start from on this device.
    ///
    /// A device that cannot host the accessory reports `.unsupported`, which is
    /// what hides Duo-only controls cleanly rather than showing an empty panel.
    public var initialSubjectDisplayAvailability: SubjectDisplayAvailability {
        supportsSubjectAccessory ? .unavailable : .unsupported
    }
}
