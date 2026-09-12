import AVFoundation
import Foundation
import PromptCamCore

/// The real capture pipeline.
///
/// STATICALLY_REVIEWED — written against long-established AVFoundation API
/// (`AVCaptureSession`, `AVCaptureMovieFileOutput`, `AVCaptureDeviceInput`,
/// `AVCaptureAudioChannel`), but never compiled. REQUIRES_MAC.
///
/// ## The rule this class exists to enforce
///
/// A recording is "finished" only when
/// `fileOutput(_:didFinishRecordingTo:from:error:)` fires **and** reports no
/// error. That delegate callback is the single origin of
/// `CaptureEvent.recordingFinished`, which is in turn the only event that can
/// lead the state machine to `.saved`. There is no other path, so the app
/// cannot tell the operator their interview is safe before the operating
/// system says so.
final class AVFoundationCaptureService: NSObject, CaptureService, @unchecked Sendable {

    let events: AsyncStream<CaptureEvent>
    private let continuation: AsyncStream<CaptureEvent>.Continuation

    /// All session mutation happens here. AVFoundation configuration is not
    /// thread-safe and must never run on the main thread.
    private let sessionQueue = DispatchQueue(label: "com.promptcam.capture.session")

    private let session = AVCaptureSession()
    private let movieOutput = AVCaptureMovieFileOutput()
    private var videoInput: AVCaptureDeviceInput?
    private var audioInput: AVCaptureDeviceInput?

    /// Where the current take is being written. Retained so an interruption can
    /// report the partial file rather than losing track of it.
    private var currentOutputURL: URL?
    private var levelTimer: DispatchSourceTimer?
    private var hasEmittedStart = false
    /// Set when a stop arrives before the output has actually begun recording.
    ///
    /// Defence in depth: `DirectorSessionModel` already queues stop until
    /// `.recordingStarted`, but the same race exists for anything else driving
    /// this service, and losing a stop leaves a capture running unattended.
    private var stopRequestedBeforeStart = false

    /// Exposed so the preview layer can attach to the same session.
    var captureSession: AVCaptureSession { session }

    override init() {
        var captured: AsyncStream<CaptureEvent>.Continuation!
        events = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured
        super.init()
        registerForInterruptions()
    }

    deinit {
        levelTimer?.cancel()
        NotificationCenter.default.removeObserver(self)
        continuation.finish()
    }

    // MARK: - CaptureService

