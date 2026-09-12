# Scope changes

Every deviation from the original brief, with its reason and who decided it.
Nothing here was added because it was easy or interesting.

## Locked V0 scope

Unchanged from the brief: interview decks, recording preparation, director
recording interface, subject-facing display, recording output with markers and
export, ordinary-iPhone fallback.

Exclusions honoured in full — no AI, question generation, transcription,
subtitles, editing, cloud, accounts, teams, social publishing, analytics,
subscriptions, Android, general teleprompter, pose coaching, livestreaming, or
multiple themes. **Nothing on the exclusion list was added.**

## Changes

| # | Change | Reason | Decided by |
|---|---|---|---|
| SC-1 | Two-layer split renamed and hardened: `PromptCamCore` (Foundation only) + `PromptCamiOS`, with `Scripts/static_review.py` failing the build if the boundary is crossed | Environment override mandated the split; an enforced check beats a documented intention | Product owner (override) |
| SC-2 | SwiftData moved out of Core into the iOS layer; Core uses value types | Core must import no platform framework, so it stays testable without an Apple SDK | Product owner (override) |
| SC-3 | Repository protocols changed from synchronous to `async` | SwiftData's `ModelContext` is main-actor-bound; forcing it through a synchronous protocol required an `assumeIsolated` that crashes if the assumption is ever wrong | Claude (implementation correctness) |
| SC-4 | Subject display switched from `ExternalNonInteractiveAccessory` to `CameraCaptureAccessory` | Supplied guidance names the camera-app accessory. Same `sceneAccessory`/`onAvailabilityChange` shape, so the seam was unchanged | Product owner (supplied guidance) |
| SC-5 | All unverified Duo API isolated behind `PROMPTCAM_DUO`, **off in Debug and Release** | One wrong signature must not block the baseline build or the test run | Claude, endorsed by override ("centralize uncertain APIs") |
| SC-6 | Added a `Duo` build configuration and a "PromptCam (Duo)" scheme | Review finding: with the flag absent from both configurations, the committed app was an ordinary single-screen camera app | Product owner (review) |
| SC-7 | `AVCaptureDeviceDirectionCoordinator` deliberately not implemented | Five simultaneous unknowns in a startup path; the rear-camera workflow does not need it. Override explicitly permits a documented placeholder | Claude, per override §6 |
| SC-8 | Live subject preview flag-gated and off | Brief forbids faking a preview; capability unverified | Brief + Claude |
| SC-9 | Deployment target iOS 26.0 rather than 27.x, Duo paths runtime-gated | Keeps the ordinary-iPhone app installable on phones that have not upgraded | Claude (reversible; documented as D4) |
| SC-10 | Persistent `Recovery/` directory added to the storage model | Review P0: a "preserved" recording was being deleted by the next session's cleanup. "Kept" was not true | Product owner (review) |
| SC-11 | Single idempotent finalisation path; `SessionResultSnapshot` gained a stable identifier; recording repository upserts | Review P0: an interruption followed by a late completion callback orphaned the video and could have duplicated the library row | Product owner (review) |
| SC-12 | Stop queued until capture is confirmed; 8-second startup watchdog | Review P0: stop could reach an output that had not started, stranding the session in `.finishing` | Product owner (review) |
| SC-13 | Capture service made per-session (`AppEnvironment.PreparedSession`) | Review P1: one single-consumer `AsyncStream` was shared across session models, and `captureTask` was cancelled but never cleared | Product owner (review) |
| SC-14 | In-app **Recover** share action for preserved files | Review P1: "your video has been kept" was not actionable — a sandbox path is not a recovery mechanism | Product owner (review) |
| SC-15 | `hasSeededSample` flag persisted | Review: seeding on "is the database empty?" resurrected a deliberately deleted sample deck | Product owner (review) |
| SC-16 | `docs/SDK_CAPABILITY_REPORT.md` rewritten | Review: its executive summary asserted that real APIs do not exist — dangerous context for a future coding agent | Product owner (review) |
| SC-17 | This `/duck` ledger created | Review: TheDuck rules require the milestone ledger under `/duck`, not only long-form docs under `/docs` | Product owner (review) |
| SC-18 | **Orchestration moved from the iOS layer into `PromptCamCore`** as `InterviewSessionCoordinator`; `DirectorSessionModel` reduced to mirroring and timer scheduling | Round-2 review: the lifecycle defects lived in code that no test could reach, because it imported SwiftUI and AVFoundation. Moving it behind the existing protocols made the real orchestration testable | Product owner (review) |
| SC-19 | `CaptureEvent.runtimeError` added, distinct from `recordingFailed` | A runtime error does not mean the writer has finished. Conflating them caused the app to move a file AVFoundation might still be writing, and to discard the completed file that arrived afterwards | Product owner (review) |
| SC-20 | `DuoRelease` configuration; Duo scheme's Archive and Profile actions pinned to it | Archive defaults to Release, so archiving the Duo scheme would have shipped an App Store build with the headline feature compiled out, silently | Product owner (review) |
| SC-21 | No timeline event is recorded until capture is confirmed; the opening question is written at offset zero on confirmation | Markers and question changes taken during start-up pointed at no file and were invalidated by the rebase. Gating is simpler and more truthful than rebasing pending events | Product owner (review) |
| SC-22 | Bounded `finalisationTimedOut` backstop | Reconciliation must stay open after a failure, but not forever — otherwise a completion callback that never arrives means the file is swept and lost | Claude, per review guidance |
| SC-23 | **Merged a parallel fix (`90e09c3`) for the same five findings.** Kept this branch's Core-coordinator architecture; adopted two fixes from the parallel work and its iOS unit-test target | Two agents addressed the round-2 review independently. Details below | Claude (merge), reconciling both |

