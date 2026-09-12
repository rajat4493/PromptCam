# Milestone ledger

## M1 — Smallest credible PromptCam, honestly testable

**Opened:** 2026-09-12
**Verdict:** **NOT COMPLETE.** Code and documentation delivered; verification
boundary not crossed. M1 cannot close while nothing has been compiled.

### Exit criteria

| # | Criterion | Status |
|---|---|---|
| 1 | Repository and environment reconnaissance, with the blocker recorded | ✅ `VERIFIED_LINUX` |
| 2 | Product definition, challenged rather than accepted | ✅ done |
| 3 | Core/iOS separation with an enforced boundary | ✅ `VERIFIED_LINUX` (invariant check) |
| 4 | Deck management and persistence | ⬜ `STATICALLY_REVIEWED` → needs `swift test` |
| 5 | Recording state machine with invalid transitions rejected | ⬜ `STATICALLY_REVIEWED` |
| 6 | Ordinary-iPhone recording | ⬜ `REQUIRES_MAC`, then physical iPhone |
| 7 | Duo subject-display integration | ⬜ `REQUIRES_MAC` → `REQUIRES_DUO_SIMULATOR` → `REQUIRES_PHYSICAL_DUO` |
| 8 | Marker storage and export | ⬜ `STATICALLY_REVIEWED` |
| 9 | Failure handling, no false success, no silent deletion | ⬜ `STATICALLY_REVIEWED` (regression-tested, unexecuted) |
| 10 | Accessibility and adaptive layout | ⬜ `REQUIRES_MAC` |
| 11 | Automated tests for all 23 required areas | ⬜ 155 cases written, **0 executed** |
| 12 | Manual UAT document | ✅ 17 cases, `docs/UAT.md` |
| 13 | Verification ledger | ✅ `docs/VERIFICATION_LEDGER.md` + `VERIFICATION.md` |
| 14 | Human summary and engineering handover | ✅ |

### Review history

| Date | Reviewer | Verdict | Outcome |
|---|---|---|---|
| 2026-09-12 | Product owner | Strong architecture, honest docs, **do not start founder testing** — 3 P0 recording-safety defects, headline feature disabled | All 3 P0s and 4 P1s fixed in `973fbcc`; 18 regression tests added; SDK report rewritten; this ledger created |
| 2026-09-12 | Product owner (round 2) | **M1 reopened.** Two lifecycle holes remained, Release still excluded Duo, and the new tests did not exercise the orchestrator | Orchestration moved into `PromptCamCore` as `InterviewSessionCoordinator`; watchdog now stops capture; outcome persistence separated from file reconciliation; `DuoRelease` configuration pinned to the Duo scheme's Archive action; timeline gated on capture confirmation; 25 orchestration tests with scripted capture events |

### Why M1 is still open

Everything above is source and documentation. The verification boundary has not
moved: no compiler has seen this code. Further Linux-side feature work would
not change that, so the next legitimate gate is **Xcode 27.1 compilation**, not
more implementation.

### What closes M1

1. `swift test` green on a Mac (criteria 4, 5, 8, 9, 11).
2. Baseline build succeeds (criterion 6, partially).
3. One real interview recorded and played back on a physical iPhone.
4. UAT case 17 — no false "saved" — passing.

Criterion 7 can lag: it needs hardware that may not exist yet, and the ledger
records it as blocked rather than pretending otherwise.

### Next milestone (not opened)

**M2 — Validated wedge.** Answer the one assumption no code can settle: do
interviewees give better answers when they can read the question? Three real
interviews, with and without. See `ASSUMPTIONS.md` P1/P6.
