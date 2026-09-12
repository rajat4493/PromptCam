# PromptCam — Engineering Handover

**Status:** `STATICALLY_REVIEWED`. Never compiled. See
`docs/VERIFICATION_LEDGER.md` before trusting any claim here.

---

## 1. Architecture overview

Two layers, with a hard boundary between them.

```
PromptCam/
├── Package.swift                 SPM package: PromptCamCore only
├── project.yml                   XcodeGen spec for the iOS app (never run)
├── Scripts/static_review.py      Executable invariant checks (passing)
├── Sources/
│   ├── PromptCamCore/            Foundation only. No Apple framework.
│   │   ├── Model/                DeckModel, QuestionModel, recording models
│   │   ├── Session/              RecordingState, state machine, engine, snapshots
│   │   ├── Services/             Protocols: capture, permissions, store, repos, clock
│   │   ├── Export/               MarkerExporter (CSV + text)
│   │   └── Support/              FeatureFlags, DeviceCapabilities
│   └── PromptCamiOS/             SwiftUI, AVFoundation, SwiftData, AVKit
│       ├── Platform/             ⚠ ALL unverified Apple API lives here
│       ├── Capture/              AVFoundationCaptureService, RecordingFileStore
│       ├── Persistence/          SwiftData models + repositories
│       ├── DirectorSession/      Operator console + orchestrator
│       ├── SubjectDisplay/       SubjectPromptView
│       ├── Decks/ RecordingSetup/ Recordings/ Permissions/ DesignSystem/
│       └── App/                  Entry point, RootView, AppEnvironment
└── Tests/PromptCamCoreTests/     112 cases, 7 test doubles
```

**Why the split is this strict.** `PromptCamCore` compiles and tests with no
Apple SDK, so on a machine with any Swift toolchain the business rules can be
verified without a simulator, a device, or Xcode. That was not hypothetical
here: it is the only layer that *could* have been trusted, had a Swift compiler
been reachable at all.

`Scripts/static_review.py` enforces the boundary: 11 forbidden module imports
in Core, and 12 unverified Duo symbols permitted only under `Platform/`.

---

## 2. Important modules

| Module | Responsibility | Notes |
|---|---|---|
| `RecordingStateMachine` | The only place a recording state may change | One exhaustive transition table; `nil` means illegal |
| `InterviewSessionEngine` | Owns state, question cursor, countdown, timeline, accessory availability | Synchronous value type; no I/O |
| `DirectorSessionModel` | Async orchestration only — timers, capture stream, file moves, persistence | Contains **no** business rules |
| `AVFoundationCaptureService` | Camera, microphone, file output, interruptions, level metering | `recordingFinished` originates in exactly one delegate callback |
| `RecordingFileStore` | Temp → permanent file movement | Never deletes on failure |
| `Platform/*` | Every unconfirmed Apple symbol | Behind `PROMPTCAM_DUO`, off by default |
| `SubjectSnapshot` | The entire subject-surface contract | Cannot carry director data |
| `MarkerExporter` | CSV (RFC 4180) and plain text | Pure functions |

---

## 3. State ownership

One owner per piece of state. No duplication, so nothing can disagree.

| State | Owner | Read by |
|---|---|---|
| Recording state | `RecordingStateMachine` inside the engine | Both surfaces, via the engine |
| Current question index | `InterviewSessionEngine` | Both surfaces |
| Countdown remaining | Encoded in `RecordingState.countdown(remaining:)` | Both surfaces |
| Duration | Derived: `clock.now - captureStartedAt`, frozen at terminal states | Director only |
| Markers / question changes | `InterviewSessionEngine` | Export, library |
| Accessory availability | `InterviewSessionEngine`, set **only** from system callbacks | Director UI |
| Audio level | `InterviewSessionEngine`, fed by capture events | Director only |
| Decks | SwiftData, via `DeckRepository` | `DeckLibraryModel` |
| Recordings | SwiftData, via `RecordingRepository` | `RecordingsLibraryModel` |

**The director/subject synchronisation design.** There is no message passing and
no mirroring. Both surfaces render from the same `InterviewSessionEngine`
instance — the director from the engine directly, the subject from
`engine.subjectSnapshot()`. Synchronisation is therefore a consequence of there
being one copy of the data, not a feature that can drift.

---

## 4. Data model

