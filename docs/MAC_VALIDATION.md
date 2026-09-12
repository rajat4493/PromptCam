# PromptCam — Mac Validation Handover

**Who this is for:** the person with a Mac. Follow it in order — the sequence
matters, because steps 1–7 establish a clean baseline before step 8 introduces
the unverified iPhone Duo APIs. Doing it the other way round means one wrong
API signature blocks you from validating anything else.

**Before you start, understand the honest position:** nothing in this
repository has ever been compiled. It was written on Linux where no Apple
toolchain and no Swift toolchain were available, and the Swift download hosts
were blocked by network policy. Expect compiler errors, particularly in the
five files under `Sources/PromptCamiOS/Platform/`. That is the expected
outcome, not a failure — those files exist to concentrate the uncertainty in
one place.

Record every correction in **`docs/APPLE_API_CORRECTIONS.md`** as you go.

---

## Step 1 — Install or open Xcode 27.1 or later

```bash
xcodebuild -version
```

Expected: `Xcode 27.1` or higher.

- If you have an older Xcode, get 27.1 from the Mac App Store or
  <https://developer.apple.com/download/>.
- **If Xcode 27.1 does not exist yet:** stop and record that. As of 2026-09-12
  Apple's published release notes listed **Xcode 27 RC** as the newest version,
  with no 27.1. If only 27 RC is available, you can still do steps 1–7 and 18;
  steps 8–17 wait.

## Step 2 — Confirm the iOS 27.1 SDK

```bash
xcodebuild -showsdks | grep -i ios
xcrun --sdk iphoneos --show-sdk-version
```

Expected: an iOS 27.1 SDK. Write down the exact version you actually have.

**Ten-second check that settles the biggest open question.** Before touching
the project, confirm whether the supplied accessory API exists at all:

```bash
cat > /tmp/probe.swift <<'SWIFT'
import SwiftUI

@available(iOS 27.0, *)
func probeSupplied(_ enabled: Binding<Bool>) -> some View {
    Text("x").sceneAccessory {
        CameraCaptureAccessory(isEnabled: enabled) { Text("subject") }
            .onAvailabilityChange { _ in }
    }
}

@available(iOS 27.0, *)
func probeDocumented(_ enabled: Binding<Bool>) -> some View {
    Text("x").sceneAccessory {
        ExternalNonInteractiveAccessory(isEnabled: enabled) { Text("subject") }
            .onAvailabilityChange { _ in }
    }
}
SWIFT

xcrun swiftc -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -target arm64-apple-ios27.0 -typecheck /tmp/probe.swift
```

- Both functions compile → excellent. `CameraCaptureAccessory` is real; proceed
  as designed.
- Only `probeDocumented` compiles → `CameraCaptureAccessory` does not exist
  under that name. Switch `DuoSubjectAccessory.swift` to
  `ExternalNonInteractiveAccessory`, which is already documented in that file as
  the fallback. Record it.
- Neither compiles → record it, and find the real symbol in Xcode's
  documentation before changing any code.

## Step 3 — Generate and open the project

```bash
brew install xcodegen        # if not already installed
cd /path/to/PromptCam
xcodegen generate
open PromptCam.xcodeproj
```

`project.yml` has never been run through XcodeGen. If generation fails, fix the
spec rather than hand-building a `.xcodeproj`.

## Step 4 — Select your development team

Xcode → target **PromptCam** → **Signing & Capabilities** → **Team**.

`DEVELOPMENT_TEAM` is deliberately blank in `project.yml`; a committed team
identifier would break every other developer's build. Set it in Xcode, or add it
to `project.yml` locally without committing.

## Step 5 — Check the bundle identifier

Default: `com.example.promptcam.PromptCam`.

Change it to your own reverse-DNS identifier before any device build or TestFlight
upload. Update both `options.bundleIdPrefix` and
`targets.PromptCam.settings.base.PRODUCT_BUNDLE_IDENTIFIER`, then re-run
`xcodegen generate`.

## Step 6 — Build for an ordinary iPhone simulator

This is the baseline. `PROMPTCAM_DUO` is off, so no Duo API is referenced.

```bash
xcodebuild -project PromptCam.xcodeproj -scheme PromptCam \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build
```

Expect errors on the first attempt. Likely areas, in rough order of probability:

