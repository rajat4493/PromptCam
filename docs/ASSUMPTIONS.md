# PromptCam — Assumptions Register

**Last updated:** 2026-09-12
**Companion documents:** `SDK_CAPABILITY_REPORT.md` (what I could and could not
check), `VERIFICATION_LEDGER.md` (what has been proven),
`APPLE_API_CORRECTIONS.md` (where compiler reality gets recorded).

This file separates three things that are easy to blur together:

- **SUPPLIED** — stated by the product owner from Apple's iPhone Duo developer
  guidance. Treated as authoritative product input. **Not** compiler-confirmed.
- **DOC-VERIFIED** — I read it in Apple's published documentation myself.
- **ASSUMED** — nobody has confirmed it; it is a bet.

No item in this file has been compiled or run. See §5 for why.

---

## 1. Evidence labels used across this project

| Label | Meaning |
|---|---|
| `VERIFIED_LINUX` | Proven by an executable check in this Linux environment |
| `STATICALLY_REVIEWED` | Source exists and was read line by line; never compiled |
| `REQUIRES_MAC` | Needs Xcode 27.1 and the iOS 27.1 SDK |
| `REQUIRES_DUO_SIMULATOR` | Needs Device Hub and an iPhone Duo simulator |
| `REQUIRES_PHYSICAL_DUO` | Cannot be fully proven without the device |
| `BLOCKED` | Cannot currently proceed at all |
| `FAILED` | Attempted and did not work |

**`STATICALLY_REVIEWED` never becomes `VERIFIED`.** It can only be replaced by
a compiler or a device result.

---

## 2. Supplied Apple API surface

All of the following came from the product owner. PromptCam is built to use
them, every use is isolated in `Sources/PromptCamiOS/Platform/`, and every use
is behind the `PROMPTCAM_DUO` compilation condition.

| ID | Supplied fact | Where PromptCam relies on it | Status |
|---|---|---|---|
| S1 | iPhone Duo runs iOS 27 | Availability floor | SUPPLIED |
| S2 | Xcode 27.1 adds Duo support via Device Hub | Simulator UAT cases | SUPPLIED, REQUIRES_MAC |
| S3 | The iOS 27.1 SDK provides the intended edge-to-edge and vertical-control behaviour | `project.yml` targets that SDK | SUPPLIED, REQUIRES_MAC |
| S4 | Outer display behaves like a compact iPhone environment | Size-class-driven layout | SUPPLIED |
| S5 | Open inner display reports regular horizontal **and** vertical size classes | `prefersSideBySide` in `DirectorSessionView` | SUPPLIED |
| S6 | The inner display does not use supported-orientation configuration for layout | All three orientations declared; layout driven by size classes | SUPPLIED |
| S7 | `CameraCaptureAccessory` is the camera-app scene accessory | `DuoSubjectAccessory.swift` | SUPPLIED, REQUIRES_MAC |
| S8 | Accessory availability requires full-screen on the inner display **and** an active camera-capture session | `SubjectDisplayAvailability` models this; the app never keeps a camera alive just to unlock the accessory | SUPPLIED |
| S9 | The system controls availability and may change it at any time | Availability comes only from the system callback | SUPPLIED |
| S10 | `onHingeChange` with `(previousContext, currentContext)`, `hinge.status`, `hinge.angle` | `DuoHingeObserver.swift`, off by default | SUPPLIED, REQUIRES_MAC |
| S11 | `GeometryProxy.reservedRegions(kind:)` with `.division` / `.occlusion` | `DuoReservedRegionLayout.swift` | SUPPLIED, REQUIRES_MAC |
| S12 | `ArrangementView { } secondary: { }` with `.split` / `.overlay` | Behind a second flag; a size-class layout is the default | SUPPLIED, REQUIRES_MAC |
| S13 | `AVCaptureDeviceDirectionCoordinator(view:deviceTypes:changeHandler:)` | **Deliberately not implemented** — see §4 | SUPPLIED, REQUIRES_MAC |
| S14 | `.builtInOuterUltraWideCamera`, `.builtInInnerUltraWideCamera` exist | Listed in `CameraDirectionAdapter`, not used by the rear-camera workflow | SUPPLIED, REQUIRES_MAC |
| S15 | Duo front cameras: outer 4K/120, inner 1080p/60, virtual ~1080p/60 | Not relied upon; PromptCam records with a rear camera | SUPPLIED |
| S16 | Screens come from `window?.windowScene?.screen`, never `UIScreen.main` | Enforced — `Scripts/static_review.py` fails the build on `UIScreen.main` | SUPPLIED, VERIFIED_LINUX (absence proven) |
| S17 | Safe-area insets may be asymmetric | No inset is ever doubled or assumed symmetric | SUPPLIED |
| S18 | Duo must not be identified by model name or fixed dimensions | Enforced — static review fails on `utsname`, `UIDevice.current.model`, `sysctlbyname`, model string literals | SUPPLIED, VERIFIED_LINUX (absence proven) |

### 2.1 A discrepancy worth recording

Independently of the supplied guidance, I searched Apple's **published**
documentation from this environment: the complete SwiftUI, AVFoundation and
UIKit symbol indexes, the iOS & iPadOS 27 RC release notes, and the list of 407
documented frameworks.

