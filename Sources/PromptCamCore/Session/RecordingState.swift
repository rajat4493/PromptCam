import Foundation

/// Why a recording could not be completed.
///
/// Modelled explicitly rather than as a generic `Error` so the UI can offer a
/// specific recovery path and tests can assert the exact cause.
public enum RecordingFailure: Equatable, Sendable {
    case cameraUnavailable(String)
    case microphoneUnavailable(String)
    case cameraPermissionDenied
    case microphonePermissionDenied
    /// Capture started but the pipeline failed mid-recording.
    case captureFailed(String)
    /// The file was captured but could not be moved into permanent storage.
    ///
    /// `preservedPath` is non-nil when a usable file still exists on disk.
    /// PromptCam never deletes a captured file because a later step failed.
    case saveFailed(reason: String, preservedPath: String?)
    case insufficientStorage

    /// Path of a recoverable media file that still exists despite the failure.
    public var preservedPath: String? {
        if case .saveFailed(_, let path) = self { return path }
        return nil
    }

    /// Copy the operator can act on. Deliberately blunt about what happened to
    /// their footage, because that is the only thing they care about.
    public var operatorMessage: String {
        switch self {
        case .cameraUnavailable(let detail):
            return "The camera could not start. \(detail)"
        case .microphoneUnavailable(let detail):
            return "The microphone could not start. \(detail)"
        case .cameraPermissionDenied:
            return "PromptCam needs camera access to record an interview."
        case .microphonePermissionDenied:
            return "PromptCam needs microphone access to record an interview."
        case .captureFailed(let detail):
            return "Recording stopped unexpectedly. \(detail)"
        case .saveFailed(let reason, let path):
            if path != nil {
                return "The interview was recorded but could not be filed. \(reason) The video file has been kept."
            }
            return "The interview could not be saved. \(reason)"
        case .insufficientStorage:
            return "There is not enough free space to record."
        }
    }
}

/// Why a recording was interrupted by something outside the app's control.
public enum InterruptionReason: Equatable, Sendable {
    /// A phone call, FaceTime, or another app took the audio session.
    case audioSessionLost
    /// The system interrupted the capture session — for example a hardware
    /// reconfiguration, or another app claiming the camera.
    case captureSessionInterrupted
    /// The app was backgrounded while recording.
    case backgrounded
    /// A thermal or resource condition.
    case resourcePressure

    public var isResumable: Bool {
        switch self {
        case .audioSessionLost, .captureSessionInterrupted, .backgrounded:
            return true
        case .resourcePressure:
            return false
        }
    }

    public var operatorMessage: String {
        switch self {
        case .audioSessionLost:
            return "Recording stopped because another app took the microphone (usually a phone call)."
        case .captureSessionInterrupted:
            return "Recording stopped because the camera was interrupted."
        case .backgrounded:
            return "Recording stopped because PromptCam went to the background."
        case .resourcePressure:
            return "Recording stopped because the device ran low on resources."
        }
    }
}

/// The complete lifecycle of one interview capture.
///
/// The single source of truth that the director surface and the subject
/// surface both render from — a value type with no reference to any view or
/// capture object, so the two surfaces cannot disagree.
public enum RecordingState: Equatable, Sendable {
    /// Nothing is happening. The only state from which a session may be torn down.
    case idle
    /// The capture pipeline is being configured, or is configured and ready.
    case preparing
    /// A cancellable countdown is running before capture begins.
    case countdown(remaining: Int)
    /// Capture is active and bytes are being written.
    case recording
    /// Stop requested; waiting for the operating system to finalise the file.
    case finishing
    /// The OS confirmed a complete file. **Only** reachable from `.finishing`
    /// via an explicit confirmation.
    case saved(fileName: String)
    /// Terminal failure with a specific cause.
    case failed(RecordingFailure)
    /// Capture stopped because of an external event.
    case interrupted(reason: InterruptionReason)

    /// True while the device is actually capturing to disk.
    public var isCapturing: Bool { self == .recording }

    /// True while a countdown or capture is in progress, so the operator must
    /// be protected from accidentally dismissing the screen.
    public var isBusy: Bool {
        switch self {
        case .preparing, .countdown, .recording, .finishing: return true
        case .idle, .saved, .failed, .interrupted: return false
        }
    }

    /// True once the session has come to rest and can be restarted.
    public var isTerminal: Bool {
        switch self {
        case .saved, .failed, .interrupted: return true
        default: return false
        }
    }

    /// Whether a complete, OS-confirmed file exists.
    ///
    /// The UI must use **only** this to decide whether to tell the operator
    /// their interview was saved.
    public var hasConfirmedSavedFile: Bool {
        if case .saved = self { return true }
        return false
    }

    public var savedFileName: String? {
        if case .saved(let name) = self { return name }
        return nil
    }

    /// Seconds left on the countdown, if one is running.
    public var countdownRemaining: Int? {
        if case .countdown(let remaining) = self { return remaining }
        return nil
    }
}

/// Everything that can be asked of a recording session.
///
/// Transitions are driven only by these events, so every state change has a
/// name and a test.
public enum RecordingEvent: Equatable, Sendable {
    case prepare
    /// Capture configured successfully and is ready to roll.
    case prepareSucceeded
    case startCountdown(seconds: Int)
    case countdownTick
    /// The operator cancelled the countdown before it reached zero.
    case cancelCountdown
    /// Begin writing to disk. Legal from `preparing`, or from a countdown that
    /// reached zero.
    case beginRecording
    case stop
    /// The OS confirmed a finalised file. The **only** route to `.saved`.
    case saveConfirmed(fileName: String)
    case saveFailed(RecordingFailure)
    case fail(RecordingFailure)
    case interrupt(InterruptionReason)
    /// Return a terminal session to `idle` so a new take can begin.
    case reset
}

/// Raised when an event is not legal in the current state.
///
/// The brief requires invalid transitions to be *rejected*, not silently
/// ignored, so this is thrown rather than being a no-op.
public struct InvalidTransition: Error, Equatable, Sendable, CustomStringConvertible {
    public let state: RecordingState
    public let event: RecordingEvent

    public init(state: RecordingState, event: RecordingEvent) {
        self.state = state
        self.event = event
    }

    public var description: String {
        "Invalid recording transition: cannot apply \(event) while in \(state)."
    }
}
