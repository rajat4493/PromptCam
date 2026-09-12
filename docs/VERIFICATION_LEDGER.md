# PromptCam — Verification Ledger

**Last updated:** 2026-09-12
**Rule:** a row's Result may only be raised by an actual execution. No row is
marked `VERIFIED_LINUX` without a command that ran here; nothing becomes
`VERIFIED` on a Mac or a device without that Mac or device.

`STATICALLY_REVIEWED` never becomes `VERIFIED`. It is replaced by a compiler or
hardware result, or it stays as it is.

## Result vocabulary

| Result | Meaning |
|---|---|
| `VERIFIED_LINUX` | An executable check ran in this environment and passed |
| `STATICALLY_REVIEWED` | Source read line by line; never compiled |
| `REQUIRES_MAC` | Needs Xcode 27.1 + iOS 27.1 SDK |
| `REQUIRES_DUO_SIMULATOR` | Needs Device Hub + an iPhone Duo simulator |
| `REQUIRES_PHYSICAL_DUO` | Needs the physical device |
| `BLOCKED` | Cannot proceed at all from here |
| `FAILED` | Attempted and did not work |

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

**Nothing in PromptCam is VERIFIED on an Apple platform.** Not one line has
been compiled. Read the whole table before describing this app to anyone.

---

## A. Environment and toolchain

| # | Requirement | Verification method | Evidence | Result | Remaining limitation |
|---|---|---|---|---|---|
| A1 | Determine whether an Apple toolchain is available | `command -v xcodebuild xcrun xcode-select simctl`; `ls -d /Applications/Xcode*.app /Library/Developer` | All absent | `VERIFIED_LINUX` | Conclusion is "absent", which is itself the blocker |
| A2 | Determine whether Swift is available | `command -v swift swiftc` | Not installed | `VERIFIED_LINUX` | — |
| A3 | Attempt to install a Swift toolchain | `curl` to `download.swift.org`, `archive.swiftlang.xyz`, `apt.swiftlang.xyz`; `apt-cache search swift` | All three hosts return **403 CONNECT** (egress policy); apt "swift" is OpenStack Swift | `BLOCKED` | No Swift on Linux. Policy denial, not retried per `/root/.ccr/README.md` |
| A4 | Confirm Xcode 27.1 / iOS 27.1 SDK | Impossible locally. Apple's published release-note indexes list Xcode 26→26.6 then **Xcode 27 RC**, and iOS 26→26.6 then **iOS 27 RC** | No 27.1 in published docs | `REQUIRES_MAC` | 27.1 is SUPPLIED by the product owner; unconfirmable from here |
| A5 | Confirm Duo SDK symbol signatures | Searched complete SwiftUI/AVFoundation/UIKit symbol indexes + iOS 27 RC release notes + 407 framework names | `sceneAccessory` family present (iOS 27.0). `CameraCaptureAccessory`, `onHingeChange`, `reservedRegions`, `ArrangementView`, `AVCaptureDeviceDirectionCoordinator`, Duo camera types: **not present** | `REQUIRES_MAC` | See `ASSUMPTIONS.md` §2.1 |
| A6 | Confirm Device Hub / Duo simulator exists | Impossible locally | No evidence either way | `REQUIRES_DUO_SIMULATOR` | `xcrun simctl list devicetypes \| grep -i duo` on a Mac |

---

## B. Architectural invariants — executed here

Command: `python3 Scripts/static_review.py` → **PASSED**
(45 Swift files: Core 15/1751 lines, iOS 25/3817 lines, Tests 6/1953 lines; 112 declared test cases)

| # | Requirement | Verification method | Evidence | Result | Remaining limitation |
|---|---|---|---|---|---|
| B1 | `PromptCamCore` imports no platform framework | Static review, `core-purity` check over all 15 Core files against 11 forbidden modules | 0 violations | `VERIFIED_LINUX` | Proves imports, not that the code compiles |
| B2 | Unverified Duo symbols appear only in `PromptCamiOS/Platform/` | Static review, `duo-isolation` check, 12 symbols × all non-Platform files | 0 violations | `VERIFIED_LINUX` | A correction is confined to 5 files |
| B3 | No model-name or fixed-dimension device detection | Static review, `device-detection` check (`utsname`, `UIDevice.current.model`, `sysctlbyname`, model string literals, `modelIdentifier`) | 0 violations | `VERIFIED_LINUX` | — |
| B4 | `UIScreen.main` is never referenced | Same check | 0 occurrences | `VERIFIED_LINUX` | — |
| B5 | Every Platform file using an unverified symbol carries a `REQUIRES_MAC_VALIDATION` marker | Static review, `marker` check | All 5 marked | `VERIFIED_LINUX` | — |
| B6 | Brackets, braces and parentheses balance in every Swift file | Static review, comment- and string-aware balance scan | Balanced in all 45 | `VERIFIED_LINUX` | Catches common typos; **is not a parser** and cannot find a balanced-but-wrong brace |
| B7 | No source file claims VERIFIED or production-ready status | Static review, `honesty` check | 0 claims | `VERIFIED_LINUX` | — |
| B8 | `PROMPTCAM_DUO` is off by default so the baseline build is not blocked by Duo APIs | Read `project.yml`; Debug and Release conditions contain no `PROMPTCAM_DUO` | Confirmed | `VERIFIED_LINUX` | — |
| B9 | The subject surface cannot receive director-only data | `SubjectSnapshot` has 7 fields, none of which can carry upcoming questions, the deck, or notes. A test asserts it | `VERIFIED_LINUX` (type shape) | Test itself is `REQUIRES_MAC` to run |