**Core (value types, `Codable`, `Sendable`):** `DeckModel` (array order *is* the
question order), `QuestionModel`, `InterviewRecordingModel`, `MarkerModel`,
`QuestionChangeModel`, `RecordingOutcome`.

**Persistence (SwiftData `@Model`):** `StoredDeck`, `StoredQuestion`,
`StoredRecording`, `StoredMarker`, `StoredQuestionChange`.

Three deliberate choices:

1. **`StoredQuestion.order` is explicit.** SwiftData does not guarantee to-many
   relationship ordering across a reload, so array position alone is not
   trustworthy. `toModel()` sorts by `order`.
2. **`outcomeRaw` is a `String`.** An unrecognised value degrades to `.failed`,
   which is not playable — failing in the safe direction.
3. **Deck name is copied into the recording, not referenced.** Renaming or
   deleting a deck cannot corrupt interview history.

---

## 5. Camera and audio design

Capture is a protocol (`CaptureService`) emitting an `AsyncStream<CaptureEvent>`.
The engine never touches AVFoundation.

**The save-integrity chain, which is the point of the whole design:**

```
AVCaptureMovieFileOutput
  → fileOutput(_:didFinishRecordingTo:from:error:)   ← the ONLY origin
  → CaptureEvent.recordingFinished(path:duration:)
  → DirectorSessionModel.finishRecording
  → RecordingFileStore.store(temporaryPath:startedAt:)   ← may throw
  → engine.confirmSaved(fileName:duration:)               ← only on success
  → RecordingEvent.saveConfirmed
  → RecordingState.saved                                  ← the only route
```

Each arrow is the only path to the next. A save cannot be claimed early because
there is no other edge into `.saved`.

`AVError.recordingSuccessfullyFinishedKey` is honoured: AVFoundation sometimes
reports an error alongside a genuinely complete file, and that case is treated
as success. Anything else is a failure — and the file is left on disk.

**Audio metering** reads `AVCaptureAudioChannel.averagePowerLevel` from the
movie output's audio connection on a 100 ms timer, mapped from a −60…0 dB window
to 0…1. It is only meaningful while the session runs, so the meter greys out
when not recording rather than showing a stale level.

**Interruptions** map from `AVCaptureSession.wasInterruptedNotification`
(including `audioDeviceInUseByAnotherClient`,
`videoDeviceNotAvailableInBackground`, `…DueToSystemPressure`),
`runtimeErrorNotification`, and `AVAudioSession.interruptionNotification`.

`interruptionEnded` deliberately does **not** auto-resume. Restarting capture
unasked would produce a second file the operator never saw begin.

---

## 6. Inner/outer display synchronisation

See §3 — the short answer is that there is nothing to synchronise.

The accessory is declared with `.promptCamSubjectAccessory(...)` in
`DirectorSessionView`, which resolves to either the supplied
`CameraCaptureAccessory` (with `PROMPTCAM_DUO`) or an explicit no-op that
renders nothing and reports unavailable.

Availability has four states (`SubjectDisplayAvailability`): `.unsupported`,
`.unavailable`, `.availableNotEnabled`, `.presented`. `.unsupported` is distinct
from `.unavailable` on purpose — it is what hides Duo-only controls *entirely*
rather than showing them disabled, and `updateSubjectAvailability` refuses to
leave `.unsupported` on a device whose capabilities say the accessory is not
supported, so a spurious callback cannot light up controls that cannot work.

**Accessory loss never changes recording state.** Asserted by
`accessoryDisappearsWhileRecording`.

---

## 7. Failure-handling strategy

| Failure | Behaviour |
|---|---|
| Permission denied | Resolved on the setup screen before the camera opens; per-status recovery (`denied` → Settings, `restricted` → explain it cannot be changed) |
| Camera init failure | `.failed(.cameraUnavailable)`, reported distinctly from the microphone |
| Microphone init failure | `.failed(.microphoneUnavailable)` |
| Mid-recording failure | `.failed(.captureFailed)`, partial file left on disk |
| Interruption | `.interrupted(reason:)`, partial file path preserved, no auto-resume |
| Save failure | `.failed(.saveFailed(reason:preservedPath:))`, **file never deleted**, path surfaced in the UI |
| Export failure | Reported; the recording is untouched and stays playable |
| Library write failure | Alert distinguishes "the video was saved" from "check the recordings folder" |
| Storage unopenable | Falls back to in-memory with a persistent yellow banner; total failure shows `StorageFailureView` rather than crashing |
| Double-tap record/stop | Rejected at two levels: the UI asks `engine.canApply`, and the engine throws |

