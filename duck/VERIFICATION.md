# Verification

Full row-by-row ledger: [`../docs/VERIFICATION_LEDGER.md`](../docs/VERIFICATION_LEDGER.md).
This is the summary a reviewer should be able to trust after thirty seconds.

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

Current counts: Core 15 files / 1,827 lines; iOS 25 files / 4,235 lines; Tests
7 files / 2,317 lines; **130 declared test cases, 0 executed.**

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

## Defects found and fixed in review

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