    func prepare(direction: CaptureDirection) async {
        await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                self?.configureSession(direction: direction)
                resume.resume()
            }
        }
    }

    func startRecording(toPath path: String) async {
        await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { resume.resume(); return }

                guard self.session.isRunning else {
                    self.continuation.yield(
                        .recordingFailed(.captureFailed("The camera session was not running."))
                    )
                    resume.resume()
                    return
                }
                guard !self.movieOutput.isRecording else {
                    // Defensive: the state machine already rejects a second
                    // start, so reaching here means a bug rather than a user
                    // action. Do not start a second file.
                    resume.resume()
                    return
                }

                let url = URL(fileURLWithPath: path)
                // Remove a stale file at the destination; AVFoundation refuses
                // to write over an existing file.
                if FileManager.default.fileExists(atPath: path) {
                    try? FileManager.default.removeItem(at: url)
                }

                self.currentOutputURL = url
                self.hasEmittedStart = false
                self.stopRequestedBeforeStart = false
                self.movieOutput.startRecording(to: url, recordingDelegate: self)
                resume.resume()
            }
        }
    }

    func stopRecording() async {
        await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { resume.resume(); return }
                // The file is NOT complete here. Completion arrives via the
                // delegate callback below.
                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                } else if self.currentOutputURL != nil {
                    // A stop arrived between `startRecording` and the output
                    // actually starting. Asking it to stop now would do
                    // nothing, so remember the request and honour it the moment
                    // recording begins — otherwise the capture runs on with
                    // nobody waiting for it.
                    self.stopRequestedBeforeStart = true
                }
                resume.resume()
            }
        }
    }

    func tearDown() async {
        await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { resume.resume(); return }
                self.stopLevelMetering()
                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                }
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                resume.resume()
            }
        }
    }

    // MARK: - Configuration

    private func configureSession(direction: CaptureDirection) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .high

        // Video input.
        guard let camera = CameraDirectionAdapter.device(for: direction) else {
            continuation.yield(
                .configurationFailed(.cameraUnavailable("No camera was found on this device."))
            )
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if let existing = videoInput { session.removeInput(existing) }
            guard session.canAddInput(input) else {
                continuation.yield(
                    .configurationFailed(.cameraUnavailable("The camera could not be added to the session."))
                )
                return
            }
            session.addInput(input)
            videoInput = input
        } catch {
            continuation.yield(
                .configurationFailed(.cameraUnavailable(error.localizedDescription))
            )
            return
        }

        // Audio input. Reported separately from the camera so the operator is
        // told which one actually failed.
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            continuation.yield(
                .configurationFailed(.microphoneUnavailable("No microphone was found on this device."))
            )
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: microphone)
            if let existing = audioInput { session.removeInput(existing) }
            guard session.canAddInput(input) else {
                continuation.yield(
                    .configurationFailed(.microphoneUnavailable("The microphone could not be added to the session."))
                )
                return
            }
            session.addInput(input)
            audioInput = input
        } catch {
            continuation.yield(
                .configurationFailed(.microphoneUnavailable(error.localizedDescription))
            )
            return
        }

        if !session.outputs.contains(movieOutput) {
            guard session.canAddOutput(movieOutput) else {
                continuation.yield(
                    .configurationFailed(.captureFailed("The recorder could not be added to the session."))
                )
                return
            }
            session.addOutput(movieOutput)
        }

        if let connection = movieOutput.connection(with: .video),
           connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = .auto
        }

        if !session.isRunning {
            session.startRunning()
        }

        startLevelMetering()
        continuation.yield(.ready)
    }

    // MARK: - Microphone level

    /// Polls the recording connection's audio channels.
    ///
    /// `AVCaptureAudioChannel.averagePowerLevel` is in decibels, roughly
    /// -160...0, and is only meaningful while the session is running. It is
    /// mapped to 0...1 so the meter view needs no audio knowledge.
    private func startLevelMetering() {
        stopLevelMetering()
        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let connection = self.movieOutput.connection(with: .audio) else { return }
            let channels = connection.audioChannels
            guard !channels.isEmpty else { return }

            let averageDecibels = channels
                .map { Double($0.averagePowerLevel) }
                .reduce(0, +) / Double(channels.count)

            self.continuation.yield(.audioLevel(Self.normalisedLevel(decibels: averageDecibels)))
        }
        timer.resume()
        levelTimer = timer
    }

    private func stopLevelMetering() {
        levelTimer?.cancel()
        levelTimer = nil
    }

    /// Maps decibels to 0...1 across a 60 dB window, which is the useful range
    /// for speech on a phone microphone.
    static func normalisedLevel(decibels: Double) -> Double {
        let floorDecibels = -60.0
        guard decibels.isFinite else { return 0 }
        if decibels <= floorDecibels { return 0 }
        if decibels >= 0 { return 1 }
        return (decibels - floorDecibels) / -floorDecibels
    }

    // MARK: - Interruptions

    private func registerForInterruptions() {
        let center = NotificationCenter.default

        center.addObserver(
            self,
            selector: #selector(sessionWasInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(sessionRuntimeError(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: session
        )
        center.addObserver(
            self,
            selector: #selector(audioSessionInterrupted(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func sessionWasInterrupted(_ notification: Notification) {
        let reasonValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
        let reason = reasonValue.flatMap(AVCaptureSession.InterruptionReason.init(rawValue:))

        let mapped: InterruptionReason
        switch reason {
        case .audioDeviceInUseByAnotherClient:
            mapped = .audioSessionLost
        case .videoDeviceNotAvailableInBackground:
            mapped = .backgrounded
        case .videoDeviceNotAvailableDueToSystemPressure:
            mapped = .resourcePressure
        default:
            mapped = .captureSessionInterrupted
        }
        continuation.yield(.interrupted(mapped))
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        continuation.yield(.interruptionEnded)
    }

    @objc private func sessionRuntimeError(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        continuation.yield(
            .recordingFailed(.captureFailed(error?.localizedDescription ?? "The camera reported an error."))
        )
    }

    @objc private func audioSessionInterrupted(_ notification: Notification) {
        guard
            let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        if type == .began {
            continuation.yield(.interrupted(.audioSessionLost))
        } else {
            continuation.yield(.interruptionEnded)
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension AVFoundationCaptureService: AVCaptureFileOutputRecordingDelegate {

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        guard !hasEmittedStart else { return }
        hasEmittedStart = true
        // The first byte is on disk. The session rebases marker offsets from
        // here, so a slow camera start does not skew every timestamp.
        continuation.yield(.recordingStarted)

        if stopRequestedBeforeStart {
            stopRequestedBeforeStart = false
            // Honour the stop that arrived too early. Runs on the session queue
            // because this delegate callback is delivered there.
            if movieOutput.isRecording {
                movieOutput.stopRecording()
            }
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        currentOutputURL = nil
        stopRequestedBeforeStart = false

        if let error = error as NSError? {
            // AVFoundation reports a partial-but-usable file through
            // `AVErrorRecordingSuccessfullyFinishedKey`. When it says the file
            // finished successfully, the take is genuinely complete even though
            // an error accompanied it — anything else is a real failure.
            let finishedSuccessfully =
                (error.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false

            if finishedSuccessfully {
                emitFinished(url: outputFileURL)
            } else {
                // The file is NOT deleted here. A partial capture belongs to the
                // operator, and the session records its path so it can be
                // recovered.
                continuation.yield(.recordingFailed(.captureFailed(error.localizedDescription)))
            }
            return
        }

        emitFinished(url: outputFileURL)
    }

    private func emitFinished(url: URL) {
        // Read the real duration from the asset rather than trusting a timer,
        // so the stored duration matches the file the user will play back.
        let asset = AVURLAsset(url: url)
        Task { [continuation] in
            let duration: TimeInterval
            do {
                let loaded = try await asset.load(.duration)
                duration = CMTimeGetSeconds(loaded)
            } catch {
                // A duration we cannot read is reported as zero rather than
                // guessed at; the file itself is still handed over.
                duration = 0
            }
            continuation.yield(.recordingFinished(path: url.path, duration: duration))
        }
    }
}
