# PromptCam — Product Definition (V0)

**Status:** Stage B complete — concept challenged, scope locked.
**Companion documents:** `SDK_CAPABILITY_REPORT.md` (what the SDK actually allows),
`VERIFICATION_LEDGER.md` (what has been proven).

---

## 1. The human problem

One person cannot simultaneously operate a camera and produce an interview.

A solo creator recording someone else is doing at least five jobs at once: holding framing, watching audio,
remembering the question list, deciding when to move on, and marking the moments worth keeping. In practice
something gets dropped. The usual failure modes are specific and familiar:

- The interviewee **forgets the question** halfway through the answer, and the take is wasted.
- The creator **reads questions off a second device** (a phone on a table, a printed sheet), which breaks eye
  contact and looks unprofessional on camera.
- The interviewee **doesn't know when recording starts**, so the first four seconds are a confused pause.
- Good moments are **not marked**, so the editor re-watches 40 minutes of footage to find six usable clips.
- The creator **can't see the question list and the camera at the same time**, so pacing collapses.

None of these are camera-quality problems. They are *production* problems, and they are what makes one-person
interview shoots feel amateur.

## 2. Target user

**Primary (V0):** a solo creator or a two-person creator team who records other people talking, on a phone,
without a crew.

Concretely: street interviews, customer testimonials, podcast clips, founder interviews, employee and event
interviews, short-form Q&A.

**Explicitly not the V0 user:** broadcast crews (they have hardware teleprompters and monitors), people
recording *themselves* (that is a teleprompter product, deliberately excluded — see §8), and anyone whose
problem is editing rather than capture.

## 3. Core job to be done

> *"When I record someone else on my own, help me run the interview — not just the camera — so the subject
> always knows what to answer and I leave the shoot knowing where the good parts are."*

Three sub-jobs, in priority order:

1. **Keep the subject oriented** — they can see the current question and whether we are rolling.
2. **Keep the operator in control** — camera, question navigation, record/stop, duration, audio level, all
   reachable one-handed without leaving the camera view.
3. **Leave the shoot with structure** — the video, plus timestamped markers and question-change points, so
   editing starts from a map instead of a blank timeline.

## 4. The promise

**Turn one iPhone into a camera operator and an interview producer.**

## 5. Why a second display materially improves this workflow

This is the part the brief asked me to challenge, so I will be precise about what is and is not established.

**The genuine mechanism:** the interview has two audiences for two *different* sets of information, and today
they are forced to share one screen or none.