---

## C. Product success criteria

Criteria S1–S15 from `PRODUCT.md` §7.

| # | Requirement | Verification method | Evidence | Result | Remaining limitation |
|---|---|---|---|---|---|
| S1 | Create, edit, reorder a deck; survives relaunch | 21 test cases in `DeckTests.swift` | Written, never run | `STATICALLY_REVIEWED` → `REQUIRES_MAC` | Needs `swift test` |
| S2 | A complete interview records and plays back | UAT 5 | None | `REQUIRES_MAC` then physical iPhone | Simulator has no camera |
| S3 | Never reports "saved" without OS confirmation | `.saved` reachable only from `.finishing` via `.saveConfirmed`; `savedOnlyFromFinishing` asserts all 8 other states reject it; capture service emits `recordingFinished` only from `didFinishRecordingTo` | Type shape reviewed; tests written | `STATICALLY_REVIEWED` → `REQUIRES_MAC` | Structurally enforced; unexecuted |
| S4 | State transitions total; invalid ones rejected | 19 cases in `RecordingStateMachineTests.swift` | Written, never run | `STATICALLY_REVIEWED` → `REQUIRES_MAC` | — |
| S5 | Questions change mid-recording, each timestamped | 6 cases in `QuestionNavigationTests` | Written, never run | `STATICALLY_REVIEWED` → `REQUIRES_MAC` | Offsets exact under `ManualSessionClock` |
| S6 | Markers with accurate timestamps | 7 cases in `MarkerTests`, incl. rebase onto the real first byte | Written, never run | `STATICALLY_REVIEWED` → `REQUIRES_MAC` | Real-clock accuracy needs a device |
| S7 | Video and marker list export | `MarkerExportTests` (13 cases) + `ShareLink` wiring | Format logic written; share sheet unexercised | `STATICALLY_REVIEWED` → `REQUIRES_MAC` | — |
| S8 | Denied permission gives a clear recovery path, never a crash | `PermissionTests` (7 cases); `RecordingSetupView` branches on notDetermined / denied / restricted | Written, never run | `STATICALLY_REVIEWED` → `REQUIRES_MAC` | UAT 2, 3 |
| S9 | An interrupted recording is finished safely or reported — never silently lost | `InterruptionTests` (6 cases); partial file path preserved | Written, never run | `STATICALLY_REVIEWED` → `REQUIRES_PHYSICAL_DUO` for fold-driven interruption | Real interruptions need a phone call on a device |
| S10 | No empty or broken secondary UI on a device without an accessory | `FallbackTests` (3 cases); `.unsupported` hides controls entirely; a spurious callback cannot override it | Written, never run | `STATICALLY_REVIEWED` → `REQUIRES_MAC` | UAT 5 |
| S11 | Subject surface shows question, countdown, status, and no director-only content | `SubjectSurfaceTests` (7 cases) | Written, never run | `REQUIRES_DUO_SIMULATOR` then `REQUIRES_PHYSICAL_DUO` | The privacy half is structural; the display half is unproven |
| S12 | Accessory appearing/disappearing mid-session does not end the recording | `AccessoryAvailabilityTests` (4 cases) assert state stays `.recording` | Written, never run | `STATICALLY_REVIEWED` → `REQUIRES_PHYSICAL_DUO` | UAT 13 |
| S13 | Controls reachable and readable across orientation, size class, Dynamic Type | Size-class layout + `ViewThatFits` + relative type styles + 44 pt targets | Reviewed only | `REQUIRES_MAC` | UAT 11 |
| S14 | Subject surface readable at 1–2 m | Measurement | None | `REQUIRES_PHYSICAL_DUO` | Must be measured, not asserted |
| S15 | Duo inner/outer split works on iPhone Duo | Device test | None | `REQUIRES_PHYSICAL_DUO` | **The headline claim. Entirely unproven.** |

---

## D. Required automated test coverage

All 23 areas the brief requires. Every row is `STATICALLY_REVIEWED` and
`REQUIRES_MAC` to execute, because no Swift toolchain is reachable here (A3).

