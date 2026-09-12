# PromptCam — SDK & Environment Capability Report

**Date of reconnaissance:** 2026-09-12
**Performed by:** Claude (TheDuck operating method, Stage A)
**Status:** Reconnaissance complete. Several premises in the original brief were **not confirmed** and one was **contradicted**.

This document separates what was *proven*, what was *disproven*, and what remains *assumed*. Nothing in this
file is stated as fact unless the evidence column shows how it was checked.

---

## 0. Executive summary (read this first)

Three findings change the shape of the project:

1. **This build environment cannot compile Swift at all.** There is no Xcode, no Swift toolchain, no iOS SDK
   and no Simulator. The session runs on Ubuntu 24.04 / x86-64 Linux. Therefore **no code in this repository
   has been compiled or executed.** Every claim about the code is design-level only.
2. **Xcode 27.1 and the iOS 27.1 SDK do not exist yet.** The newest versions Apple documents are
   **iOS & iPadOS 27 RC** and **Xcode 27 RC**. The brief asked me to confirm 27.1; the honest answer is that
   27.1 is not a shipping version as of today.
3. **There is no documented iPhone Duo / foldable API in the iOS 27 SDK.** No hinge API, no fold posture API,
   no reserved-region API, no `CameraCaptureAccessory`, no "Device Hub". What *does* exist — and what is
   genuinely useful — is a real second-surface API called **`sceneAccessory`**, but it is documented as an
   **external display / AirPlay** feature and it is explicitly **non-interactive**.

The product is still buildable and the wedge is still credible, but the Duo-specific claims must be treated as
an unverified bet, not a confirmed capability. Section 4 explains why building on `sceneAccessory` is
nonetheless the correct architectural decision either way.

---

## 1. Build environment — what is actually installed

| Property | Finding | How verified |
|---|---|---|
| Platform | Ubuntu 24.04.4 LTS, Linux 6.18, x86-64, 4 cores | `uname -a`, `/etc/os-release` |
| `xcodebuild` | **NOT INSTALLED** | `command -v xcodebuild` → not found |
| `xcrun` / `xcode-select` | **NOT INSTALLED** | `command -v` → not found |
| `swift` / `swiftc` | **NOT INSTALLED** | `command -v swift` → not found |
| `simctl` (Simulator) | **NOT INSTALLED** | `command -v simctl` → not found |
| `/Applications/Xcode*.app` | **ABSENT** | `ls -d` → no match |
| `/Library/Developer` | **ABSENT** | `ls` → no such directory |
| Installed iOS SDKs | **NONE** | no Xcode, no SDK roots on disk |
| Swift toolchain installable? | **NO** | `download.swift.org` returns **403 CONNECT** from the egress proxy — an organisation policy denial. Per `/root/.ccr/README.md` these must be reported, not worked around. Ubuntu's `apt` "swift" packages are OpenStack Swift, unrelated. |
| Available compilers | clang (C/C++), rustc, node, python3, ruby, java | `command -v` |

### Consequence — the central blocker

> **BLOCKER-1: No Apple toolchain in this environment.**
> Nothing can be compiled, no test can be executed, no Simulator can be booted, no screenshot can be taken.
> Every "verified" claim in this project must come from a Mac that the founder controls.

This is recorded as `BLOCKED` for all compile-, test- and Simulator-dependent criteria in
`docs/VERIFICATION_LEDGER.md`. It is not a reason to stop producing the code, but it *is* a reason why
this repository must be treated as **unbuilt source awaiting first compilation**, not a working app.

### What I used instead of a local SDK

The brief said to use locally installed SDK documentation as the source of truth. There is none. The closest
available substitute is **Apple's live documentation JSON API**, which is reachable from this environment:

- `https://developer.apple.com/tutorials/data/documentation/<path>.json` — per-symbol docs (availability,
  declaration, discussion, code samples)
- `https://developer.apple.com/tutorials/data/index/<framework>` — the *complete* symbol index for a framework

I downloaded the full symbol indexes for **SwiftUI (1.38 MB)**, **AVFoundation (1.96 MB)** and
**UIKit (4.98 MB)**, plus the full **iOS & iPadOS 27 RC release notes (152 KB)** and the framework
("technologies") list (407 frameworks). Searches below were run against those local copies.

**Evidence class for everything in section 2–3: `DOC-VERIFIED` — present in Apple's official published
documentation, but not compiler-verified.** That is weaker than compiling against the SDK and much weaker
than running on hardware. It is, however, considerably stronger than recall, and it is sufficient to
distinguish a real API from an invented one.

