import Testing
import Foundation
@testable import PromptCamCore

@Suite("Recording state machine: the happy path")
struct RecordingStateMachineHappyPathTests {

    @Test("Idle to saved, the whole intended route")
    func fullSuccessfulRoute() throws {
        var machine = RecordingStateMachine()
        #expect(machine.state == .idle)

        try machine.apply(.prepare)
        #expect(machine.state == .preparing)

        try machine.apply(.prepareSucceeded)
        #expect(machine.state == .preparing)

        try machine.apply(.startCountdown(seconds: 3))
        #expect(machine.state == .countdown(remaining: 3))

        try machine.apply(.countdownTick)
        try machine.apply(.countdownTick)
        try machine.apply(.countdownTick)
        #expect(machine.state == .countdown(remaining: 0))

        try machine.apply(.beginRecording)
        #expect(machine.state == .recording)

        try machine.apply(.stop)
        #expect(machine.state == .finishing)

        try machine.apply(.saveConfirmed(fileName: "a.mov"))
        #expect(machine.state == .saved(fileName: "a.mov"))
        #expect(machine.state.hasConfirmedSavedFile)
    }

    @Test("Recording without a countdown is allowed")
    func recordWithoutCountdown() throws {
        var machine = RecordingStateMachine()
        try machine.apply(.prepare)
        try machine.apply(.beginRecording)
        #expect(machine.state == .recording)
    }

    @Test("A terminal session can be reset for another take")
    func resetAfterTerminalStates() throws {
        for terminal in [
            RecordingState.saved(fileName: "a.mov"),
            .failed(.insufficientStorage),
            .interrupted(reason: .backgrounded)
        ] {
            var machine = RecordingStateMachine(state: terminal)
            try machine.apply(.reset)
            #expect(machine.state == .idle)
        }
    }
}

@Suite("Recording state machine: invalid transitions are rejected")
struct RecordingStateMachineRejectionTests {

