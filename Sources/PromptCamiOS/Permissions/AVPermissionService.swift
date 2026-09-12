import AVFoundation
import PromptCamCore

/// The real permission service.
///
/// STATICALLY_REVIEWED — long-established AVFoundation API, never compiled.
/// REQUIRES_MAC.
struct AVPermissionService: PermissionService {

    func status(for permission: CapturePermission) async -> PermissionStatus {
        Self.map(AVCaptureDevice.authorizationStatus(for: Self.mediaType(for: permission)))
    }

    @discardableResult
    func request(_ permission: CapturePermission) async -> PermissionStatus {
        let mediaType = Self.mediaType(for: permission)
        let granted = await AVCaptureDevice.requestAccess(for: mediaType)
        // Re-read rather than inferring from the boolean: a restricted status
        // also returns false, and it needs different recovery copy.
        _ = granted
        return Self.map(AVCaptureDevice.authorizationStatus(for: mediaType))
    }

    func snapshot() async -> PermissionSnapshot {
        PermissionSnapshot(
            camera: await status(for: .camera),
            microphone: await status(for: .microphone)
        )
    }

    private static func mediaType(for permission: CapturePermission) -> AVMediaType {
        switch permission {
        case .camera: return .video
        case .microphone: return .audio
        }
    }

    private static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default:
            // An unrecognised status is treated as not granted. Guessing
            // "authorized" here would let the app attempt a capture it cannot
            // perform.
            return .denied
        }
    }
}