| Information | Who needs it | Who must NOT see it |
|---|---|---|
| Current question, large and readable | the subject | — |
| Countdown before roll | the subject | — |
| "We are recording" | the subject | — |
| Upcoming questions, private notes | the operator | **the subject** |
| Camera controls, audio level, markers | the operator | the subject (it's distracting and unprofessional) |

Without a second surface, the operator's only options are to read questions aloud from behind the phone, use a
second device, or hand the subject a piece of paper. A second display collapses all of that into one device.

**What is confirmed:** iOS 27 provides `sceneAccessory` / `ExternalNonInteractiveAccessory`, a real API for
presenting non-interactive content on a second surface while the app keeps its controls on the primary
surface. Apple's own documentation example for this API is a presentation preview on a second screen with
controls staying on the first — structurally identical to PromptCam. Because both surfaces render from the
same SwiftUI state, the two screens *cannot disagree*; synchronisation is a consequence of the architecture
rather than a feature to build.

**What is NOT confirmed — stated plainly:** that iPhone Duo's outer display is exposed to third-party apps
through this API, or through any API. As documented today, `sceneAccessory` is about **external displays and
AirPlay**. There is no hinge API, no fold-posture API, no reserved-region API and no `CameraCaptureAccessory`
anywhere in the iOS 27 SDK documentation. See `SDK_CAPABILITY_REPORT.md` §3 for the searches.

**Why the product is still worth building now:** the second-surface value proposition is real and shippable
*today* on external displays and AirPlay — a studio monitor, a TV, an Apple TV. If the Duo exposes its outer
display as a scene accessory, PromptCam gains the marquee use case for free, because the seam is a protocol,
not a device check. If it does not, PromptCam is still a differentiated interview tool and nothing needs
rewriting. That asymmetry is the reason to proceed.

## 6. Product wedge

**Narrow wedge:** the *only* app where the person being interviewed can read the question themselves.

Not "a camera app with more features". Not "a teleprompter". The wedge is the **subject-facing surface**, and
everything else in V0 exists to make that surface useful: decks give it content, the state machine keeps it
truthful, markers make the resulting footage editable.

Defensibility in the short term is execution and timing, not technology. The honest position: this is a
land-grab on a new hardware affordance, and the moat is being early with something that actually works.

## 7. Success criteria for V0

A criterion is only "met" when `VERIFICATION_LEDGER.md` records it as `VERIFIED` with stated evidence.

| # | Criterion | Verification tier required |
|---|---|---|
| S1 | A user can create a deck, edit and reorder questions, and see them again after relaunch | unit test + physical iPhone |
| S2 | A complete interview can be recorded and the file plays back | physical iPhone |
| S3 | The app never reports a recording as saved unless the OS confirmed it | unit test + physical iPhone |
| S4 | Recording state transitions are total and invalid ones are rejected | unit test |
| S5 | Questions can be changed mid-recording and each change is timestamped | unit test + physical iPhone |
| S6 | Markers can be added mid-recording with accurate timestamps | unit test + physical iPhone |
| S7 | Video and marker list can be exported | physical iPhone |
| S8 | Denied camera or mic permission produces a clear recovery path, never a crash or dead screen | physical iPhone |
| S9 | A recording interrupted by a call or backgrounding is either finished safely or reported as interrupted — never silently lost | physical iPhone |
| S10 | On a device with no accessory, no empty or broken secondary UI is ever shown | physical iPhone |
| S11 | The subject surface shows the current question, countdown and recording state, and never director-only content | physical iPhone + external display |
| S12 | Accessory appearing or disappearing mid-session does not end the recording or desynchronise state | unit test + physical iPhone + external display |
| S13 | Controls stay reachable and readable across orientation, size class and Dynamic Type | physical iPhone / iPad Split View |
| S14 | The subject surface is readable from 1–2 m | physical device + external display, measured |
| S15 | The Duo inner/outer split works on iPhone Duo | **physical iPhone Duo — currently BLOCKED** |

## 8. V0 boundaries (explicit non-goals)

Excluded, as instructed, and each for a reason worth remembering:

| Excluded | Why |
|---|---|
| Generative AI / auto question generation | The value is in *asking* well, not generating filler. Also: instant credibility loss. |
| Transcription, subtitles | Large surface, commodity elsewhere, nothing to do with the wedge. |
| Video editing | Different product. Markers exist precisely so the user can edit elsewhere. |
| Cloud storage, accounts, teams, backend | V0 is local-only. Nothing to breach, nothing to operate, no privacy review. |
| Social publishing APIs | Fragile, high-maintenance, reviewer-sensitive. |
| Analytics SDKs, tracking | Interview recordings are sensitive. Zero third-party SDKs is a feature. |
| Subscription infrastructure | Charge after evidence that people finish interviews with it. |
| Android | Premise is iPhone-specific hardware. |
| General-purpose teleprompter | Self-recording is a different job with different competitors. Would blur the wedge. |
| Pose coaching, livestreaming, multiple themes | Feature theatre. |

**A feature does not enter V0 because it is easy. It enters because S1–S14 need it.**

## 9. Risks

| ID | Risk | Severity | Mitigation in V0 |
|---|---|---|---|
| R1 | Duo's outer display is not exposed to third-party apps at all | **Critical** — kills the marquee story | Subject display sits behind `SubjectDisplayPresenting`; ships today on external display / AirPlay; product survives as an interview tool |
| R2 | Live preview on the accessory is impossible | Medium | Preview is off by default and flag-gated; question display is the honest primary design, not a fallback |
| R3 | Folding mid-recording tears down the capture session | **High** | Capture-interruption handling, no false "saved", recording survives accessory loss; cannot be tested without hardware |
| R4 | No physical Duo → the headline claim is unverifiable before submission | **High** | Ledger marks Duo criteria `BLOCKED`; App Store copy must not claim unverified Duo behaviour |
| R5 | Nothing in this repo has been compiled (no Mac in this environment) | **Critical for delivery** | First Mac session must be a build/typecheck pass before any other work |
| R6 | Reviewer rejects for camera use without clear purpose | Medium | Accurate usage strings, visible recording state, no hidden capture |
| R7 | Wedge is copied quickly once the hardware is common | Medium | Accepted. Speed is the strategy; depth comes from interview workflow, not the display trick |
| R8 | Interviewee finds an on-screen prompt distracting rather than helpful | Medium | Cheap to test: a single real interview answers it. Listed as the first user-evidence question |

## 10. Assumptions requiring validation

**Technical** — see `SDK_CAPABILITY_REPORT.md` §6 (A1–A6). The two that matter most: the Duo outer display is
a scene accessory (A1), and folding does not kill capture (A4). Both need hardware.

**Product** — untested, and more likely to be wrong than the technical ones:

| ID | Assumption | Cheapest test |
|---|---|---|
| P1 | Subjects answer better when they can read the question | 3 real interviews, with and without |
| P2 | Creators will prepare a question deck in advance rather than improvising | Ship with one sample deck; observe whether anyone creates a second |
| P3 | Timestamped markers actually save editing time | Ask one editor to cut from a marker list |
| P4 | A phone-sized second surface is readable enough at interview distance | Measure at 1 m and 2 m (S14) |
| P5 | "Turn one iPhone into a camera operator and interview producer" is the line that lands | Landing-page copy test before build-out |

**P1 is the assumption the whole product rests on, and it is the one with no evidence at all.** It is also the
cheapest to test — one afternoon with three interviewees. That test should happen before any V1 investment.

## 11. Decisions made without asking (conservative and reversible)

| # | Decision | Rationale | Reversible? |
|---|---|---|---|
| D1 | Subject display built on `sceneAccessory` + `ExternalNonInteractiveAccessory` | Only documented second-surface API; works on external display/AirPlay today | Yes — isolated behind a protocol |
| D2 | **No live preview on the subject surface in V0**, flag-gated off | Brief forbids faking a preview; capability unverified | Yes — flip one flag once verified |
| D3 | No hinge/fold-specific code | No such API exists; writing it would be inventing API | Yes — additive when API appears |
| D4 | Deployment target **iOS 26.0**, Duo path gated `@available(iOS 27.0, *)` | Keeps the fallback app installable on today's phones while the accessory path stays available on 27 | Yes — raise the floor to 27.0 |
| D5 | Local-only persistence via SwiftData | Matches privacy stance; no backend to operate | Yes |
| D6 | Markers export as CSV **and** plain text | CSV for tooling, text for humans; both trivial | Yes |
| D7 | Core logic in an SPM package (`PromptCamKit`), app is a thin shell | Makes the state machine and decks testable with `swift test`, no Simulator needed | Yes |
| D8 | Xcode project generated from a checked-in `project.yml` (XcodeGen) | No Mac here to author a `.xcodeproj` safely; a spec is reviewable and diffable | Yes — commit a real `.xcodeproj` later |
| D9 | Recording is **not** stopped when the accessory disappears | Losing the subject screen is not a reason to lose the take | Yes |
| D10 | Countdown is cancellable and never auto-starts recording without reaching zero | Avoids accidental captures | Yes |

## 12. Open questions for the founder

Answers would change architecture or scope; none block V0 implementation, and each has a working default.

1. **Do you have, or can you get, a physical iPhone Duo?** Without one, S15 and UAT 6/12 stay `BLOCKED`
   permanently and the App Store listing must not claim Duo behaviour. *Default: proceed, mark blocked.*
2. **Where did `CameraCaptureAccessory`, `onHingeChange`, reserved regions and "Device Hub" come from?** If
   from a real NDA/beta SDK you have access to, that changes the design materially and I should use it. If from
   a rumour or a generated summary, my `sceneAccessory`-based design stands. *Default: assume not real.*
3. **Ship first on external display / AirPlay, or hold for Duo hardware?** Shipping now gets real user
   evidence on P1–P3 months earlier. *Default: build so either is possible; recommend shipping.*
4. **iOS floor: 26.0 or 27.0?** 27.0-only is simpler code but a much smaller install base at launch.
   *Default: 26.0 with gating.*
5. **Is "subject can read the question" the feature you'd put in the App Store subtitle**, or is the marker/
   editing workflow the real hook? This decides what V1 deepens. *Default: the subject-facing surface.*
