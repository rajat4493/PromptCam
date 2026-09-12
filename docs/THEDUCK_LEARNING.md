# TheDuck — Learning Capture: PromptCam

Not marketing copy. Delivery memory, written so the next foldable project
starts further along than this one did.

---

## 1. Where the original idea was ambiguous

| Ambiguity | Why it mattered | How it was resolved |
|---|---|---|
| "Outer display" was treated as a screen the app draws on | It is not. It is a *scene accessory* the **system** presents when it decides to, and the app must work without it | Designed for absence first: `.unsupported` is a first-class state and the fallback is the compliant baseline, not a consolation |
| "Optionally their preview" | Buried an unproven capability inside a checkbox | Split into a documented assumption, a feature flag defaulting off, and an option stripped at the engine boundary |
| "A camera and director console" vs "prompt and preview screen" | Read as two UIs to keep in sync | Reframed as one state with two projections. Nothing to sync |
| "Useful on an ordinary iPhone" | Unclear whether that meant degraded or complete | Made complete. Apple's own documentation requires the app to be fully functional without an accessory, which settled it |
| Which camera records the subject | Duo introduces several new *front* cameras; easy to drift onto one | Stated the intent in the adapter's own documentation: rear camera records the subject, and a new front-camera API is not a reason to use the front camera |
| "Recording state" | Sounded binary | Eight states, and the distinctions earn their keep — `.finishing` vs `.saved` is exactly where false success lives |

**The pattern:** every ambiguity was about **who owns a decision** — the app,
the system, or the user. Naming the owner resolved each one.

---

## 2. Assumptions confirmed and rejected

### Confirmed
- A real second-surface API exists: `sceneAccessory`, `SceneAccessoryContent`,
  `ExternalNonInteractiveAccessory`, `onAvailabilityChange`, iOS 27.0+, plus the
  UIKit `UISceneAccessory` equivalents. Read directly, with code samples.
- Its semantics match what the product needed: the system decides presentation,
  the app declares content, and the app must function without it.
- Apple's own documented example for it is a presentation preview on a second
  screen with controls staying on the first — structurally identical to a
  director console plus a subject prompt.
- Scene-based lifecycle is mandatory in the iOS 27 SDK.

### Rejected
- **That the brief's API list was reliable.** `sceneAccessory` was exactly
  right; `CameraCaptureAccessory`, `onHingeChange`, reserved regions and
  "Device Hub" were absent from every published index I searched.
- **That "Xcode 27.1 / iOS 27.1" was a known quantity.** Apple's published
  release notes ended at Xcode 27 RC and iOS 27 RC.
- **That a hinge API would be needed.** Even taking the supplied guidance at
  face value, it says to use reserved regions and arrangement APIs for layout
  and to treat hinge data as interaction and effects. The layout problem was
  solved with size classes.

### Still open
- Whether the Duo outer display reaches apps through this API at all.
- Whether a live preview can render on a non-interactive accessory.
- Whether folding mid-recording tears down the capture session. **The
  highest-risk unknown in the project, and there is no API to observe it.**

---

## 3. Where a coding agent could easily have produced false confidence

This is the most reusable section. Each of these was a real fork in the road.

**1. Writing the supplied snippets verbatim and declaring the feature done.**
The snippets look authoritative. Pasting `AVCaptureDeviceDirectionCoordinator(view:deviceTypes:changeHandler:)`
into the app's startup path would have produced something that *reads* finished.
It contains five unknowns at once — type name, three labels, the handler's
parameter type ("a map", type unnamed), actor isolation, availability. If the
handler type is wrong it may compile and silently never fire, which is worse
than a build error. **What worked:** not implementing it, returning `false`,
and documenting the five unknowns and five completion steps.

**2. Claiming the tests pass.** 112 test cases exist. Zero have run. The
sentence "tests written and passing" would have been a lie a founder could not
detect. **What worked:** a scoreboard at the top of the ledger, and a script
that fails if any source file asserts `VERIFIED`.

**3. Substituting a second `UIWindow` for the accessory.** Technically easy,
would have demoed beautifully on any iPhone, and would have been a fabrication
of the one capability the product depends on. **What worked:** the no-op branch
renders *nothing* and reports unavailable, with a comment saying why.

**4. Faking the live preview.** A grey rounded rectangle labelled "Preview"
would have passed a screenshot review. **What worked:** the option is stripped
at the engine boundary, and the placeholder reads "Preview unavailable".

