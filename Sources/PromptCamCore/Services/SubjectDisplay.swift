import Foundation

/// What the subject-facing surface is allowed to show.
///
/// Enumerated rather than left to the view layer, because the privacy rule
/// (never show upcoming questions, notes or operator controls to the subject)
/// must be enforceable and testable.
public struct SubjectDisplayOptions: Equatable, Sendable, Codable {
    /// Show the current question in large type.
    public var showsQuestion: Bool
    /// Show the pre-roll countdown.
    public var showsCountdown: Bool
    /// Show whether recording is active.
    public var showsRecordingStatus: Bool
    /// Show a short standing instruction, e.g. "Look at the camera".
    public var showsSubjectInstruction: Bool
    /// Show a mirrored live camera preview.
    ///
    /// **Off by default and additionally gated by
    /// `FeatureFlags.subjectLivePreviewEnabled`.**
    ///
    /// Per the supplied Apple guidance, whether an independent live preview can
    /// be embedded in the outer accessory — and how it performs — is
    /// unverified for this project. Status: REQUIRES_MAC, then
    /// REQUIRES_PHYSICAL_DUO. V0 ships without it rather than faking it.
    public var showsLivePreview: Bool

    public init(
        showsQuestion: Bool = true,
        showsCountdown: Bool = true,
        showsRecordingStatus: Bool = true,
        showsSubjectInstruction: Bool = false,
        showsLivePreview: Bool = false
    ) {
        self.showsQuestion = showsQuestion
        self.showsCountdown = showsCountdown
        self.showsRecordingStatus = showsRecordingStatus
        self.showsSubjectInstruction = showsSubjectInstruction
        self.showsLivePreview = showsLivePreview
    }

    public static let `default` = SubjectDisplayOptions()

    /// The options actually honoured, after removing anything unsupported.
    ///
    /// Live preview is stripped whenever the capability is not verified, so an
    /// enabled-but-unsupported preview can never reach the view layer.
    public func resolved(livePreviewSupported: Bool) -> SubjectDisplayOptions {
        var copy = self
        if !livePreviewSupported { copy.showsLivePreview = false }
        return copy
    }
}

/// Why a subject-facing surface is or is not usable right now.
///
/// The supplied Apple guidance states that camera scene-accessory availability
/// requires the app to be full-screen on the inner display **and** to have an
/// active camera-capture session, and that the system controls availability and
/// may change it dynamically. Those conditions are represented here so the
/// director UI can explain the situation instead of silently showing nothing.
public enum SubjectDisplayAvailability: Equatable, Sendable {
    /// The platform does not provide a subject-facing surface at all
    /// (for example an ordinary iPhone running an older iOS).
    case unsupported
    /// Supported, but the system is not currently offering it.
    case unavailable
    /// The system is offering it, but the operator has not enabled it.
    case availableNotEnabled
    /// Enabled and content is on screen.
    case presented

    /// Whether any Duo-only affordance should appear in the director UI.
    ///
    /// When `false`, Duo-only controls must be hidden entirely — never shown
    /// disabled, and never shown as an empty secondary panel.
    public var shouldShowSubjectControls: Bool {
        switch self {
        case .unsupported, .unavailable: return false
        case .availableNotEnabled, .presented: return true
        }
    }

    public var isPresented: Bool { self == .presented }
}

/// Observes whether a subject-facing surface is available.
///
/// ## Why this is a protocol
///
/// The app must never inspect a device name, model identifier or fixed screen
/// dimension to decide whether it is on an iPhone Duo. Availability comes only
/// from the system's own callback. Putting it behind this protocol also means a
/// correction to the accessory API (see docs/APPLE_API_CORRECTIONS.md) changes
/// one adapter file rather than the session, the subject view or any test.
public protocol SubjectDisplayAvailabilityObserving: AnyObject, Sendable {
    var availability: SubjectDisplayAvailability { get }
}