## The parallel-fix merge (SC-23)

`90e09c3` fixed the same five findings on the same branch, at the same time.
The two solutions converged on `CaptureEvent.runtimeError` and on a
`DuoRelease` configuration pinned to the Duo scheme's Archive action, and
diverged on where orchestration should live.

| Area | This branch | `90e09c3` | Merged outcome |
|---|---|---|---|
| Orchestration | moved into `PromptCamCore` as `InterviewSessionCoordinator` | stayed in `DirectorSessionModel` | **Core coordinator kept.** It makes the orchestration tests runnable under `swift test` with no Xcode, which matters because the review's point was that the orchestration was untestable |
| Orchestration tests | 27 cases in `PromptCamCoreTests` | 5 cases in a new `PromptCamiOSTests` Xcode target | **Both kept, re-scoped.** All five parallel scenarios were already covered in Core; the iOS target now tests what the wrapper alone owns — mirroring, event consumption, teardown |
| Interruption's preserved path | exposed `temporaryCapturePath` immediately | set to `nil` until the file is final | **Theirs adopted.** It caught a real hole here: exposing an in-flight path offers a Recover action for a file that may still be open |
| Sweeper protection | skipped the in-flight capture only | also skipped every path an existing library row references | **Theirs adopted.** A recorded `preservedFilePath` is a promise the sweeper must not break |
| Timeline gating | engine-level `isCaptureConfirmed`, automatic | `recordTimeline:` parameter on `goToQuestion` | **Engine gating kept** — it cannot be forgotten at a call site |
| Permission injection | concrete `AVPermissionService` | concrete | **Changed to the `PermissionService` protocol**, so the wrapper is testable |

## Proposed and rejected

| Proposal | Why rejected |
|---|---|
| Substitute a second `UIWindow` for the accessory so the feature "works" everywhere | Would fabricate the one capability the product depends on. Override forbids it explicitly, and it would have demoed convincingly — which is what makes it dangerous |
| Record with a Duo front camera because new front-camera APIs exist | PromptCam films *someone else*. A new API is not a reason to change what the product does |
| Auto-advance questions on detected silence | Would talk over a thinking interviewee. Actively harmful |
| Multi-cam capture | Nobody asked; doubles the failure surface |
