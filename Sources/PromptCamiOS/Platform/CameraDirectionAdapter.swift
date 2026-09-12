import AVFoundation
import PromptCamCore

/// Chooses capture devices and, on a foldable, reacts to direction changes.
///
/// ## PromptCam's intent, stated up front
///
/// PromptCam records the **interview subject using a rear camera** while the
/// operator works on the inner display and the subject reads prompts on the
/// outer display. The supplied guidance describes several new *front* camera
/// device types on iPhone Duo (outer ultrawide, inner under-display ultrawide,
/// and a virtual front camera that switches between them). Those exist to
/// support selfie-style capture and are **not** what PromptCam's primary
/// workflow wants.
///
/// This adapter therefore never selects a front camera unless the operator has
/// explicitly asked for `.front`. A new front-camera API is not a reason to
/// start using the front camera.
///
/// ## Status: REQUIRES_MAC, then REQUIRES_PHYSICAL_DUO
enum CameraDirectionAdapter {

    /// Finds the best capture device for `direction`.
    ///
    /// Uses `AVCaptureDevice.DiscoverySession` and takes what the device
    /// actually reports, rather than hardcoding a lens, so a device with an
    /// unfamiliar camera layout still works.
    static func device(for direction: CaptureDirection) -> AVCaptureDevice? {
        let position: AVCaptureDevice.Position = direction == .rear ? .back : .front

        // Ordered by preference. Every type here is long-established; the
        // Duo-specific types are deliberately NOT in this list, because they
        // are all front-facing. See `duoFrontCameraDeviceTypes` below.
        let preferredTypes: [AVCaptureDevice.DeviceType] = [
            .builtInDualWideCamera,
            .builtInWideAngleCamera,
            .builtInUltraWideCamera
        ]

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: preferredTypes,
            mediaType: .video,
            position: position
        )

        // Prefer the earliest type in `preferredTypes` that the device offers.
        for type in preferredTypes {
            if let match = discovery.devices.first(where: { $0.deviceType == type }) {
                return match
            }
        }
        return discovery.devices.first
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    /// Maps an `AVCaptureDevice.Position` back into PromptCam's own enum.
    static func direction(for position: AVCaptureDevice.Position) -> CaptureDirection {
        position == .front ? .front : .rear
    }

    #if PROMPTCAM_DUO
    /// The Duo front-camera device types from the supplied guidance.
    ///
    /// REQUIRES_MAC_VALIDATION — confirm that `.builtInOuterUltraWideCamera`
    /// and `.builtInInnerUltraWideCamera` exist with these exact spellings and
    /// what their availability annotations are. `.builtInDualWideCamera` is
    /// long-established and is already used above.
    ///
    /// Listed but not used by the default rear-camera workflow. They become
    /// relevant only if PromptCam later offers a front-facing mode.
    static var duoFrontCameraDeviceTypes: [AVCaptureDevice.DeviceType] {
        [
            .builtInOuterUltraWideCamera,
            .builtInInnerUltraWideCamera,
            .builtInDualWideCamera
        ]
    }
    #endif
}

/// Coordinates camera changes when the device's fold direction changes.
///
/// ## Status: REQUIRES_MAC, then REQUIRES_PHYSICAL_DUO
///
/// The supplied guidance describes `AVCaptureDeviceDirectionCoordinator`, built
/// with a view, a list of device types and a change handler that receives a map
/// of devices. PromptCam's rear-camera workflow does not depend on it: the rear
/// camera does not change identity when the device folds.
///
/// It is wired here, behind the flag, for one honest reason — if a physical Duo
/// turns out to swap the active device when the operator folds mid-interview,
/// this is where PromptCam must react, and having the seam already cut is worth
/// more than pretending the question does not exist.
///
/// REQUIRES_MAC_VALIDATION — confirm the type name, the initialiser labels
/// (`view:deviceTypes:changeHandler:`), the actual type of the value passed to
/// the handler (the guidance calls it a "map" without naming the type), the
/// actor isolation of the handler, and the availability annotation. **Do not
/// copy the supplied snippet into the app without confirming all five.**
final class CaptureDirectionCoordinator {

    /// Called when the platform reports that the active camera should change.
    private let onDirectionChange: (CaptureDirection) -> Void

    #if PROMPTCAM_DUO
    private var coordinator: AnyObject?
    #endif

    init(onDirectionChange: @escaping (CaptureDirection) -> Void) {
        self.onDirectionChange = onDirectionChange
    }

    /// Begins observing, if the platform supports it.
    ///
    /// Returns whether observation actually started, so the caller can record
    /// the truth in the verification ledger rather than assuming.
    @discardableResult
    func startObserving() -> Bool {
        #if PROMPTCAM_DUO
        // REQUIRES_MAC_VALIDATION — intentionally NOT implemented against the
        // supplied snippet.
        //
        // Writing `AVCaptureDeviceDirectionCoordinator(view:deviceTypes:changeHandler:)`
        // here would put an unconfirmed initialiser, an unconfirmed handler
        // parameter type and an unconfirmed isolation context into the app's
        // startup path. If any of the three is wrong the app fails to build,
        // and if the handler type is wrong it could silently never fire.
        //
        // PromptCam's rear-camera workflow does not need it, so the honest
        // position is: the seam exists, the work is documented, and the
        // capability is reported as unavailable until a Mac confirms it.
        //
        // To complete on a Mac:
        //   1. Confirm the five unknowns listed in this type's documentation.
        //   2. Build the coordinator with
        //      `CameraDirectionAdapter.duoFrontCameraDeviceTypes`.
        //   3. In the change handler, map the reported device to a
        //      `CaptureDirection` and call `onDirectionChange`.
        //   4. Retain it in `coordinator`.
        //   5. Record the real signature in docs/APPLE_API_CORRECTIONS.md and
        //      move UAT case 12 off REQUIRES_MAC.
        return false
        #else
        return false
        #endif
    }

    func stopObserving() {
        #if PROMPTCAM_DUO
        coordinator = nil
        #endif
    }
}
