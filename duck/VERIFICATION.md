# Verification

Full row-by-row ledger: [`../docs/VERIFICATION_LEDGER.md`](../docs/VERIFICATION_LEDGER.md).
This is the summary a reviewer should be able to trust after thirty seconds.

**M1 remains NOT COMPLETE.** A second review found five further defects, all
now fixed. Nothing has been compiled; no Apple-platform verification is
claimed.

## Scoreboard

| Result | Rows |
|---|---|
| `VERIFIED_LINUX` | 9 |
| `STATICALLY_REVIEWED` | 24 |
| `REQUIRES_MAC` | 12 |
| `REQUIRES_DUO_SIMULATOR` | 4 |
| `REQUIRES_PHYSICAL_DUO` | 7 |
| `BLOCKED` | 3 |
| `FAILED` | 0 |

> **Nothing in PromptCam is VERIFIED on an Apple platform. Not one line has
> been compiled.**

## What was actually executed

Two things, both real.

**1. Environment reconnaissance.** No `xcodebuild`, `xcrun`, `simctl`, no
Xcode, no `swift`. Three separate Swift toolchain hosts return 403 CONNECT
under egress policy.

**2. `python3 Scripts/static_review.py` — passing.**

| Invariant | Result |
|---|---|
| Core imports no platform framework (11 forbidden modules × 15 files) | 0 violations |
| Unverified Duo symbols confined to `Platform/` (12 symbols) | 0 violations |
| No `utsname`, `UIDevice.current.model`, `sysctlbyname`, model string literals | 0 violations |
| `UIScreen.main` never referenced | 0 occurrences |
| Every `Platform/` file using an unverified symbol is marked | 5/5 marked |
| Brackets balance across all Swift files | balanced |
| No source file asserts VERIFIED or production-ready | 0 claims |

Current counts: Core 16 files / 2,437 lines; iOS 25 files / 3,975 lines; Tests
9 files / 3,174 lines; **165 declared test cases, 0 executed** — 157 runnable
under `swift test`, 8 requiring Xcode.

Two further fixes were adopted from a parallel solution to the same review
(`90e09c3`, merged as SC-23): an interruption no longer exposes the in-flight
capture path until the file is final, and the sweeper now also protects every
path an existing library row references.

The script proves *structure*. It is not a compiler and proves nothing about
whether the code runs.

## Structural guarantees (reviewed, not executed)

Two properties hold by construction rather than by discipline:

- **`.saved` has exactly one inbound edge**, `.finishing --saveConfirmed-->`,
  and the only origin of that event is AVFoundation's
  `didFinishRecordingTo` callback. The app cannot claim a save the OS has not
  confirmed. `savedOnlyFromFinishing` asserts all eight other states reject it.
- **`SubjectSnapshot` has no field that could carry** an upcoming question, the
  deck name, notes or controls, so director-only data cannot reach the subject
  surface.

## Defects found and fixed in review — round two

The first round's regression tests reached `InterviewSessionEngine` and a
duplicate store, **not** the orchestration. That was the finding that mattered
most: the lifecycle defects lived in code no test could reach. Orchestration
moved into `PromptCamCore` as `InterviewSessionCoordinator`, and the iOS layer
became a mirror-and-schedule wrapper.

| Severity | Defect | Fix | Test |
|---|---|---|---|
| P0 | The start-up watchdog failed the session but never stopped the pipeline. A `recordingStarted` arriving afterwards began an unattended recording that ran indefinitely. | `captureStartTimedOut` requests a stop and sets a pending stop; a `recordingStarted` on a terminal session stops capture instead of adopting it | `CaptureStartupTimeoutTests` (4) |
| P0 | `hasFinalised` conflated two facts. A runtime error set it, so the later completion callback was discarded and the finished file was lost. The same path also *moved* the file while AVFoundation might still be writing it. | Split into `hasPersistedOutcome` and `hasReconciledFile`. New `CaptureEvent.runtimeError` means "error, file may still be open": the outcome is recorded, the file is left alone, and reconciliation waits for the completion callback or a bounded `finalisationTimedOut` backstop | `RuntimeErrorThenCompletionTests` (3) |
| P0 product | Archive defaults to Release, where `PROMPTCAM_DUO` was undefined — an App Store build silently missing the headline feature | `DuoRelease` configuration (release-optimised, Duo enabled); the **PromptCam (Duo)** scheme pins Archive and Profile to it | build configuration |
| P1 | Markers and question changes could be timestamped during the start-up window, before any file existed, and were then invalidated by the rebase | The engine records **no** timeline event until `isCaptureConfirmed`. `noteCaptureStarted` writes the opening question at offset zero — the question genuinely on screen when the first byte lands. `duration` reports zero until confirmed | `TimelineGatingTests` (4) + engine tests (3) |
| P1 | The new tests did not exercise the orchestrator at all | `SessionCoordinatorTests` — 25 cases against the real coordinator with scripted capture-event sequences | see below |

### What the orchestration tests actually script

| Scenario | Asserts |
|---|---|
| Timeout, then delayed start | the pipeline is stopped; a late start is stopped again, not adopted |
| Timeout, then late completion | reconciliation stayed open; the file becomes recoverable; never reported as saved |
| Timeout, no completion | the bounded backstop preserves the file, and it survives a sweep |
| Runtime error | the file is untouched and **not** offered for recovery while the writer may hold it |
| Runtime error, then completion | the completed file is reconciled, not discarded; one row, not two |
| Duplicate completion (×3) | idempotent; outcome and filename unchanged |
| Completion after a save | cannot downgrade a saved take |
| Interruption, then completion | stop requested, outcome persisted, then the file reconciled into one row |
| Interruption, no completion | the interview still appears in the library; the backstop makes it recoverable |
| Stop during start-up | queued, not dropped; honoured on confirmation; still reaches a confirmed save |
| Permission denied | fails before the camera is ever configured |
| Store failure | preserves the file, never claims a save |

## Defects found and fixed in review — round one

| Severity | Defect | Fix | Regression test |
|---|---|---|---|
| P0 | A preserved recording was deleted by the next session's cleanup | Persistent `Recovery/` directory; cleanup narrowed to old, unreferenced files | `PreservedFileSurvivesCleanupTests` (6) |
| P0 | An interruption plus a late completion callback orphaned the video | One idempotent finalisation path; reconcile instead of confirming; stable identity + upsert | `LateFileReconciliationTests` (6) |
| P0 | Stop could race capture startup and strand `.finishing` | Stop queued until `.recordingStarted`; service-level guard; 8 s watchdog | `StopDuringStartupTests` (4) |
| P1 | Duo feature compiled out of both configurations | `Duo` configuration + scheme | n/a (build config) |
| P1 | `Double(hinge.angle)` — no such initialiser for `Angle` | `hinge.angle.degrees` | n/a (`REQUIRES_MAC`) |
| P1 | "Video has been kept" was not actionable | In-app Recover share action, existence-checked | n/a (UI) |
| P1 | Capture-event ownership unsafe across sessions | Per-session capture service; `captureTask` cleared | `SessionReuseTests` (2) |
| — | A deleted sample deck reappeared | Persisted `hasSeededSample` flag | existing seed test |

Two further defects were caught earlier by the static review itself: a callback
named `onAvailabilityChange` that shadowed Apple's modifier, and an unset
ephemeral-store flag that would have hidden the "storage unavailable" warning.

## What closes the gap

`docs/MAC_VALIDATION.md`, in order. Steps 1–7 convert 24
`STATICALLY_REVIEWED` rows into real results. Step 2 is a ten-second
`swiftc -typecheck` probe that settles the accessory question before any other
work.