| Area | What to look at |
|---|---|
| SwiftUI API drift | `Tab(_:systemImage:value:)` in `RootView`, `ContentUnavailableView`, `ViewThatFits`, `.rect(cornerRadius:)` shorthand, `navigationDestination(item:)` |
| SwiftData macros | `#Index` in `PersistenceModels.swift`, `#Predicate` closures in `SwiftDataRepositories.swift` |
| Strict concurrency | `SWIFT_STRICT_CONCURRENCY: complete` is on. `AVFoundationCaptureService` is `@unchecked Sendable` with a serial queue; expect isolation warnings around the delegate callbacks |
| `@Observable` + `@State` | `DirectorSessionModel` etc. are injected via `State(initialValue:)` |
| Async asset loading | `asset.load(.duration)` in `emitFinished` |

Fix and re-run until the build is clean. **Do not proceed to step 8 until it is.**

## Step 7 — Run the unit tests

`PromptCamCore` is a plain Swift package with no Apple-platform dependency, so
its tests run without a simulator:

```bash
swift test
```

Expect 112 test cases across 6 files, **none of which has ever been executed**.
Anticipate:

- Swift Testing availability — the tests `import Testing`. If your toolchain
  lacks it, either update or convert to XCTest.
- `await #expect(throws:)` usage in the async tests.
- `IndexSet`/`move(fromOffsets:toOffset:)` semantics in the reorder tests.

Once green, record the pass count in `VERIFICATION_LEDGER.md` — replacing
`STATICALLY_REVIEWED` with the real result for rows S1, S3–S8, S10, S12 and
section D. **Do not mark anything `VERIFIED` that the test run did not cover.**

## Step 8 — Enable the Duo code paths

In `project.yml`:

```yaml
targets:
  PromptCam:
    settings:
      configs:
        Debug:
          SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG PROMPTCAM_DUO
```

Then `xcodegen generate` and build again. Everything that breaks now is in
`Sources/PromptCamiOS/Platform/` by design. Work through the five files:

| File | Confirm |
|---|---|
| `DuoSubjectAccessory.swift` | `CameraCaptureAccessory` exists; module; `init(isEnabled:content:)`; conformance required by `sceneAccessory(content:)`; real `@available` |
| `DuoReservedRegionLayout.swift` | `GeometryProxy.reservedRegions(kind:)`; `.division` / `.occlusion`; `.frame` on each region; whether `.includeInactive` is needed |
| `DuoHingeObserver.swift` | `onHingeChange` modifier name; two-argument closure; `currentContext.hinge` optionality; `hinge.status` cases; `hinge.angle` type |
| `CameraDirectionAdapter.swift` | `.builtInOuterUltraWideCamera`, `.builtInInnerUltraWideCamera` spellings and availability |
| `CameraDirectionAdapter.swift` | `AVCaptureDeviceDirectionCoordinator`: type name, initialiser labels, handler parameter type, actor isolation, availability. **Intentionally not implemented** — five steps to complete it are in the file |

## Step 9 — Open Device Hub

Xcode → **Window ▸ Devices and Simulators**, or Device Hub if 27.1 relocates it.

If you cannot find it, record that in `APPLE_API_CORRECTIONS.md` — "Device Hub"
does not appear in Apple's published documentation, so its exact location is
unconfirmed.

## Step 10 — Create or select an iPhone Duo simulator

```bash
xcrun simctl list devicetypes | grep -i -E 'duo|fold'
```

- Found → create the simulator and continue.
- Not found → mark UAT 6 and 12 `BLOCKED`, and note that every Duo claim now
  depends on physical hardware.

## Step 11 — Test closed, open, rotated and partially folded poses

For each pose, on the director screen, check:

1. The record button is fully visible and tappable, and does not cross the hinge.
2. Question navigation buttons are reachable.
3. The timer and audio meter are readable.
4. Nothing is clipped by an asymmetric safe-area inset.
5. The layout switches between side-by-side and stacked as size classes change.

`DirectorSessionView` drives this from `horizontalSizeClass` /
`verticalSizeClass` plus `ReservedRegionReader`, with no hardcoded dimension.
If the record button lands on a hinge, fix
`bottomInsetAvoidingReservedRegions` — not the theme.

## Step 12 — Confirm the actual `CameraCaptureAccessory` API signature

