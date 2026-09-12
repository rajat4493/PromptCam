# Apple API Corrections

**Purpose.** Every supplied API assumption that turns out to differ from the
real SDK gets recorded here, once, with the correction and the files affected.

**Why this file exists.** PromptCam was written on Linux with no Apple
toolchain, so no Duo API signature could be confirmed. All of them are
concentrated in `Sources/PromptCamiOS/Platform/` behind the `PROMPTCAM_DUO`
compilation condition. When the compiler disagrees with what was written, the
fix belongs in one adapter file — and the reason belongs here, so the next
person does not rediscover it.

## How to use it

Add a row per correction. Keep the "Supplied assumption" column exactly as it
was assumed, even once it is wrong — the diff is the useful part.

`Retest status` is one of: `not retested`, `retested — passes`,
`retested — still failing`.

---

## Corrections

| # | Supplied assumption | Actual compiler / SDK result | Required correction | Files affected | Retest status |
|---|---|---|---|---|---|
| _(none yet — no Mac session has run)_ | | | | | |

---

## Open questions for the first Mac session

Pre-filled from `docs/ASSUMPTIONS.md` §2. Answer each, then move it into the
table above with its result.

| # | Question | Where it matters | Expected from |
|---|---|---|---|
| Q1 | Does `CameraCaptureAccessory` exist, and in which module? | `DuoSubjectAccessory.swift` | `MAC_VALIDATION.md` step 2 probe |
| Q2 | Is its initialiser `init(isEnabled: Binding<Bool>, content:)`? | same | step 2 |
| Q3 | Does it satisfy the conformance `sceneAccessory(content:)` requires (`SceneAccessoryContent`)? | same | step 2 |
| Q4 | What is its real `@available` annotation — 27.0 or 27.1? | same, and `DuoCapabilityProvider.swift` | step 2 |
| Q5 | Does availability genuinely require an active capture session? | `SubjectDisplayAvailability` semantics | step 13 |
| Q6 | Does `GeometryProxy.reservedRegions(kind:)` exist with that spelling? | `DuoReservedRegionLayout.swift` | step 8 |
| Q7 | Are the kinds `.division` and `.occlusion`, and does each region expose `.frame`? | same | step 8 |
| Q8 | Is `.includeInactive` needed, and what is its type? | same | step 8 |
| Q9 | Is the hinge modifier `onHingeChange`, with a two-argument closure? | `DuoHingeObserver.swift` | step 8 |
| Q10 | Is `currentContext.hinge` optional, and what are `hinge.status`'s cases? | same | step 8 |
| Q11 | What type is `hinge.angle`? | same | step 8 |
| Q12 | Does `ArrangementView { } secondary: { }` exist with `.split` / `.overlay`? | `DuoReservedRegionLayout.swift` | step 8 |
| Q13 | Does `AVCaptureDeviceDirectionCoordinator` exist? What are its initialiser labels? | `CameraDirectionAdapter.swift` | step 8 |
| Q14 | What is the **type** of the value passed to its `changeHandler`? (the guidance calls it "a map" without naming the type) | same | step 8 |
| Q15 | What is the handler's actor isolation? | same | step 8 |
| Q16 | Do `.builtInOuterUltraWideCamera` and `.builtInInnerUltraWideCamera` exist with those spellings? | same | step 8 |
| Q17 | Does Xcode 27.1 / the iOS 27.1 SDK exist yet? | `project.yml`, all availability | step 1–2 |
| Q18 | Does an iPhone Duo simulator device type exist? | UAT 6, 12 | step 10 |
| Q19 | Where is Device Hub in Xcode 27.1? | UAT 6 | step 9 |
| Q20 | Can an `AVCaptureVideoPreviewLayer` render inside the camera scene accessory, and at what cost? | `FeatureFlags.subjectLivePreviewEnabled` | step 17 |

## A documented fallback worth knowing about

While the Duo-specific symbols could not be confirmed, one second-surface API
**was** read directly in Apple's published iOS 27.0 documentation:

```swift
// SwiftUI, iOS 27.0+, iPadOS 27.0+ — documented for external displays and AirPlay
func sceneAccessory<C>(@ContentBuilder content: () -> C) -> some View where C: SceneAccessoryContent
@MainActor protocol SceneAccessoryContent
struct ExternalNonInteractiveAccessory<Content> where Content: View
    init(content: () -> Content)
    init(isEnabled: Binding<Bool>, content: () -> Content)
func onAvailabilityChange(perform: @escaping (Bool) -> Void) -> some SceneAccessoryContent

// UIKit equivalent, same release
class UISceneAccessory
class UISceneAccessoryRegistration   // .isAvailable, .isEnabled
UISceneAccessory.externalNonInteractive(sceneConfiguration:)
UIViewController.registerSceneAccessory(_:) -> UISceneAccessoryRegistration
UIViewController.unregisterSceneAccessory(_:)
UIScene.ConnectionOptions.sceneAccessoryUserInfo
```

If `CameraCaptureAccessory` does not resolve, this is the shape to fall back to.
It uses the same `sceneAccessory` / `onAvailabilityChange` pattern, so
`DuoSubjectAccessory.swift` needs only the type name changed — and PromptCam
then works on any external display or AirPlay target, which is a shippable
product in its own right.