---

## 2. CONFIRMED SDK facts

### 2.1 iOS 27 and Xcode 27 exist — but only as RC

| Claim in brief | Reality | Evidence |
|---|---|---|
| "Xcode 27.1" | **Does not exist.** Latest is **Xcode 27 RC**. Prior line is 26.x (26.0 → 26.6). | Xcode release-notes index lists: Xcode 26, 26.0.1, 26.1.1, 26.2–26.6, **Xcode 27 RC**. No 27.1. |
| "iOS 27.1 SDK" | **Does not exist.** Latest is **iOS & iPadOS 27 RC**. | iOS release-notes index lists 26 → 26.6, then **iOS & iPadOS 27 RC**. No 27.1. |
| iOS 27 is real | **CONFIRMED** | SwiftUI "what's new" has a **June 2026** section (ContentBuilder, `reorderable()`, swipe actions, toolbar `visibilityPriority`, document `ReadableDocument`/`WritableDocument`, gesture input kinds). Symbols report `introducedAt: "27.0"`. |

**Implication:** the deployment target must be chosen against **iOS 27.0**, not 27.1. Any instruction or
generated code referencing "iOS 27.1" or "Xcode 27.1" is wrong and should be corrected wherever it appears.

### 2.2 `sceneAccessory` — REAL, and the only second-surface API that exists

This is the single most important confirmed finding. The brief named `sceneAccessory` and it is genuine.

**SwiftUI surface** (all `iOS 27.0+`, `iPadOS 27.0+`, non-beta):

| Symbol | Declaration |
|---|---|
| `View.sceneAccessory(content:)` | `nonisolated func sceneAccessory<C>(@ContentBuilder content: () -> C) -> some View where C : SceneAccessoryContent` |
| `SceneAccessoryContent` | `@MainActor protocol SceneAccessoryContent` |
| `ExternalNonInteractiveAccessory<Content>` | `nonisolated struct ExternalNonInteractiveAccessory<Content> where Content : View` |
| `ExternalNonInteractiveAccessory.init(content:)` | `init(content: () -> Content)` |
| `ExternalNonInteractiveAccessory.init(isEnabled:content:)` | `init(isEnabled: Binding<Bool>, content: () -> Content)` |
| `SceneAccessoryContent.onAvailabilityChange(perform:)` | `nonisolated func onAvailabilityChange(perform action: @escaping (Bool) -> Void) -> some SceneAccessoryContent` |

**UIKit surface** (equivalent, same release):

| Symbol | Path |
|---|---|
| `UISceneAccessory` | `/documentation/uikit/uisceneaccessory` |
| `UISceneAccessoryRegistration` (`.isAvailable`, `.isEnabled`) | `/documentation/uikit/uisceneaccessoryregistration` |
| `UISceneAccessory.externalNonInteractive(sceneConfiguration:)` | + `(sceneConfiguration:userInfo:)` overload |
| `UIViewController.registerSceneAccessory(_:)` → returns registration | `/documentation/uikit/uiviewcontroller/registersceneaccessory(_:)` |
| `UIViewController.unregisterSceneAccessory(_:)` | — |
| `UIScene.ConnectionOptions.sceneAccessoryUserInfo` | — |

**Apple's documented semantics** (quoted from `View.sceneAccessory(content:)` discussion):

> "A scene accessory declares supplementary content that the system presents on the app's behalf when an
> associated piece of system functionality becomes available, for example when an external display is
> connected. The app declares what content to provide; the system decides when and where to present it.
> **Scene accessories enhance the app's experience when available, but the app must remain fully functional
> without them.**"

And from `ExternalNonInteractiveAccessory`:

> "A scene accessory that presents non-interactive content on an external display. The scene accessory may be
> presented when an external display is connected to the device, **or when the device is connected to an
> external display via AirPlay.**"

**Apple's own canonical code sample** (verbatim from the docs — this is the pattern PromptCam adopts):

```swift
struct RootView: View {
    @State private var isEnabled = false
    @State private var isAvailable = false
    @State private var isPresented = false
    var document: PresentationDocument

    var body: some View {
        PresentationDocumentView(document: document)
            .toolbar {
                if isAvailable {
                    SecondaryDisplayToggle(isEnabled: $isEnabled)
                    if isPresented {
                        SecondaryDisplayControls()
                    }
                }
            }
            .sceneAccessory {
                ExternalNonInteractiveAccessory(isEnabled: $isEnabled) {
                    PresentationPreview(document: document)
                        .onAppear { isPresented = true }
                        .onDisappear { isPresented = false }
                }
                .onAvailabilityChange { newValue in
                    isAvailable = newValue
                }
            }
    }
}
```

