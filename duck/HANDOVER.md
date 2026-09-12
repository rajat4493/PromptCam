# Handover

Full engineering detail: [`../docs/ENGINEERING_HANDOVER.md`](../docs/ENGINEERING_HANDOVER.md).
First-build sequence: [`../docs/MAC_VALIDATION.md`](../docs/MAC_VALIDATION.md).

## The shape of it

```
PromptCamCore   Foundation only. Models, recording state machine, session
  (15 files)    engine, export, service protocols. Testable with no Apple SDK.
       ▲ protocols only
       ▼
PromptCamiOS    SwiftUI, AVFoundation, SwiftData, AVKit.
  (25 files)    Platform/ holds every unconfirmed Apple API, behind
                PROMPTCAM_DUO and the `Duo` build configuration.
```

`Scripts/static_review.py` fails if that boundary is crossed, so the separation
is enforced rather than merely intended.

## Three things to understand before changing anything

**1. `.saved` has exactly one inbound edge.** `.finishing --saveConfirmed-->`,
and the only origin of that event is AVFoundation's `didFinishRecordingTo`
callback. If you add another route into `.saved`, you have removed the
guarantee that the app never lies about saving an interview.

**2. There is one finalisation path, and it is idempotent.**
`DirectorSessionModel.finalise` is guarded by `hasFinalised` and switches on
engine state. A file that arrives *after* the session ended is reconciled — the
file is preserved and attached to the existing library row — never confirmed as
a save. This is what fixes the interruption-orphan defect; do not add a second
path that stores or confirms.

**3. Files worth keeping leave the capture directory.** `Captures/` is swept
(old, unreferenced files only). `Recordings/` and `Recovery/` never are.
Anything the app promises to keep must be moved into `Recovery/` via
`preserveForRecovery`, or the next session's cleanup will be entitled to delete
it — which is exactly the bug that review found.

## State ownership

One owner each, no duplication. Recording state lives in
`RecordingStateMachine` inside `InterviewSessionEngine`; so do the question
cursor, countdown, marker timeline and accessory availability. Duration is
derived from the injected clock. Decks and recordings live in SwiftData behind
`async` repository protocols.

Both surfaces render from the same engine — the director directly, the subject
from `engine.subjectSnapshot()`. There is no message passing to drift.

## Where the risk is concentrated

`Sources/PromptCamiOS/Platform/` — five files, every unconfirmed Apple symbol,
each marked `REQUIRES_MAC_VALIDATION`:

| File | Confirm |
|---|---|
| `DuoSubjectAccessory.swift` | `CameraCaptureAccessory` module, initialiser, conformance, availability |
| `DuoReservedRegionLayout.swift` | `reservedRegions(kind:)`, `.division`/`.occlusion`, `.frame`, `ArrangementView` |
| `DuoHingeObserver.swift` | `onHingeChange` shape, `hinge.status` cases, `hinge.angle` type |
| `CameraDirectionAdapter.swift` | Duo device-type spellings; `AVCaptureDeviceDirectionCoordinator` (not implemented — five unknowns documented in-file) |
| `DuoCapabilityProvider.swift` | the real availability floor |

Record every answer in [`../docs/APPLE_API_CORRECTIONS.md`](../docs/APPLE_API_CORRECTIONS.md)
— 20 questions pre-filled.

## Commands

```bash
swift test                          # Core tests. No simulator, no device
python3 Scripts/static_review.py    # Architectural invariants
xcodegen generate                   # Never yet run — expect to fix the spec
```

Schemes: **PromptCam** (baseline, Duo-free) and **PromptCam (Duo)**. Get the
baseline green *first*; the ordering exists so one wrong Duo signature cannot
block validating the rest of the app.

## Known limitations

Nothing compiled. Duo API surface unconfirmed. Direction coordinator not
implemented. Live subject preview off. No hinge-driven layout (by design).
`project.yml` never run. The bracket checker is not a parser. No background
recording (backgrounding is an interruption, deliberately). No Photos-library
write — export is via the share sheet. Audio metering needs a running session,
so there is no pre-roll level check.

## Configuration

Swift 6, strict concurrency `complete`. Deployment target iOS 26.0, build with
the iOS 27.1 SDK. iPhone + iPad. Zero dependencies.

Signing: `DEVELOPMENT_TEAM` is blank on purpose — a committed team identifier
breaks every other developer's build. Copy `Support/Signing.xcconfig.example`
to `Support/Signing.xcconfig` (git-ignored) and set your team and bundle
identifier there.
