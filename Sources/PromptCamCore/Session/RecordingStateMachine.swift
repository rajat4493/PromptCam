import Foundation

/// The authoritative recording state machine.
///
/// Design rules, each covered by a test:
///
/// 1. `.saved` is reachable **only** from `.finishing` via `.saveConfirmed`.
///    No other path exists, so the app physically cannot claim a recording was
///    saved before the operating system confirmed the file.
/// 2. Repeated `.beginRecording` or `.stop` is rejected, so double-tapping the
///    record button cannot start two captures or truncate one.
/// 3. A cancelled countdown returns to `.preparing`: the pipeline is still
///    configured, so the operator can roll again immediately.
/// 4. A countdown reaching zero does **not** auto-start capture — the caller
///    must still send `.beginRecording`, so a cancel racing the final tick
///    cannot produce an unwanted recording.
/// 5. `.interrupt` is accepted from every busy state, because interruptions
///    are not under the app's control.
public struct RecordingStateMachine: Equatable, Sendable {
    public private(set) var state: RecordingState

    /// Every state the session has occupied, for diagnostics and tests.
    public private(set) var history: [RecordingState]

    public init(state: RecordingState = .idle) {
        self.state = state
        self.history = [state]
    }

    /// Whether `event` is legal right now, without mutating anything.
    public func canApply(_ event: RecordingEvent) -> Bool {
        Self.nextState(from: state, for: event) != nil
    }

    /// Applies `event`, or throws `InvalidTransition` if it is not legal.
    @discardableResult
    public mutating func apply(_ event: RecordingEvent) throws -> RecordingState {
        guard let next = Self.nextState(from: state, for: event) else {
            throw InvalidTransition(state: state, event: event)
        }
        state = next
        history.append(next)
        return next
    }

    /// The transition table. `nil` means "not legal".
    ///
    /// Written as one exhaustive function so the entire legal surface of a
    /// session can be read and reviewed in one place.
    public static func nextState(from state: RecordingState, for event: RecordingEvent) -> RecordingState? {
        switch (state, event) {

        // MARK: Preparing the pipeline
        case (.idle, .prepare):
            return .preparing
        case (.preparing, .prepareSucceeded):
            // Idempotent: `.preparing` covers both "configuring" and "ready".
            return .preparing

        // MARK: Countdown
        case (.preparing, .startCountdown(let seconds)):
            // A zero or negative countdown is meaningless. Reject it rather
            // than silently rolling immediately.
            return seconds > 0 ? .countdown(remaining: seconds) : nil
        case (.countdown(let remaining), .countdownTick):
            // Ticking an already-finished countdown is rejected rather than
            // looping at zero, so a runaway timer cannot go unnoticed.
            guard remaining > 0 else { return nil }
            return .countdown(remaining: remaining - 1)
        case (.countdown, .cancelCountdown):
            return .preparing
        case (.countdown(let remaining), .beginRecording):
            // Only a countdown that actually reached zero may roll.
            return remaining == 0 ? .recording : nil

        // MARK: Recording
        case (.preparing, .beginRecording):
            return .recording
        case (.recording, .stop):
            return .finishing

        // MARK: Finishing — the only route to `.saved`
        case (.finishing, .saveConfirmed(let fileName)):
            return .saved(fileName: fileName)
        case (.finishing, .saveFailed(let failure)):
            return .failed(failure)

        // MARK: Failure, accepted wherever it can genuinely occur
        case (.idle, .fail(let failure)),
             (.preparing, .fail(let failure)),
             (.countdown, .fail(let failure)),
             (.recording, .fail(let failure)),
             (.finishing, .fail(let failure)):
            return .failed(failure)

        // MARK: Interruption, accepted from any busy state
        case (.preparing, .interrupt(let reason)),
             (.countdown, .interrupt(let reason)),
             (.recording, .interrupt(let reason)),
             (.finishing, .interrupt(let reason)):
            return .interrupted(reason: reason)

        // MARK: Restart after coming to rest
        case (.saved, .reset),
             (.failed, .reset),
             (.interrupted, .reset):
            return .idle
        case (.idle, .reset):
            // Harmless no-op; keeps teardown paths simple.
            return .idle

        // MARK: Everything else is rejected
        //
        // Named explicitly so the reasons are reviewable:
        //   (.recording,  .beginRecording) double-tap record
        //   (.finishing,  .stop)           double-tap stop
        //   (.recording,  .saveConfirmed)  claiming a save before finishing
        //   (.idle,       .beginRecording) rolling without a configured pipeline
        //   (.saved,      .stop)           acting on a finished session
        //   (.interrupted,.saveConfirmed)  reviving an interrupted take
        default:
            return nil
        }
    }
}
