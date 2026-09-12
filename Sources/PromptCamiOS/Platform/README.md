# Platform — isolated Apple-API uncertainty

Every symbol in this project whose **exact signature has not been confirmed by a
compiler** lives in this directory and nowhere else. Nothing in `PromptCamCore`,
and nothing in the feature folders (`Decks`, `DirectorSession`, `Recordings`, …),
references an unverified API.

That is deliberate: when the Mac session discovers that a supplied signature
differs from what is written here, the correction touches these files only.
Record each correction in `docs/APPLE_API_CORRECTIONS.md`.

## The compile flag

Unverified Duo APIs are behind the Swift compilation condition
**`PROMPTCAM_DUO`**, which is **off by default**.

With the flag off, the app builds and runs as an ordinary iPhone camera app
with a compact in-frame director overlay. The Duo code paths are replaced by
explicit no-op adapters that return "unsupported" — they cannot be mistaken for
a working outer display, because they render nothing and report
`.unsupported` to the session.

With the flag on, the adapters call the supplied Duo APIs.

This ordering exists so the Mac validation can proceed in the sequence
`docs/MAC_VALIDATION.md` describes: get a clean baseline build and a green test
run *first*, then enable `PROMPTCAM_DUO` and resolve the Duo API surface
separately. A single wrong signature must not block validating the rest of the
application.

To enable it, in `project.yml`:

```yaml
settings:
  SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG PROMPTCAM_DUO
```

or pass `-D PROMPTCAM_DUO` in `OTHER_SWIFT_FLAGS`.

## Files

| File | Uncertainty it contains |
|---|---|
| `DuoCapabilityProvider.swift` | How capability is reported; no model-name detection anywhere |
| `DuoSubjectAccessory.swift` | `CameraCaptureAccessory`, `sceneAccessory`, `onAvailabilityChange` |
| `DuoHingeObserver.swift` | `onHingeChange`, hinge context and status |
| `DuoReservedRegionLayout.swift` | `GeometryProxy.reservedRegions(kind:)`, `ArrangementView` |
| `CameraDirectionAdapter.swift` | `AVCaptureDeviceDirectionCoordinator`, Duo device types |

## Rules for this directory

- No private APIs.
- No model-name or screen-dimension detection.
- No fake implementation that appears to drive an outer display.
- No generic second `UIWindow` substituted for the camera accessory.
- Never keep a camera session alive purely to unlock outer-screen behaviour.
- Every unverified symbol carries a `REQUIRES_MAC_VALIDATION` comment naming
  what must be confirmed.