**5. Treating documentation presence as verification.** I read real declarations
from Apple's docs. That is much better than recall and still nowhere near a
compiler. **What worked:** a `DOC-VERIFIED` label distinct from
`COMPILE-VERIFIED`, and a ten-second `swiftc -typecheck` probe as step 2 of the
Mac handover.

**6. Letting the environment blocker justify doing less.** No compiler could
have excused shipping a skeleton. It is instead a reason to be precise about
what is unproven. **What worked:** building the whole thing and labelling every
part honestly.

**7. Trusting my own checker.** The static review's first run reported six
failures. One was real (a callback named `onAvailabilityChange` colliding with
Apple's modifier); five were my regex flagging *disclaimers* like "not yet
verified" as claims. Accepting all six would have meant deleting good
disclaimers. Dismissing all six would have hidden the real bug. **What worked:**
reading each flagged line before acting.

---

## 4. Which APIs were genuinely useful

| API | Verdict |
|---|---|
| `sceneAccessory` + `onAvailabilityChange` | **Genuinely useful.** Exactly the right shape: declarative content, system-owned presentation, an availability callback. The whole subject-display design rests on it |
| Size classes | **Most useful thing of all**, and not new. Solved the fold-layout problem without a single foldable API |
| `reservedRegions` (supplied) | Plausibly useful for one narrow job: keeping the record button off the hinge. Nothing else needed it |
| `ArrangementView` (supplied) | Not needed. `HStack`/`VStack` on a size class did the same job portably |
| `onHingeChange` (supplied) | Marginal. Warns before a take; drives no layout |
| `AVCaptureDeviceDirectionCoordinator` (supplied) | Irrelevant to a rear-camera workflow. Front-camera APIs are the wrong tool for filming someone else |
| `AVCaptureMultiCamSession` | Considered, not used. The product needs one camera and two *content* surfaces, which is not the same thing |

**Lesson: the marquee foldable APIs were the least useful ones.** The value came
from a second-surface content API plus adaptive layout primitives that have
existed for a decade.

---

## 5. What required physical hardware

Unavoidably device-only:
- Any real recording — **the Simulator has no camera**, so capture, audio levels
  and interruptions cannot be exercised there at all. Easy to forget when
  planning a simulator-only test pass.
- Readability at distance. A measurement, not a design opinion.
- Interruption by a real phone call.
- Whether folding tears down capture.
- Live preview feasibility and thermal cost.
- Marker accuracy against a real clock.

Testable without a foldable, which was the most valuable discovery of the
project: because the underlying API is documented for external displays and
AirPlay, **the entire subject-display experience may be testable on a TV or an
Apple TV today.** That decouples validating the core product idea from hardware
availability.

---

## 6. What to ask earlier next time

Five questions, in priority order, before writing any code:

1. **"Do you have the hardware, and do you have the SDK?"** Asked in minute one,
   not after the architecture is designed. It changes what "done" means.
2. **"Where did these API names come from — did you compile them, read them in
   Xcode, or read them in an announcement?"** The distinction is everything, and
   it is a completely neutral question to ask.
3. **"Can this feature be tested on hardware you already own?"** The
   external-display insight would have reframed the schedule on day one.
4. **"Which single claim, if false, kills the product?"** Then check that first.
   Here it was "the outer display is available to third-party apps".
5. **"What is the cheapest test of the *user* assumption?"** The riskiest
   assumption in PromptCam is not an API. It is whether a visible question
   actually helps an interviewee — untested, and answerable in an afternoon.

---

## 7. Patterns worth reusing

**Architecture**

- **Two layers with an enforced boundary.** Platform-free core, thin platform
  shell, and a script that *fails* if the boundary is crossed. Intent in a
  document decays; intent in a failing check does not.
- **Concentrate uncertainty in one directory behind one compile flag, off by
  default.** A wrong signature then costs five files and never blocks the
  baseline build or the test run. This is the single highest-leverage pattern
  here.
- **One state, two projections.** Synchronisation bugs between two surfaces are
  designed out, not tested out.
- **Make the privacy rule a type.** `SubjectSnapshot` has no field that could
  carry an upcoming question, so the rule cannot be violated by a careless edit.
- **Make the integrity rule a graph.** `.saved` has exactly one inbound edge,
  originating in the OS callback. "Don't report false success" stops being
  discipline and becomes topology.
- **Reject invalid transitions by throwing**, not by ignoring. A silent no-op
  hides the bug that caused it.
- **Inject the clock.** Determinism for free; no test sleeps.
- **Absence as a value.** `.unsupported` distinct from `.unavailable` is what
  makes "hide Duo-only controls cleanly" expressible.

**Verification**

- **A results vocabulary with tiers, and a rule that one tier never silently
  becomes another.** `STATICALLY_REVIEWED` → `VERIFIED` must require a compiler.
- **A scoreboard at the top of the ledger.** A reader who stops after ten
  seconds still learns the truth.
- **Executable invariant checks as a separate layer from unit tests.** Layer
  purity, symbol isolation, absence of device detection — none of it is visible
  to a unit test, all of it is decidable by reading source.
- **A self-check against false claims.** The honesty check turns the project's
  central rule into something machine-enforced.
- **Fetch real documentation instead of trusting recall**, and label it as
  documentation rather than verification. Downloading complete symbol indexes
  and grepping them turned "I think this API exists" into a countable result.
- **A ten-second probe as step 2 of the handover.** One `swiftc -typecheck`
  resolves the project's biggest open question before any other work.

**Delivery**

- **Sequence the handover so a baseline is green before uncertainty is
  introduced.** Steps 1–7 then step 8 matters more than it sounds: reversing it
  means one wrong signature blocks validating everything else.
- **A corrections file with the open questions pre-filled.** Twenty numbered
  questions, each pointing at the file and handover step that answers it. The
  Mac session starts with a worklist, not an investigation.
- **Name deliberate non-implementations explicitly.** "Not built, here is why,
  here are the five steps" is a deliverable. A plausible guess is a liability.

---

## 8. Features that sounded attractive and were excluded

| Excluded | Why it was tempting | Why it stayed out |
|---|---|---|
| Live preview on the subject screen | It is the obvious "wow" | Unverifiable, and faking it was forbidden. The question is the feature; the preview is garnish |
| Hinge-angle-reactive UI | Foldable-native and demo-friendly | No layout problem needed it. Would have been novelty |
| Multi-cam (record both cameras) | Technically possible since iOS 13 | Nobody asked for it. Doubles the failure surface |
| Auto-generated questions | One prompt away | The value is in asking well. Instant credibility loss |
| Transcription | Interviews are speech; it seems adjacent | Commodity, large, and unrelated to the wedge |
| Auto-advance questions on silence | Feels clever | Would talk over a thinking interviewee. Actively harmful |
| In-app editing | Markers are right there | Different product. Markers exist so editing happens elsewhere |
| Cloud sync | "Obviously" needed eventually | Local-only means nothing to breach, nothing to operate, no privacy review |
| `ArrangementView` for its own sake | New and Duo-flavoured | Standard containers already worked; the guidance itself warns against novelty adoption |

**The rule that did the work:** a feature enters V0 only when a success
criterion needs it. Not because it is easy, new, or impressive.

---

## 9. Product insights for the next Duo application

1. **A foldable's value is two audiences, not more pixels.** Every strong idea
   here came from asking "who sees what?" The winning question was never "what
   do I do with a bigger screen" but "what should the *other* person see?"
2. **Ask what the second surface must NOT show.** The privacy constraint shaped
   the architecture more productively than any feature did.
3. **Non-interactive is a feature.** The accessory cannot take input — which is
   exactly right for an interviewee. Constraints often encode good design.
4. **Design for the accessory's absence first.** Apple requires it, and it
   forces the app to be genuinely useful on the hardware people already own.
5. **Find the non-foldable path to the same value.** Second-surface value is
   real on an external display or AirPlay *today*. Testing the idea should never
   have been blocked on owning a foldable.
6. **Never identify a foldable by model name.** It breaks on the next device and
   is explicitly discouraged. Capability, never identity.
7. **The riskiest assumption in a hardware-led product is usually still a human
   one.** PromptCam's technical unknowns are documented and bounded. The
   unbounded one is whether interviewees give better answers when they can read
   the question — and that costs one afternoon to find out.

---

## 10. What I would do differently

- **Ask question 1 of §6 before Stage A.** I spent real effort on reconnaissance
  that a single question about the environment would have reframed.
- **Search Apple's documentation *first*, not after designing.** Downloading the
  symbol indexes took two minutes and was the highest-information action in the
  project. It should have been the very first thing.
- **Write the honesty check before the code, not after.** It caught a real bug
  and would have caught it earlier.
- **State the hardware-free test path in the product document.** The
  external-display insight arrived while writing the capability report; it
  belonged in the plan on day one, because it changes the whole schedule.