Note how closely Apple's own example matches PromptCam's need: a **presentation preview shown on a second
surface while the operator keeps the controls on the primary surface.** That is a strong signal that the
"director console + subject prompt screen" split is an idiomatic use of this API rather than a fight against it.

**Release-note corroboration** (iOS & iPadOS 27 RC, item 175548901):

> "In apps built with the iOS 27.0 SDK, you can display non-interactive content on external display scenes
> using the `.sceneAccessory` view modifier with an `ExternalNonInteractiveAccessory` type."

And (UIKit migration note):

> "In apps built with the iOS 27.0 SDK, `windowExternalDisplayNonInteractive` scenes are no longer offered
> automatically by the system. Use `UIViewController.registerSceneAccessory(_:)` with a
> `UISceneAccessory.externalNonInteractive` instance to display non-interactive content on external display
> scenes."

### 2.3 Scene-based lifecycle is now mandatory

From the iOS 27 RC release notes (141837548):

> "Apps built with the latest SDK must adopt the scene-based life cycle or they fail to launch."

A SwiftUI `App` already satisfies this. Recorded so it is not accidentally violated later.

### 2.4 Camera/recording APIs relied upon — all long-established

| Symbol | iOS availability | Note |
|---|---|---|
| `AVCaptureVideoPreviewLayer` | 4.0+ | operator preview |
| `AVCaptureMovieFileOutput` | 4.0+ | file recording + delegate-confirmed completion |
| `AVCaptureMultiCamSession` | 13.0+ | exists, but **not needed for V0** (see §5) |
| `AVCaptureDevice.requestAccess(for:)` | 7.0+ | permissions |

No new iOS 27 camera API was found that changes this design.

---

## 3. DISPROVEN / NOT FOUND — claims from the brief that do not hold

Searches were run over the **complete** SwiftUI, AVFoundation and UIKit symbol indexes plus the full iOS 27 RC
release notes. Match counts are literal, case-insensitive.

| Claim in brief | Result | Evidence |
|---|---|---|
| `CameraCaptureAccessory` | **NOT FOUND** | 0 matches across all three framework indexes. Not in release notes. |
| `onHingeChange` | **NOT FOUND** | 0 matches across all three framework indexes. Not in release notes. |
| "Reserved regions" API | **NOT FOUND** | 0 matches for `reservedRegion` / "reserved region". The only `reserved*` hits in UIKit are unrelated: `UIControl.State.reserved`, `UIControlEventApplicationReserved`, `UICellAccessory.reservedLayoutWidth`. |
| "Device Hub" | **NOT FOUND** | 0 matches in iOS 27 RC release notes; not among the 407 documented frameworks. |
| Hinge API of any kind | **NOT FOUND** | `hinge`: 0 in SwiftUI, 0 in AVFoundation, 0 in UIKit (the 2 UIKit "matches" are the substring inside `isPrefetchingEnabled`). 0 in release notes. |
| Fold / posture / articulation API | **NOT FOUND** | `fold`: 0 symbols in all three indexes; the 3 release-note hits are the word "folder". `posture`, `articulat`, `unfold`, `halfopen`, `booklet`, `crease`, `dual screen`: **0 symbol matches each.** |
| "iPhone Duo" as a documented device | **NOT FOUND** | 0 mentions in iOS 27 RC release notes. (`duo` matches only `AVCaptureDeviceTypeBuiltInDuoCamera` — the deprecated iPhone 7 Plus dual-lens device type, unrelated to a foldable.) |
| A foldable-specific framework | **NOT FOUND** | Reviewed all **407** framework names in Apple's technologies index. Nothing foldable-, hinge- or Duo-related. |
| "Inner and outer camera selection" API | **NOT FOUND** | No new iOS 27 camera-position API. `AVCaptureDevice.Position` remains front/back/unspecified. |
| "Adaptive size classes" as a new Duo feature | **Already existed** | Size classes, safe areas and `GeometryReader` are long-standing. Nothing Duo-specific was added. |
| iPhone Duo Simulator | **CANNOT CHECK** | No Simulator installed and no Xcode. Undetermined, not disproven. |

### 3.1 The single most important correction