| Symbol | Found in published docs? |
|---|---|
| `sceneAccessory`, `SceneAccessoryContent`, `onAvailabilityChange` | **Yes** — iOS 27.0+ |
| `ExternalNonInteractiveAccessory` | **Yes** — iOS 27.0+, documented for external displays and AirPlay |
| `UISceneAccessory`, `UIViewController.registerSceneAccessory(_:)` | **Yes** — iOS 27.0+ |
| `CameraCaptureAccessory` | No |
| `onHingeChange`, `UIHingeInteraction` | No |
| `reservedRegions` | No |
| `ArrangementView` | No |
| `AVCaptureDeviceDirectionCoordinator` | No |
| `.builtInOuterUltraWideCamera` / `.builtInInnerUltraWideCamera` | No |
| Any hinge, fold or posture API | No |
| "Device Hub" | No |
| Xcode 27.1 / iOS 27.1 | No — newest published is **Xcode 27 RC** and **iOS 27 RC** |

**How to read this, without over-claiming in either direction.** The
`sceneAccessory` family being present and correct, while the Duo-specific
symbols are uniformly absent, is most consistent with the Duo APIs being
newer than Apple's public documentation archive — a device announced around
now, with its SDK arriving in 27.1. That is a coherent explanation and it does
not contradict the supplied guidance.

It does, however, have one hard consequence: **I could not confirm a single
Duo-specific signature, so none of them may be treated as known-correct.** The
first Mac session must verify each one and record the result in
`APPLE_API_CORRECTIONS.md`. The architecture is arranged so that a wrong
signature costs one adapter file, not a rewrite.

A useful fallback also comes out of this: `ExternalNonInteractiveAccessory` is
the one second-surface type whose declaration I actually read. If
`CameraCaptureAccessory` does not resolve, it is the obvious next thing to try,
and it is already documented in `DuoSubjectAccessory.swift`.

---

## 3. Product assumptions (no evidence either way)

These are riskier than the technical ones, and cheaper to test.

| ID | Assumption | Why it matters | Cheapest test |
|---|---|---|---|
| P1 | Subjects answer better when they can read the question themselves | **The entire product rests on this** | Three real interviews, with and without |
| P2 | Creators will prepare a deck in advance rather than improvising | Decks are the content model | Ship with one sample; see if anyone makes a second |
| P3 | Timestamped markers genuinely save editing time | Justifies the marker workflow | Give one editor a marker list and a 40-minute take |
| P4 | A phone-sized surface is readable at interview distance (1–2 m) | Determines the type scale | Measure at 1 m and 2 m |
| P5 | "Turn one iPhone into a camera operator and interview producer" is the line that lands | App Store positioning | Landing-page copy test |
| P6 | An on-screen prompt does not distract the interviewee more than it helps | Could invert the whole premise | Same three interviews as P1 |

**P1 and P6 are the same experiment, and it has not been run.** It costs one
afternoon and should happen before any V1 investment.

---

## 4. Deliberate non-implementations

Places where writing plausible code would have been worse than not writing it.

| What | Why it was left out | How to complete it |
|---|---|---|
| `AVCaptureDeviceDirectionCoordinator` wiring | The supplied snippet has five unknowns at once: type name, three initialiser labels, the handler's parameter type ("a map", type unnamed), actor isolation, and availability. Putting that in the app's startup path risks either a build failure or a handler that silently never fires. PromptCam's rear camera does not change identity when the device folds, so nothing needs it. | `CaptureDirectionCoordinator.startObserving()` documents the five unknowns and the five steps. It returns `false` today, so the capability is reported as unavailable rather than assumed. |
| Live preview on the subject surface | Capability and performance unverified. The brief forbids faking a preview. | `FeatureFlags.subjectLivePreviewEnabled`. Flip it only after UAT 16 passes on hardware. Until then the option is stripped at the engine boundary, so it cannot reach the view. |
| Hinge-driven layout | The supplied guidance recommends reserved regions and arrangement APIs for layout. Hinge angle is for interaction and effects. | `DuoHingeObserver` exists for diagnostics and a pre-roll warning only, off by default. |
| `ArrangementView` as the primary layout | Standard adaptive containers already do this, and the guidance says not to adopt it for novelty. | Behind `PROMPTCAM_USE_ARRANGEMENT_VIEW`; compare against the size-class layout on a Mac and keep whichever is better. |

---

## 5. The environment blocker

**`BLOCKED`: there is no Apple toolchain, and no Swift toolchain at all.**

| Probe | Result |
|---|---|
| `xcodebuild`, `xcrun`, `xcode-select`, `simctl` | not installed |
| `/Applications/Xcode*.app`, `/Library/Developer` | absent |
| `swift`, `swiftc` | not installed |
| `download.swift.org` | **403 CONNECT** — organisation egress policy |
| `archive.swiftlang.xyz`, `apt.swiftlang.xyz` | **403 CONNECT** — same |
| Ubuntu `apt` "swift" packages | OpenStack Swift; unrelated |

Per `/root/.ccr/README.md`, a 403 from the proxy is a policy denial to be
reported rather than worked around, so no attempt was made to route around it.

**Consequences, stated plainly:**

- `swift build` and `swift test` have **never been run**. The 112 declared test
  cases in `Tests/PromptCamCoreTests` have never executed. They are
  `STATICALLY_REVIEWED`, not passing.
- No SwiftUI or AVFoundation file has been type-checked.
- `xcodegen generate` has never been run, so `project.yml` is unproven.
- No simulator, no device, no screenshot, no signing.

**What *was* executed here:** `Scripts/static_review.py`, which checks the
architectural invariants and currently passes. That is real evidence for
structure — Core purity, Duo-symbol isolation, absence of device detection and
`UIScreen.main`, bracket balance, no false verification claims — and it is
evidence for nothing else. It is not a compiler.