**Invariants:**

- No recording is silently deleted. `Captures/` is swept; `Recordings/` and
  `Recovery/` are not, and anything the app promises to keep is moved into
  `Recovery/` first. The sweeper additionally skips in-use paths and anything
  newer than an hour.
- No incomplete file is presented as valid. `RecordingOutcome.isPlayable` is
  the sole playback gate, and `playbackURL` additionally requires the file to
  exist.
- **One idempotent finalisation path.** `finalise` is guarded by `hasFinalised`
  and switches on engine state; a file arriving after the session ended is
  reconciled, never confirmed as a save. `attachRecoveredFile` refuses to run
  on a saved or in-flight session, so it cannot become a route to a false save.
- **A stop is never lost.** If it arrives before capture is confirmed it is
  queued until `.recordingStarted`; a watchdog fails the session if capture
  never starts, rather than leaving it in `.finishing`.
- Every terminal outcome is persisted under a stable identifier, and the
  repository upserts, so reconciliation updates one row instead of duplicating
  the interview.

---

## 8. Test strategy

112 `@Test` cases in 6 files, Swift Testing. **Never executed** (no toolchain).

Seven test doubles: `FakeCaptureService`, `FakePermissionService`,
`InMemoryDeckRepository`, `InMemoryRecordingRepository`, `TestRecordingStore`
(real temp directory, injectable failure), `FakeSubjectDisplayObserver`,
`ManualSessionClock`.

`ManualSessionClock` is what makes timing deterministic: advance 12.5 s and the
marker offset must be exactly 12.5. No test sleeps.

`TestRecordingStore` writes real files, so "a failed save must not delete the
capture" is asserted against the file system rather than a mock.

`Scripts/static_review.py` is the second, complementary layer: it checks the
things a unit test cannot see — layer purity, symbol isolation, absence of
device detection, bracket balance, and absence of false verification claims.

---

## 9. Known limitations

1. **Nothing has been compiled.** The single most important fact here.
2. **The Duo API surface is unconfirmed.** All of it, isolated in five files.
3. **`AVCaptureDeviceDirectionCoordinator` is not implemented** — a documented
   placeholder returning `false`. Five unknowns, and the rear-camera workflow
   does not need it.
4. **Live subject preview is off** and stripped at the engine boundary.
5. **No hinge-driven layout.** By design, per the supplied guidance.
6. **`project.yml` has never been run through XcodeGen.**
7. **The bracket checker is not a parser** — it cannot find a balanced-but-wrong
   brace.
8. **No background recording.** Backgrounding is an interruption, deliberately.
9. **No Photos-library write.** Export is via the share sheet, so no
   `NSPhotoLibraryAddUsageDescription` is needed and no Photos permission can
   fail. Add it only if in-app saving to Photos is wanted.
10. **Audio metering needs a running session**, so there is no pre-roll level
    check before recording starts.
11. **`Recovery/` is never swept automatically.** Files accumulate until the
    user shares them out or deletes the app. That is the deliberate trade — the
    alternative is the R1 defect, where cleanup deleted interviews.
12. **The app icon is programmatically generated**, not designed. Replace it.

---

## 10. Configuration requirements

| Setting | Value | Where |
|---|---|---|
| Swift version | 6.0, strict concurrency `complete` | `project.yml`, `Package.swift` |
| Deployment target | iOS 26.0 | `project.yml` |
| Build SDK | iOS 27.1 (Xcode 27.1) | Toolchain |
| Device family | iPhone + iPad (`1,2`) | `project.yml` |
| Orientations | Portrait + both landscapes | `project.yml` |
| Configurations | `Debug`, `Duo`, `Release` | `project.yml` |
| Schemes | **PromptCam** (baseline) and **PromptCam (Duo)** | `project.yml` |
| `PROMPTCAM_DUO` | set in the `Duo` configuration only | `SWIFT_ACTIVE_COMPILATION_CONDITIONS` |
| `PROMPTCAM_USE_ARRANGEMENT_VIEW` | off | Same, additionally requires `PROMPTCAM_DUO` |
| Dependencies | **none** | `Package.swift` has zero |

Deployment target is 26.0 rather than 27.x so the ordinary-iPhone app installs
on phones that have not upgraded; the Duo paths are gated at runtime with
`#available`.

---

## 11. Signing requirements

