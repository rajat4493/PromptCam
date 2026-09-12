# Assumptions

Three categories, kept strictly apart.

- **SUPPLIED** — stated by the product owner from Apple's iPhone Duo developer
  guidance. Authoritative product input. Not compiler-confirmed.
- **DOC-VERIFIED** — read directly in Apple's published documentation.
- **ASSUMED** — nobody has confirmed it; it is a bet.

Itemised list of all 18 supplied API facts: [`../docs/ASSUMPTIONS.md`](../docs/ASSUMPTIONS.md) §2.

## The one technical fact that matters most

**No Duo-specific API signature has been confirmed by a compiler.** Not one.
Every supplied symbol is isolated in `Sources/PromptCamiOS/Platform/` (5 files)
behind the `PROMPTCAM_DUO` condition and a dedicated `Duo` build configuration,
with 20 pre-filled questions in
[`../docs/APPLE_API_CORRECTIONS.md`](../docs/APPLE_API_CORRECTIONS.md).

A wrong signature costs one adapter file. That containment was the point.

## Technical assumptions needing hardware

| ID | Assumption | Risk if wrong | How to falsify |
|---|---|---|---|
| A1 | The Duo outer display reaches third-party apps as a camera scene accessory | The marquee feature does not work; product degrades to an external-display prompter | Run on a physical Duo; observe `onAvailabilityChange` |
| A2 | A live camera preview can render on the accessory, at acceptable cost | "Optional mirrored preview" is impossible; question-only display is final | `MAC_VALIDATION.md` step 17 on hardware |
| A3 | The accessory keeps presenting while `AVCaptureSession` runs | Subject screen blanks mid-interview | Physical device + second display, record 5 min |
| A4 | **Folding mid-recording does not tear down capture** | Recording lost at the worst possible moment | Physical Duo only. **Highest-risk unknown in the project** |
| A5 | An iPhone Duo simulator exists in Xcode 27.1 | UAT 6 and 12 blocked without hardware | `xcrun simctl list devicetypes \| grep -i duo` |
| A6 | iOS 26.0 is a safe deployment floor with 27-gated Duo paths | Availability gates need raising | Check the Duo's shipping iOS version |

## Product assumptions — riskier, and much cheaper to test

| ID | Assumption | Cheapest test |
|---|---|---|
| **P1** | **Subjects answer better when they can read the question themselves** | **Three real interviews, with and without** |
| P2 | Creators prepare a deck in advance rather than improvising | Ship one sample; see if anyone makes a second |
| P3 | Timestamped markers genuinely save editing time | Give an editor a marker list and a 40-minute take |
| P4 | A phone-sized surface is readable at 1–2 m | Measure |
| P5 | "Turn one iPhone into a camera operator and interview producer" lands | Landing-page copy test |
| P6 | An on-screen prompt helps more than it distracts | Same three interviews as P1 |

**P1 and P6 are one experiment, and it has not been run.** The entire product
rests on it. It costs an afternoon. It should happen before any V1 investment —
and notably, it does **not** require Duo hardware if A1's fallback holds.

## Deliberate non-implementations

Places where writing plausible code would have been worse than writing none.

| What | Why | How to finish it |
|---|---|---|
| `AVCaptureDeviceDirectionCoordinator` | Five simultaneous unknowns (type name, three initialiser labels, the handler's parameter type — "a map", unnamed — and its actor isolation). A wrong label fails the build; a wrong handler type may compile and silently never fire. The rear camera does not change identity when the device folds, so V0 needs none of it. | `CaptureDirectionCoordinator.startObserving()` returns `false` and documents the five unknowns and five steps |
| Live subject preview | Unverified capability; the brief forbids faking a preview | `FeatureFlags.subjectLivePreviewEnabled`, stripped at the engine boundary until verified |
| Hinge-driven layout | The supplied guidance itself says to use reserved regions and arrangement APIs for layout | Observer exists for a pre-roll warning and diagnostics only, off by default |
| `ArrangementView` as primary layout | Standard containers already worked; the guidance warns against novelty adoption | Behind `PROMPTCAM_USE_ARRANGEMENT_VIEW`; compare on a Mac and keep the better one |

## Environment blocker

**`BLOCKED`** — no Apple toolchain and no Swift toolchain.
`download.swift.org`, `archive.swiftlang.xyz` and `apt.swiftlang.xyz` all
return 403 CONNECT under organisation egress policy, which per the proxy's own
guidance is reported rather than routed around.

Consequence: `swift build` and `swift test` have never run; the 130 declared
test cases have never executed; `xcodegen generate` has never run.