| # | Area | Where | Cases |
|---|---|---|---|
| 1 | Deck creation, editing, deletion, ordering | `DeckTests` | 11 |
| 2 | Persistence and reload | `DeckPersistenceTests` | 5 |
| 3 | Recording state transitions | `RecordingStateMachineHappyPathTests` | 3 |
| 4 | Invalid state transitions | `RecordingStateMachineRejectionTests` | 9 |
| 5 | Countdown cancellation | `CountdownCancellationTests` | 4 |
| 6 | Question navigation during recording | `QuestionNavigationTests` | 6 |
| 7 | Timestamp marker accuracy | `MarkerTests` | 7 |
| 8 | Permission denial | `PermissionTests` | 7 |
| 9 | Camera initialisation failure | `CaptureFailureTests` | 1 |
| 10 | Microphone initialisation failure | `CaptureFailureTests` | 1 |
| 11 | Recording interruption | `InterruptionTests` | 6 |
| 12 | Save failure | `SaveIntegrityTests` | 8 |
| 13 | Export failure | `ExportFailureTests` | 3 |
| 14 | Accessory becoming available | `AccessoryAvailabilityTests` | 1 |
| 15 | Accessory disappearing while active | `AccessoryAvailabilityTests` | 3 |
| 16 | Outer display receiving synchronised question state | `SubjectSurfaceTests` | 2 |
| 17 | Duo capability unavailable | `FallbackTests` | 2 |
| 18 | Ordinary iPhone fallback | `FallbackTests` | 3 |
| 19 | App backgrounding during recording | `InterruptionTests` | 2 |
| 20 | Repeated tapping of record / stop | `RecordingStateMachineRejectionTests` | 2 |
| 21 | Prevention of false success after a failed save | `SaveIntegrityTests` | 4 |
| 22 | Deterministic clock available | `ManualSessionClock` + all timing tests | — |
| 23 | Test doubles for camera, audio, storage, accessory | `TestDoubles.swift` | 7 doubles |

**112 declared `@Test` cases across 6 files. Zero executed.**

---

## E. Privacy and safety requirements

| # | Requirement | Method | Evidence | Result |
|---|---|---|---|---|
| E1 | Everything local; no upload | No networking code exists in either layer; no analytics or third-party SDK; `Package.swift` has zero dependencies | Reviewed | `VERIFIED_LINUX` (absence of network code) |
| E2 | Accurate privacy usage descriptions | `project.yml` `NSCameraUsageDescription` / `NSMicrophoneUsageDescription`, specific and stating data stays on device | Reviewed | `STATICALLY_REVIEWED` → `REQUIRES_MAC` |
| E3 | Recording state communicated clearly | `RecordingStatusBadge` shared by both surfaces via one `Theme.presentation(for:)` | Reviewed | `REQUIRES_MAC` |
| E4 | System privacy indicators never bypassed | No attempt to suppress them; nothing in Platform/ touches them | Reviewed | `VERIFIED_LINUX` (absence) |
| E5 | Interruptions handled | `AVCaptureSession.wasInterruptedNotification`, `runtimeErrorNotification`, `AVAudioSession.interruptionNotification` mapped to `InterruptionReason` | Reviewed | `STATICALLY_REVIEWED` → `REQUIRES_MAC` |
| E6 | Incomplete files never presented as valid | `RecordingOutcome.isPlayable` is the sole playback gate; `playbackURL` also requires the file to exist | Reviewed + tested | `STATICALLY_REVIEWED` → `REQUIRES_MAC` |
| E7 | Safe temporary-file handling | Capture to `Captures/`, move into `Recordings/` only on confirmation | Reviewed | `STATICALLY_REVIEWED` → `REQUIRES_MAC` |
| E8 | Failed/abandoned temporary captures cleaned up | `cleanUpAbandonedTemporaryFiles`, called before a take, never during; cannot reach `Recordings/` | Reviewed + tested | `STATICALLY_REVIEWED` → `REQUIRES_MAC` |
| E9 | A captured file survives a later failure | `store` never deletes on move failure; path recorded in `preservedFilePath`; surfaced in the UI | Reviewed + tested | `STATICALLY_REVIEWED` → `REQUIRES_MAC` |
| E10 | No recording silently deleted | Library delete removes the row only, never the file | Reviewed | `STATICALLY_REVIEWED` → `REQUIRES_MAC` |
| E11 | No camera kept alive to unlock outer-screen behaviour | `tearDown()` on close; no such coupling exists | Reviewed | `VERIFIED_LINUX` (absence) |
| E12 | No private APIs | Static review symbol list; all APIs are public Apple surface | Reviewed | `VERIFIED_LINUX` (absence) |

---

## F. App Store readiness

| # | Requirement | Result | Note |
|---|---|---|---|
| F1 | Builds for device | `REQUIRES_MAC` | Never compiled |
| F2 | Signing configured | `REQUIRES_MAC` | `DEVELOPMENT_TEAM` intentionally blank |
| F3 | App Store Review Guidelines reviewed | `BLOCKED` | Not fetched; a founder task |
| F4 | Privacy manifest / nutrition label | `REQUIRES_MAC` | Answer: no data collected. No third-party SDK, so no `PrivacyInfo.xcprivacy` required, but confirm against current rules |
| F5 | Screenshots, marketing copy | `BLOCKED` | Must not claim Duo behaviour until S15 is verified |
| F6 | Duo behaviour claims in listing | `REQUIRES_PHYSICAL_DUO` | **Do not claim what S15 has not proven** |