`sceneAccessory` is real, but the brief's framing of it as *"the iPhone Duo outer-display API"* is **not
supported by the documentation.** Every Apple sentence about it describes **external displays and AirPlay**.
There is no documented statement that a foldable's outer display is surfaced through it.

Three explanations are possible, and I cannot distinguish between them from here:

- **(a)** iPhone Duo was announced and its developer APIs are NDA / ship in a later iOS 27.x that is not yet
  publicly documented. Plausible — today is 2026-09-12, iOS 27 is only at RC, and Apple announcements
  typically land in September.
- **(b)** The specific names in the brief (`CameraCaptureAccessory`, `onHingeChange`, reserved regions,
  Device Hub) came from a rumour, a secondhand summary, or a generated draft, and are not real API names.
  The fact that `sceneAccessory` is exactly right while the other four are exactly absent points this way.
- **(c)** The Duo's outer display is exposed to third-party apps **as an external display scene**, reusing
  `sceneAccessory` rather than adding foldable-specific API. This would be very Apple-like: one abstraction,
  the system decides placement, apps must work without it.

**I have not verified which is true, and I will not write code or documentation that assumes one.**

---

## 4. Architectural decision that follows from the evidence

**Decision: build the subject-facing display on `sceneAccessory` + `ExternalNonInteractiveAccessory`, behind
a protocol boundary, and never branch on device identity.**

Rationale — this is the right bet under *all three* explanations above:

- If **(c)** is true, PromptCam works on iPhone Duo on day one with no change.
- If **(a)** is true, the protocol boundary (`SubjectDisplayPresenting`) is the seam where a Duo-specific
  implementation drops in. The session state, the subject view, the design system and all the tests are reused.
- If **(b)** is true, nothing was wasted: PromptCam still ships a genuinely differentiated feature — a
  subject-facing prompt screen on any external display or AirPlay target (a monitor, a TV, an Apple TV in a
  studio). That is a real, testable, shippable product today, on hardware the founder can already buy.

Consequences that are forced by the evidence, not chosen:

1. **The subject display cannot accept input.** The type is literally `ExternalNonInteractiveAccessory`. No
   buttons, no taps, no gestures on the subject surface. All control stays with the director. (This happens to
   be correct product design anyway — the interviewee should not be able to change anything.)
2. **The system, not the app, decides when the accessory appears.** We must drive everything from
   `onAvailabilityChange` and `onAppear`/`onDisappear`, never from a device check.
3. **The app must be fully functional with no accessory.** Apple states this as a requirement. The
   "ordinary iPhone fallback" is therefore not a nice-to-have; it is the compliant baseline.
4. **No hinge/fold code will be written.** There is no API. Fold handling reduces to ordinary adaptive layout
   (size classes, safe areas, `GeometryReader`) which is required regardless and is testable on an iPad or in
   Split View today. Writing speculative `onHingeChange` code would be inventing an API — forbidden by the brief.
5. **No string-based device detection**, per the brief, and now also because there is nothing to detect.

---

## 5. Answers to the six Stage-B validation questions

| # | Question | Answer | Confidence |
|---|---|---|---|
| 1 | Can a third-party camera app show synchronized custom content on the outer display? | **On an external display / AirPlay: yes** — `sceneAccessory` is designed for it and both surfaces render from the same SwiftUI state, so synchronisation is inherent (single source of truth, not message passing). **On a Duo outer display specifically: UNVERIFIED.** | DOC-VERIFIED for external display; ASSUMPTION for Duo |
| 2 | Can the accessory contain a **live camera preview**, or only supplementary content? | **UNVERIFIED, and V0 assumes NO.** The generic is `Content: View`, so an `AVCaptureVideoPreviewLayer` wrapped in `UIViewRepresentable` is *type-compatible* — but type-compatibility is not proof that the system renders a live capture layer on a non-interactive accessory surface, and there is no documented statement either way. Per the brief's "do not fake a preview", **V0 ships an honest question + status display with no preview**, and the preview is gated behind a feature flag that stays off until verified on hardware. | ASSUMPTION — must be tested on a device |
| 3 | Can the inner-display operator use the intended rear camera configuration? | **Standard rear capture: yes** (`AVCaptureDevice.Position.back`, unchanged API). **Whether a Duo exposes additional/different rear cameras when open vs. closed: UNVERIFIED.** V0 uses `AVCaptureDevice.DiscoverySession` and takes what the device reports, rather than hardcoding a lens. | DOC-VERIFIED for ordinary rear capture |
| 4 | What happens when the device is opened, closed, rotated or partially folded during recording? | **UNKNOWN — no API exists to observe it, so it cannot be handled explicitly.** What I *can* do defensively, and do: treat it as an ordinary scene-geometry change (layout must survive arbitrary resize), and treat accessory loss as a first-class event via `onAvailabilityChange(false)` / `onDisappear` **without ending the recording**. Also handle `AVCaptureSession` interruption notifications, which is where a hardware reconfiguration would most plausibly surface. | ASSUMPTION — highest-risk unknown in the project |
| 5 | Can the Simulator prove the complete experience? | **No.** Two independent reasons: (i) the Simulator has **no camera**, so real capture, real mic levels and real interruption behaviour cannot be exercised there at all; (ii) no Duo Simulator has been confirmed to exist. A physical device is required for capture, and a physical iPhone Duo would be required for any Duo claim. | Reasoned from (i) documented Simulator limitation, (ii) unverifiable |
| 6 | Do App Review rules restrict camera use, recording indicators or external-display behaviour? | **Partially answered; needs founder review of current guidelines.** What is *technically* enforced and confirmed: accurate `NSCameraUsageDescription` / `NSMicrophoneUsageDescription` are mandatory or the app crashes on first access; the system recording indicator cannot be suppressed; `ExternalNonInteractiveAccessory` cannot present interactive controls by construction. The App Store Review Guidelines themselves were not fetched and are outside what I can verify from here. | Partially DOC-VERIFIED; guidelines review is a founder task |