- Both live in **`Support/Signing.xcconfig`**, wired through `configFiles` for
  all three configurations, so neither requires editing `project.yml`.
- `DEVELOPMENT_TEAM` is intentionally **empty** — a committed team identifier
  breaks every other developer's build. Keep your edit out of git with
  `git update-index --skip-worktree Support/Signing.xcconfig`.
- Bundle identifier is `com.example.promptcam.PromptCam`, a placeholder that
  **cannot be registered with Apple** and must be changed before a device build.
- `CODE_SIGN_STYLE: Automatic`.
- No entitlements file. PromptCam needs no capability beyond the Info.plist
  privacy strings: no background modes, no App Groups, no iCloud, no push.

---

## 12. Build and test commands

```bash
# Core tests — no simulator, no device, no Xcode project needed
swift test

# Architectural invariants — runs anywhere with Python 3
python3 Scripts/static_review.py

# Generate and open the iOS project (Mac, Xcode 27.1)
brew install xcodegen
xcodegen generate
open PromptCam.xcodeproj

# Build for a simulator
xcodebuild -project PromptCam.xcodeproj -scheme PromptCam \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build

# Confirm the supplied accessory API exists (10 seconds, high value)
# — full script in docs/MAC_VALIDATION.md step 2
xcrun swiftc -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -target arm64-apple-ios27.0 -typecheck /tmp/probe.swift
```

---

## 13. Physical-device test plan

**Ordinary iPhone first** — the simulator has no camera, so it cannot exercise
capture, audio levels, or interruptions at all.

| Priority | What | UAT case |
|---|---|---|
| 1 | Record, save, play back | 5 |
| 2 | **No false "saved"** | 17 |
| 3 | Save failure preserves the file | 16 |
| 4 | Interruption by a phone call | 10 |
| 5 | Marker timestamp accuracy against a stopwatch | 9 |
| 6 | Permission denial and recovery | 2, 3 |
| 7 | Export video and markers | 15 |
| 8 | Rotation, Dynamic Type, VoiceOver, Reduce Motion | 11 |

**Second display next** — try an external display or AirPlay before waiting for
Duo hardware, since the underlying API is documented for exactly that.

| Priority | What | UAT case |
|---|---|---|
| 1 | Availability fires with an active capture session | 6, and `MAC_VALIDATION.md` step 13 |
| 2 | Question, countdown and status appear; nothing director-only does | 7 |
| 3 | Readability at 1 m and 2 m — **measured** | 7 |
| 4 | Accessory removed mid-recording; take survives | 13 |

**Physical iPhone Duo last** — and until it happens, S14 and S15 stay
`REQUIRES_PHYSICAL_DUO` and the App Store listing must not claim Duo behaviour.

| Priority | What | UAT case |
|---|---|---|
| 1 | Folding mid-recording does not tear down capture (**highest-risk unknown**) | 12 |
| 2 | Controls clear of the hinge in every pose | 12 |
| 3 | Inner/outer split end to end | 6, 7 |
| 4 | Whether a live preview is possible at all | 16, and step 17 |

---

## 14. App Store preparation checklist

- [ ] Apple Developer Program membership
- [ ] `DEVELOPMENT_TEAM` set in `Support/Signing.xcconfig`
- [ ] Bundle identifier changed from `com.example.promptcam.*` in the same file
- [ ] Version and build number set (currently 0.1.0 / 1)
- [x] App icon — `Sources/PromptCamiOS/Assets.xcassets/AppIcon.appiconset`, generated by `Scripts/make_app_icon.py` (replace with a designed mark when you have one)
- [ ] Launch screen — currently the `UILaunchScreen` default
- [ ] Release build succeeds and is archivable
- [ ] Privacy usage strings reviewed for accuracy
- [ ] Privacy questionnaire: **no data collected** — zero dependencies, no
      networking code
- [ ] `PrivacyInfo.xcprivacy` — likely unnecessary with no third-party SDKs;
      confirm against current rules
- [ ] Screenshots taken on real devices
- [ ] App Store Review Guidelines read for camera use, recording indicators and
      external-display behaviour (**currently `BLOCKED` — not fetched**)
- [ ] `docs/UAT.md` cases 1–5, 8–11, 14–17 passing on a physical iPhone
- [ ] `docs/VERIFICATION_LEDGER.md` updated with real results at the correct tier
- [ ] **Listing copy does not claim iPhone Duo behaviour unless S15 is verified
      on a physical iPhone Duo**
