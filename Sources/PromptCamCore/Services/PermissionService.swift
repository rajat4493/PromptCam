import Foundation

/// The state of a single capture permission.
///
/// Mirrors the meaningful cases of `AVAuthorizationStatus` without importing
/// AVFoundation, keeping `PromptCamCore` platform-independent.
public enum PermissionStatus: String, Equatable, Sendable, Codable {
    /// The user has not been asked yet.
    case notDetermined
    case authorized
    /// Refused by the user.
    case denied
    /// Blocked by Screen Time or device management. The user cannot grant it
    /// themselves, so the recovery copy must differ from `denied`.
    case restricted

    public var isAuthorized: Bool { self == .authorized }

    /// Whether sending the user to Settings could plausibly fix this.
    public var isFixableInSettings: Bool { self == .denied }
}

/// Which capture permission is being discussed.
public enum CapturePermission: String, Sendable, CaseIterable {
    case camera
    case microphone

    public var displayName: String {
        switch self {
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        }
    }

    /// Why PromptCam needs it, in the user's terms. Shown *before* the system
    /// prompt so the request is not a surprise.
    public var rationale: String {
        switch self {
        case .camera:
            return "PromptCam uses the camera to record your interview. Video stays on this device."
        case .microphone:
            return "PromptCam uses the microphone to record what your subject says."
        }
    }
}

/// Reads and requests camera and microphone permission.
///
/// Injected so denial, restriction and the not-determined path can all be
/// tested without touching the real privacy system.
public protocol PermissionService: Sendable {
    func status(for permission: CapturePermission) async -> PermissionStatus
    /// Prompts the user. Returns the status *after* the prompt resolves.
    @discardableResult
    func request(_ permission: CapturePermission) async -> PermissionStatus
}

/// The combined readiness of both permissions PromptCam needs.
public struct PermissionSnapshot: Equatable, Sendable {
    public let camera: PermissionStatus
    public let microphone: PermissionStatus

    public init(camera: PermissionStatus, microphone: PermissionStatus) {
        self.camera = camera
        self.microphone = microphone
    }

    /// Both granted — the only state in which recording may be attempted.
    public var canRecord: Bool { camera.isAuthorized && microphone.isAuthorized }

    /// Permissions still to be resolved, camera first because it is the more
    /// visible blocker.
    public var blocking: [CapturePermission] {
        var result: [CapturePermission] = []
        if !camera.isAuthorized { result.append(.camera) }
        if !microphone.isAuthorized { result.append(.microphone) }
        return result
    }

    /// The failure a session should report if asked to record in this state.
    public var blockingFailure: RecordingFailure? {
        if !camera.isAuthorized { return .cameraPermissionDenied }
        if !microphone.isAuthorized { return .microphonePermissionDenied }
        return nil
    }

    public static let bothAuthorized = PermissionSnapshot(camera: .authorized, microphone: .authorized)
}
