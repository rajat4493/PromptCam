# PromptCam — SDK & Environment Capability Report

**Date:** 2026-09-12 (rewritten after review of commit `f272a18`)
**Method:** TheDuck operating method, Stage A
**Authoritative API source:** Apple's iPhone Duo developer guidance, supplied by
the product owner. See `docs/ASSUMPTIONS.md` §2 for the itemised list.

> **Why this document was rewritten.** An earlier version led with the
> conclusion that `CameraCaptureAccessory`, `onHingeChange`, reserved regions,
> Device Hub and Xcode 27.1 "do not exist", on the strength of searches run
> from this Linux sandbox. That conclusion was wrong, and leaving it in a
> prominent position was actively harmful: a future coding agent reading the
> executive summary would have been told real APIs were fictional. Apple
> documents Xcode 27.1 and Device Hub, and provides a `CameraCaptureAccessory`
> teleprompter pattern that is a direct match for PromptCam's use case.
>
> The searches themselves were real and are reproducible, so they are retained
> — but scoped honestly to what a sandbox with no Apple toolchain could see,
> and moved to Appendix B where they cannot be mistaken for a finding about the
> SDK.

---

## 1. Executive summary

| | |
|---|---|
| **Platform** | iPhone Duo runs iOS 27. Build with Xcode 27.1 / the iOS 27.1 SDK for the intended edge-to-edge and vertical-control behaviour. |
| **Subject-display API** | `CameraCaptureAccessory`, presented through `View.sceneAccessory(content:)` with `onAvailabilityChange`. This is the camera-application scene accessory, and Apple's own teleprompter pattern for it maps directly onto PromptCam's director/subject split. |
| **Availability constraints** | The app must be full-screen on the inner display **and** have an active camera-capture session. The system owns availability and may change it at any time; the app must tolerate the accessory disappearing. |
| **Layout** | Size classes, scene geometry, safe areas and reserved regions. The open inner display reports regular horizontal **and** vertical size classes; the outer display behaves like a compact iPhone environment. |
| **Hinge** | `onHingeChange` (SwiftUI) / `UIHingeInteraction` (UIKit). Suitable for interaction and effects; reserved-region and arrangement APIs are the recommended tools for layout. |
| **Cameras** | Duo adds outer and inner ultrawide **front** cameras plus a virtual front camera. PromptCam records the subject with a **rear** camera and does not use them. |
| **The single blocker** | **No Apple toolchain and no Swift toolchain in this environment.** Nothing has been compiled; no API signature has been confirmed by a compiler. |

**What this means in practice.** PromptCam is built to the supplied API surface,
with every unconfirmed symbol isolated in `Sources/PromptCamiOS/Platform/`
behind the `PROMPTCAM_DUO` compilation condition and a dedicated `Duo` build
configuration. The first Mac session confirms the signatures and records any
correction in `docs/APPLE_API_CORRECTIONS.md`, which has 20 questions
pre-filled. A wrong signature costs one adapter file, not a rewrite.

---

## 2. Build environment — what is actually installed

| Property | Finding | How verified |
|---|---|---|
| Platform | Ubuntu 24.04.4 LTS, Linux 6.18, x86-64, 4 cores | `uname -a`, `/etc/os-release` |
| `xcodebuild`, `xcrun`, `xcode-select`, `simctl` | **NOT INSTALLED** | `command -v` |
| `/Applications/Xcode*.app`, `/Library/Developer` | **ABSENT** | `ls` |
| Installed iOS SDKs | **NONE** | no Xcode, no SDK roots on disk |
| `swift`, `swiftc` | **NOT INSTALLED** | `command -v` |
| Swift toolchain installable? | **NO** | `download.swift.org`, `archive.swiftlang.xyz` and `apt.swiftlang.xyz` all return **403 CONNECT** — organisation egress policy. Per `/root/.ccr/README.md` a 403 is reported, not routed around. Ubuntu's `apt` "swift" packages are OpenStack Swift. |
| Available compilers | clang, rustc, node, python3, ruby, java | `command -v` |

### BLOCKER-1 — no toolchain

> Nothing can be compiled, no test can be executed, no simulator can be booted,
> no screenshot taken. The 130 declared test cases have **never run**.

This is a verification boundary, not a reason to build less. What it does mean:
**this repository is unbuilt source awaiting first compilation**, and
`docs/MAC_VALIDATION.md` exists to get it across that line.

---

## 3. The subject-display API, and why the architecture suits it

The supplied guidance gives PromptCam three things that shaped the design more
than anything else in the brief.