Already probed in step 2; now confirm it in context, compiling inside the app
rather than in isolation. Record the final working declaration verbatim in
`APPLE_API_CORRECTIONS.md`.

## Step 13 — Confirm accessory availability with an active camera session

The supplied guidance says availability requires the app to be full-screen on
the inner display **and** to have an active camera-capture session.

1. Open PromptCam, pick a deck, reach the director screen (camera running).
2. Watch for `availabilityChanged(true)` — the "Subject screen" toggle appears
   in the question panel when it fires.
3. Now test the negative: before the camera starts (on the setup screen), the
   toggle must **not** appear.

If availability never becomes true with a running session, record it. That result
would put S11 and S15 in serious doubt and is worth escalating immediately.

## Step 14 — Confirm the subject question appears on the outer display

1. Enable the "Subject screen" toggle.
2. Confirm the outer display shows the current question, large and high contrast.
3. Move to the next question; confirm the outer display follows.
4. Start recording; confirm the countdown then the recording status appear.
5. **Confirm what is NOT there:** no upcoming question, no deck name, no
   controls, no timer, no marker count.

Item 5 is the privacy requirement. `SubjectSnapshot` cannot structurally carry
that data, so a failure here would mean someone added a field to it.

## Step 15 — Disable or remove the accessory during a recording

While recording, either toggle "Subject screen" off or disconnect the display.

**Required behaviour:** recording continues. The director timer keeps running.
Markers still work. Question navigation still works. The take still saves.

`AccessoryAvailabilityTests` asserts exactly this in the engine
(`accessoryDisappearsWhileRecording`). Step 15 confirms it end to end.

## Step 16 — Confirm the director session continues safely

Immediately after step 15, without restarting:

1. Add a marker → count increments.
2. Move to the next question.
3. Stop recording.
4. Confirm the interview appears in the library marked **Saved**, and plays.
5. Confirm the marker export contains the markers added after the accessory
   disappeared.

## Step 17 — Verify whether a custom live preview is possible

Currently `FeatureFlags.subjectLivePreviewEnabled = false`, and the option is
stripped at the engine boundary so it cannot reach the view.

To test:

1. Set `subjectLivePreviewEnabled: true` in `FeatureFlags.default`.
2. Add an `AVCaptureVideoPreviewLayer` (via `CameraPreviewView`) inside
   `SubjectPromptView.livePreviewPlaceholder`.
3. Observe whether it renders, and at what frame rate and thermal cost while
   also recording.

Outcomes:

- **Renders acceptably** → keep it, set the flag, update the ledger, remove the
  placeholder.
- **Does not render, or costs too much** → revert to `false`. The product is
  still valid; the question and recording cues are the differentiated
  functionality. Record the result so nobody retries it blind.

**Do not ship this enabled on the strength of a simulator.** It needs a
physical device.

## Step 18 — Test on a physical ordinary iPhone

The Simulator has no camera, so this is the first real test of capture. Work
through `docs/UAT.md` cases 1–5, 8–11, 14–17.

The highest-value case is **UAT 17**: confirm that a recording is never reported
as saved when it was not.

## Step 19 — Later, test on a physical iPhone Duo

`docs/UAT.md` cases 6, 7, 12, 13 and 16. Until this happens:

- S14 and S15 stay `REQUIRES_PHYSICAL_DUO`.
- **The App Store listing must not claim iPhone Duo behaviour.**

## Step 20 — Update the verification ledger

Edit `docs/VERIFICATION_LEDGER.md` and raise only the rows you actually tested,
using the right tier:

- `swift test` passing → those rows become verified **in a unit test**.
- Ordinary iPhone simulator → verified **in an iPhone simulator** (remember: no
  camera there).
- Duo simulator → verified **in an iPhone Duo simulator**.
- Physical iPhone → verified **on an ordinary physical iPhone**.
- Physical Duo → verified **on a physical iPhone Duo**.

Simulator evidence must never be recorded as physical-device evidence, and
`STATICALLY_REVIEWED` must never be edited into `VERIFIED`.

---

## Quick reference

```bash
xcodebuild -version                        # step 1
xcodebuild -showsdks | grep -i ios         # step 2
xcodegen generate && open PromptCam.xcodeproj
swift test                                 # step 7 — no simulator needed
python3 Scripts/static_review.py           # architectural invariants
xcrun simctl list devicetypes | grep -i duo
```