    @Test("Recording cannot start from idle without preparing")
    func cannotRecordFromIdle() {
        var machine = RecordingStateMachine()
        #expect(throws: InvalidTransition.self) {
            try machine.apply(.beginRecording)
        }
        // The rejection must not have moved the state.
        #expect(machine.state == .idle)
    }

    @Test("Repeatedly tapping record cannot start a second capture")
    func doubleTapRecord() throws {
        var machine = RecordingStateMachine()
        try machine.apply(.prepare)
        try machine.apply(.beginRecording)
        #expect(machine.state == .recording)

        for _ in 0..<5 {
            #expect(throws: InvalidTransition.self) {
                try machine.apply(.beginRecording)
            }
        }
        #expect(machine.state == .recording)
        // Exactly one entry into `.recording`, no matter how many taps.
        #expect(machine.history.filter { $0 == .recording }.count == 1)
    }

    @Test("Repeatedly tapping stop cannot truncate or double-finish a take")
    func doubleTapStop() throws {
        var machine = RecordingStateMachine()
        try machine.apply(.prepare)
        try machine.apply(.beginRecording)
        try machine.apply(.stop)
        #expect(machine.state == .finishing)

        for _ in 0..<5 {
            #expect(throws: InvalidTransition.self) {
                try machine.apply(.stop)
            }
        }
        #expect(machine.state == .finishing)
        #expect(machine.history.filter { $0 == .finishing }.count == 1)
    }

    @Test("A save cannot be claimed while still recording")
    func cannotConfirmSaveWhileRecording() throws {
        var machine = RecordingStateMachine()
        try machine.apply(.prepare)
        try machine.apply(.beginRecording)

        #expect(throws: InvalidTransition.self) {
            try machine.apply(.saveConfirmed(fileName: "premature.mov"))
        }
        #expect(machine.state == .recording)
        #expect(machine.state.hasConfirmedSavedFile == false)
    }

    @Test("`.saved` is reachable only from `.finishing`")
    func savedOnlyFromFinishing() {
        let everyOtherState: [RecordingState] = [
            .idle,
            .preparing,
            .countdown(remaining: 3),
            .countdown(remaining: 0),
            .recording,
            .saved(fileName: "x.mov"),
            .failed(.insufficientStorage),
            .interrupted(reason: .audioSessionLost)
        ]

        for state in everyOtherState {
            let next = RecordingStateMachine.nextState(
                from: state,
                for: .saveConfirmed(fileName: "x.mov")
            )
            #expect(next == nil, "\(state) must not accept .saveConfirmed")
        }

        // And it *is* reachable from finishing.
        #expect(
            RecordingStateMachine.nextState(from: .finishing, for: .saveConfirmed(fileName: "x.mov"))
                == .saved(fileName: "x.mov")
        )
    }

    @Test("A zero or negative countdown is rejected")
    func rejectsNonPositiveCountdown() throws {
        var machine = RecordingStateMachine()
        try machine.apply(.prepare)

        #expect(throws: InvalidTransition.self) {
            try machine.apply(.startCountdown(seconds: 0))
        }
        #expect(throws: InvalidTransition.self) {
            try machine.apply(.startCountdown(seconds: -3))
        }
        #expect(machine.state == .preparing)
    }

    @Test("A countdown that has not reached zero cannot start recording")
    func countdownMustCompleteBeforeRecording() throws {
        var machine = RecordingStateMachine()
        try machine.apply(.prepare)
        try machine.apply(.startCountdown(seconds: 3))
        try machine.apply(.countdownTick)   // 2 left

        #expect(throws: InvalidTransition.self) {
            try machine.apply(.beginRecording)
        }
        #expect(machine.state == .countdown(remaining: 2))
    }

    @Test("Ticking a finished countdown is rejected rather than looping")
    func cannotTickPastZero() throws {
        var machine = RecordingStateMachine(state: .countdown(remaining: 1))
        try machine.apply(.countdownTick)
        #expect(machine.state == .countdown(remaining: 0))

        #expect(throws: InvalidTransition.self) {
            try machine.apply(.countdownTick)
        }
    }

    @Test("A finished session rejects further recording commands")
    func terminalStatesRejectCommands() {
        for terminal in [
            RecordingState.saved(fileName: "a.mov"),
            .failed(.insufficientStorage),
            .interrupted(reason: .backgrounded)
        ] {
            for event in [
                RecordingEvent.stop,
                .beginRecording,
                .startCountdown(seconds: 3),
                .countdownTick,
                .cancelCountdown,
                .saveConfirmed(fileName: "x.mov")
            ] {
                var machine = RecordingStateMachine(state: terminal)
                #expect(throws: InvalidTransition.self) {
                    try machine.apply(event)
                }
            }
        }
    }

    @Test("The error names both the state and the rejected event")
    func errorIsDiagnostic() {
        var machine = RecordingStateMachine(state: .recording)
        do {
            try machine.apply(.beginRecording)
            Issue.record("Expected the transition to be rejected")
        } catch let error as InvalidTransition {
            #expect(error.state == .recording)
            #expect(error.event == .beginRecording)
            #expect(error.description.contains("recording"))
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

@Suite("Recording state machine: countdown cancellation")
struct CountdownCancellationTests {

    @Test("Cancelling a countdown returns to a prepared pipeline, not to idle")
    func cancelReturnsToPreparing() throws {
        var machine = RecordingStateMachine()
        try machine.apply(.prepare)
        try machine.apply(.startCountdown(seconds: 5))
        try machine.apply(.countdownTick)

        try machine.apply(.cancelCountdown)

        // `.preparing` rather than `.idle` so the operator can roll again
        // without reconfiguring the camera.
        #expect(machine.state == .preparing)
        #expect(machine.canApply(.beginRecording))
    }

    @Test("A cancelled countdown never produced a recording")
    func cancelLeavesNoRecording() throws {
        var machine = RecordingStateMachine()
        try machine.apply(.prepare)
        try machine.apply(.startCountdown(seconds: 3))
        try machine.apply(.cancelCountdown)

        #expect(machine.history.contains(.recording) == false)
        #expect(machine.state.hasConfirmedSavedFile == false)
    }

    @Test("Cancel can be applied at any point in the countdown, including zero")
    func cancelAtAnyPoint() throws {
        for remaining in 0...5 {
            var machine = RecordingStateMachine(state: .countdown(remaining: remaining))
            try machine.apply(.cancelCountdown)
            #expect(machine.state == .preparing)
        }
    }

    @Test("Cancel is rejected when no countdown is running")
    func cancelWithoutCountdown() {
        for state in [RecordingState.idle, .preparing, .recording, .finishing] {
            var machine = RecordingStateMachine(state: state)
            #expect(throws: InvalidTransition.self) {
                try machine.apply(.cancelCountdown)
            }
        }
    }
}

@Suite("Recording state machine: failure and interruption")
struct RecordingFailureTests {

    @Test("A failed save yields `.failed`, never `.saved`")
    func failedSaveIsNotSaved() throws {
        var machine = RecordingStateMachine()
        try machine.apply(.prepare)
        try machine.apply(.beginRecording)
        try machine.apply(.stop)

        let failure = RecordingFailure.saveFailed(reason: "disk full", preservedPath: "/tmp/x.mov")
        try machine.apply(.saveFailed(failure))

        #expect(machine.state == .failed(failure))
        #expect(machine.state.hasConfirmedSavedFile == false)
        #expect(machine.state.savedFileName == nil)
    }

    @Test("A failed save preserves the path of the surviving file")
    func failedSavePreservesPath() {
        let failure = RecordingFailure.saveFailed(reason: "no space", preservedPath: "/tmp/keep.mov")
        #expect(failure.preservedPath == "/tmp/keep.mov")
        // A non-save failure has nothing to preserve.
        #expect(RecordingFailure.cameraPermissionDenied.preservedPath == nil)
    }

    @Test("Interruption is accepted from every busy state")
    func interruptionFromBusyStates() throws {
        let busyStates: [RecordingState] = [
            .preparing, .countdown(remaining: 3), .recording, .finishing
        ]
        for state in busyStates {
            var machine = RecordingStateMachine(state: state)
            try machine.apply(.interrupt(.audioSessionLost))
            #expect(machine.state == .interrupted(reason: .audioSessionLost))
        }
    }

    @Test("Interruption is rejected once the session has come to rest")
    func interruptionRejectedWhenIdleOrTerminal() {
        for state in [
            RecordingState.idle,
            .saved(fileName: "a.mov"),
            .failed(.insufficientStorage),
            .interrupted(reason: .backgrounded)
        ] {
            var machine = RecordingStateMachine(state: state)
            #expect(throws: InvalidTransition.self) {
                try machine.apply(.interrupt(.backgrounded))
            }
        }
    }

    @Test("Resumability is classified per reason")
    func resumability() {
        #expect(InterruptionReason.audioSessionLost.isResumable)
        #expect(InterruptionReason.captureSessionInterrupted.isResumable)
        #expect(InterruptionReason.backgrounded.isResumable)
        #expect(InterruptionReason.resourcePressure.isResumable == false)
    }

    @Test("Busy states block dismissal; resting states do not")
    func busyFlags() {
        #expect(RecordingState.preparing.isBusy)
        #expect(RecordingState.countdown(remaining: 1).isBusy)
        #expect(RecordingState.recording.isBusy)
        #expect(RecordingState.finishing.isBusy)

        #expect(RecordingState.idle.isBusy == false)
        #expect(RecordingState.saved(fileName: "a").isBusy == false)
        #expect(RecordingState.failed(.insufficientStorage).isBusy == false)
        #expect(RecordingState.interrupted(reason: .backgrounded).isBusy == false)
    }
}