**1. The system decides, not the app.** Availability is system-owned and can
change at any moment. So availability is read *only* from
`onAvailabilityChange`, never inferred, and never derived from device identity.
`SubjectDisplayAvailability` has four states rather than a boolean:

| State | Meaning | Director UI |
|---|---|---|
| `.unsupported` | the platform offers no subject surface | Duo-only controls hidden **entirely** |
| `.unavailable` | supported, not currently offered | hidden |
| `.availableNotEnabled` | offered, operator has not switched it on | toggle shown |
| `.presented` | content is on screen | toggle shown, on |

`.unsupported` being distinct from `.unavailable` is what makes "hide Duo-only
controls cleanly, never show a broken or empty secondary panel" expressible
rather than aspirational.

**2. Availability requires an active capture session.** This is why the
"Subject screen" toggle appears only once the camera is running, and it is why
PromptCam must never keep a camera alive merely to unlock the accessory — that
would be a privacy abuse and is explicitly forbidden in
`Sources/PromptCamiOS/Platform/README.md`.

**3. The app must tolerate the accessory disappearing.** Losing the subject
screen never changes recording state. Asserted by
`AccessoryAvailabilityTests.accessoryDisappearsWhileRecording`.

### Synchronisation

There is none to get wrong. Both surfaces render from one
`InterviewSessionEngine`: the director from the engine, the subject from
`engine.subjectSnapshot()`. One copy of the current question, the countdown, the
recording state and the duration, so the two surfaces cannot disagree.

`SubjectSnapshot` has seven fields and none of them can carry an upcoming
question, the deck name, notes or controls — so the privacy rule is a property
of the type rather than a thing someone has to remember.

---

## 4. Layout approach

Driven entirely by documented capability APIs, with no device detection:

- `horizontalSizeClass` / `verticalSizeClass` choose side-by-side versus
  stacked. The open inner display reports regular in both axes, so it gets the
  side-by-side console with no Duo-specific branch.
- `GeometryProxy.reservedRegions(kind:)` (`.division`, `.occlusion`) keeps the
  record button and question navigation off the hinge, via
  `ReservedRegionSet.largestSafeBand(in:)`.
- Safe-area insets are never assumed symmetric and never doubled; SwiftUI's own
  safe-area handling is used, which is the declarative equivalent of
  `bounds.inset(by: safeAreaInsets)`.
- `UIScreen.main` is never referenced — enforced by `Scripts/static_review.py`,
  which fails on it.
- All three orientations are declared, because the director console must work in
  landscape. Per the supplied guidance the inner display does not use that
  configuration for layout decisions.
- `ArrangementView` is available behind a second flag
  (`PROMPTCAM_USE_ARRANGEMENT_VIEW`) to trial against the size-class layout. The
  guidance warns against adopting it for novelty, and the portable layout
  already works, so it is an evaluation rather than a dependency.

---

## 5. Camera approach

PromptCam's workflow: **record the subject with a rear camera** while the
operator works on the inner display and the subject reads prompts on the outer
display.

The Duo camera additions (`.builtInOuterUltraWideCamera`,
`.builtInInnerUltraWideCamera`, the virtual front camera) are all
**front-facing**, and exist for selfie-style capture. They are listed in
`CameraDirectionAdapter` but deliberately unused: a new front-camera API is not
a reason to start filming with the front camera.

Device selection uses `AVCaptureDevice.DiscoverySession` and takes what the
device reports, rather than hardcoding a lens, so an unfamiliar camera layout
still works.

`AVCaptureDeviceDirectionCoordinator` is **deliberately not implemented** — see
`docs/ASSUMPTIONS.md` §4. Five simultaneous unknowns in one startup path, and
the rear camera does not change identity when the device folds. The seam
exists, returns `false`, and documents the five completion steps.

---

## 6. Answers to the Stage-B validation questions