---

## 6. Assumption register (things that must be validated on hardware)

| ID | Assumption | Risk if wrong | How to falsify |
|---|---|---|---|
| A1 | iPhone Duo's outer display is offered to third-party apps as a scene accessory | Core wedge does not work on Duo; product degrades to "external display prompter" | Run on a physical iPhone Duo; observe `onAvailabilityChange` |
| A2 | A live camera preview can render on a non-interactive accessory | "Optional mirrored preview" is impossible; question-only display is final | Enable the flag on a device with an external display and observe |
| A3 | The accessory keeps presenting while `AVCaptureSession` is running | Subject screen blanks mid-interview | Physical device + external display, record for 5 min |
| A4 | Fold/open during recording does not tear down the capture session | Recording lost at the worst moment | Physical iPhone Duo only |
| A5 | An iPhone Duo Simulator exists in some Xcode 27.x | UAT cases 6, 12 are permanently blocked without hardware | `xcrun simctl list devicetypes` on a Mac with Xcode 27 |
| A6 | iOS 27.0 is an acceptable floor for the Duo path | If Duo ships on a later 27.x, availability gates need raising | Check Duo's shipping iOS version |

---

## 7. What this report does NOT claim

- It does **not** claim the code compiles. It has never been compiled.
- It does **not** claim any iPhone Duo behaviour was observed.
- It does **not** claim `sceneAccessory` was called successfully. It was read, not run.
- It does **not** claim the App Store Review Guidelines were reviewed.
- Documentation presence proves an API **exists**; it does not prove our **usage** of it is correct.

---

## 8. Reproducing this reconnaissance

Run on any machine with network access to `developer.apple.com`:

```bash
# Full symbol index for a framework
curl -s "https://developer.apple.com/tutorials/data/index/swiftui" -o idx_swiftui.json
grep -o -i '"title":"[^"]*hinge[^"]*"' idx_swiftui.json | sort -u   # expect: no output

# A single symbol's availability + declaration + code samples
curl -s "https://developer.apple.com/tutorials/data/documentation/swiftui/externalnoninteractiveaccessory.json" | jq '.metadata.platforms'

# iOS 27 RC release notes
curl -s "https://developer.apple.com/tutorials/data/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes.json" -o rn27.json
grep -c -i hinge rn27.json    # expect: 0
```

On a Mac with Xcode 27, the authoritative checks are:

```bash
xcodebuild -version
xcodebuild -showsdks | grep -i ios
xcrun simctl list devicetypes | grep -i -E 'duo|fold'
echo 'import SwiftUI; @available(iOS 27, *) func p(_ b: Binding<Bool>) -> some SceneAccessoryContent { ExternalNonInteractiveAccessory(isEnabled: b) { Text("x") } }' > /tmp/p.swift
xcrun swiftc -sdk "$(xcrun --sdk iphoneos --show-sdk-path)" -target arm64-apple-ios27.0 -typecheck /tmp/p.swift
```

That last command is the first thing to run on a Mac: it turns §2.2 from `DOC-VERIFIED` into
`COMPILE-VERIFIED` in about ten seconds.
