import Foundation

/// What the capture pipeline reports back to the session.
public enum CaptureEvent: Equatable, Sendable {
    /// The pipeline configured successfully and is ready to record.
    case ready
    case configurationFailed(RecordingFailure)
    /// Writing to disk has actually begun.
    case recordingStarted
    /// The OS finalised a complete file at `path` with `duration` seconds.
    ///
    /// This is the **only** signal that may lead to a "saved" claim.
    case recordingFinished(path: String, duration: TimeInterval)
    /// Capture ended **and the file is closed**, but produced no usable result.
    ///
    /// Emitted only from the platform's recording-completion callback. Because
    /// the file is final, the session may safely move it into recovery.
    case recordingFailed(RecordingFailure)
    /// The pipeline reported an error **while the file may still be open**.
    ///
    /// Distinct from `recordingFailed` on purpose, and the distinction is a
    /// safety property rather than a nicety: a runtime error does not mean the
    /// writer has finished. Moving or sharing the file at this point would
    /// touch something the platform is still writing to, so the session records
    /// the failed outcome but leaves the file alone and waits for the
    /// completion callback (or a bounded timeout) before reconciling it.
    case runtimeError(RecordingFailure)
    /// The system interrupted capture.
    case interrupted(InterruptionReason)
    /// The interruption ended and capture could be resumed.
    case interruptionEnded
    /// Current microphone level, normalised 0...1.
    case audioLevel(Double)
}

/// Which physical camera direction a session is capturing from.
///
/// PromptCam's primary workflow records the **subject** with a rear camera
/// while the operator works on the inner display. This enum exists so that
/// direction changes reported by the platform layer can be represented in
/// `PromptCamCore` without importing AVFoundation, and so a Duo front-camera
/// API can never be selected by accident.
public enum CaptureDirection: String, Equatable, Sendable, Codable {
    /// Rear-facing: the interview subject. PromptCam's default and intent.
    case rear
    /// Front-facing: the operator. Only ever entered on explicit request.
    case front

    public var isSubjectFacing: Bool { self == .rear }
}

/// Abstracts the AVFoundation capture pipeline.
///
/// `PromptCamCore` never imports AVFoundation. The real implementation
/// (`AVFoundationCaptureService`) lives in the iOS layer; the tests use
/// `FakeCaptureService`. This seam is what makes camera failure, microphone
/// failure, interruption and save failure testable without hardware.
public protocol CaptureService: AnyObject, Sendable {
    /// Events emitted by the pipeline. A session consumes exactly one stream.
    var events: AsyncStream<CaptureEvent> { get }

    /// Configures camera and microphone for `direction`. Emits `.ready` or
    /// `.configurationFailed`.
    func prepare(direction: CaptureDirection) async

    /// Begins writing to `path`. Emits `.recordingStarted`, then eventually
    /// `.recordingFinished` or `.recordingFailed`.
    func startRecording(toPath path: String) async

    /// Requests a stop. The file is **not** complete until
    /// `.recordingFinished` arrives.
    func stopRecording() async

    /// Releases camera and microphone.
    func tearDown() async
}