| # | Question | Answer | Status |
|---|---|---|---|
| 1 | Can a third-party camera app show synchronised custom content on the outer display? | **Yes** — that is what `CameraCaptureAccessory` is for, and synchronisation is inherent because both surfaces render from one engine. | SUPPLIED, `REQUIRES_MAC` |
| 2 | Can the accessory contain a **live camera preview**, or only supplementary content? | **Unverified, and V0 assumes no.** Apple demonstrates teleprompter-like custom content; whether an *independent* live preview is possible, and what it costs, is unverified for this project. Per the brief's "do not fake a preview", V0 ships an honest question-and-status display, and the option is stripped at the engine boundary unless a feature flag marks it verified. | `REQUIRES_MAC`, then `REQUIRES_PHYSICAL_DUO` |
| 3 | Can the inner-display operator use the intended rear camera configuration? | **Yes** — standard rear capture, unchanged API. | SUPPLIED |
| 4 | What happens when the device is opened, closed, rotated or partially folded during recording? | Layout adapts through size classes and reserved regions. Fold position is observable via `onHingeChange` but drives no layout. **Whether folding tears down the capture session is the highest-risk unknown in the project** and needs hardware. | `REQUIRES_PHYSICAL_DUO` |
| 5 | Can the simulator prove the complete experience? | **No.** The Simulator has no camera, so real capture, audio levels and interruptions cannot be exercised there at all. A Duo simulator via Device Hub can prove layout and accessory content; capture needs a device. | `REQUIRES_DUO_SIMULATOR` + physical |
| 6 | Do App Review rules restrict camera use, recording indicators or external-display behaviour? | Technically enforced and handled: accurate usage strings (absent ones crash on first access), the system recording indicator is never suppressed, and the accessory is non-interactive by construction. The Review Guidelines themselves were not fetched. | `BLOCKED` — a founder task |

---

## 7. Appendix A — reproducing the environment findings

```bash
command -v xcodebuild xcrun swift swiftc simctl   # expect: nothing
curl -sS -o /dev/null -w '%{http_code}\n' https://download.swift.org/   # expect: 000 (403 CONNECT)
python3 Scripts/static_review.py                  # architectural invariants
```

On a Mac with Xcode 27.1, the authoritative checks — and the ten-second probe
that settles the accessory question — are in `docs/MAC_VALIDATION.md` steps 1–2.

---

## 8. Appendix B — what this sandbox could and could not see

Scoped narrowly on purpose. **This section is a record of the limits of a Linux
sandbox, not a finding about the iOS SDK.** Nothing here should be read as
evidence that an API does or does not exist.

Using Apple's public documentation JSON API, I downloaded the complete symbol
indexes for SwiftUI (1.38 MB), AVFoundation (1.96 MB) and UIKit (4.98 MB), the
iOS & iPadOS 27 RC release notes (152 KB), and the list of 407 documented
frameworks.

**Resolved from here** — declarations and code samples read directly:

```swift
// SwiftUI, iOS 27.0+ / iPadOS 27.0+
func sceneAccessory<C>(@ContentBuilder content: () -> C) -> some View where C: SceneAccessoryContent
@MainActor protocol SceneAccessoryContent
struct ExternalNonInteractiveAccessory<Content> where Content: View
func onAvailabilityChange(perform: @escaping (Bool) -> Void) -> some SceneAccessoryContent

// UIKit equivalents, same release
class UISceneAccessory,  class UISceneAccessoryRegistration      // .isAvailable, .isEnabled
UISceneAccessory.externalNonInteractive(sceneConfiguration:)
UIViewController.registerSceneAccessory(_:) / .unregisterSceneAccessory(_:)
```

Apple's documented semantics for `sceneAccessory` — "the app declares what
content to provide; the system decides when and where to present it… the app
must remain fully functional without them" — match the supplied constraints for
`CameraCaptureAccessory`, and the `onAvailabilityChange` shape is identical. The
architecture was designed against that shape and needed no change to adopt the
camera accessory.

**Did not resolve from here:** `CameraCaptureAccessory`, `onHingeChange`,
`UIHingeInteraction`, `reservedRegions`, `ArrangementView`,
`AVCaptureDeviceDirectionCoordinator`, the Duo camera device types, "Device
Hub", and any 27.1 release note. A re-probe on 2026-09-12 returned 404 for each
while the control symbol returned 200.

**How to read that:** this sandbox reaches one public documentation archive,
with no Apple toolchain, no developer authentication and no access to
Xcode-bundled documentation — which is where current SDK documentation actually
lives. Absence from what I could reach says nothing about the SDK. The operative
consequence is narrow and unchanged:

> **No Duo-specific signature has been confirmed by a compiler**, so none may be
> treated as known-correct until a Mac says so.

That is why all of them are isolated in five files, behind a flag, off in the
default configuration, with 20 pre-filled questions in
`docs/APPLE_API_CORRECTIONS.md`.

**One useful by-product.** `ExternalNonInteractiveAccessory` is documented for
external displays and AirPlay. If it behaves as documented, the subject-display
experience may be testable today on a TV or an Apple TV, which would let the
core product idea be validated without waiting for Duo hardware. It is also the
obvious fallback if `CameraCaptureAccessory` needs correcting, since the
surrounding pattern is the same.
