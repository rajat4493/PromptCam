# PromptCam

**Turn one iPhone into a camera operator and an interview producer.**

You get the camera, the controls and your question list. The person you're
interviewing gets the current question, the countdown and the recording status
on a second screen.

---

## ⚠ Status: written, never compiled

This repository was authored in a Linux environment with **no Mac, no Xcode, no
iOS SDK and no Swift toolchain** (the Swift download hosts were blocked by
network policy). Consequently:

- **No file here has ever been compiled.**
- The **112 automated test cases have never been executed.**
- `project.yml` has never been run through XcodeGen.
- Nothing has run on a simulator or a device.

Treat this as a complete, carefully structured first draft awaiting its first
build. Expect compiler errors on the first attempt — especially in
`Sources/PromptCamiOS/Platform/`, which deliberately concentrates every
unconfirmed Apple API in one place.

**Start here:** [`docs/MAC_VALIDATION.md`](docs/MAC_VALIDATION.md)
**Non-technical overview:** [`docs/HUMAN_SUMMARY.md`](docs/HUMAN_SUMMARY.md)
**What is actually proven:** [`docs/VERIFICATION_LEDGER.md`](docs/VERIFICATION_LEDGER.md)

---

## Requirements

| | |
|---|---|
| Xcode | 27.1 or later (iOS 27.1 SDK) |
| Deployment target | iOS 26.0 |
| Swift | 6.0, strict concurrency |
| Dependencies | **None** |
| XcodeGen | for project generation (`brew install xcodegen`) |

---

## Setup and run

### 1. Run the core tests — no simulator or device needed

`PromptCamCore` is a plain Swift package with no Apple-platform dependency, so
its tests run on any machine with a Swift toolchain:

```bash
swift test
```

### 2. Check the architectural invariants — runs anywhere with Python 3

```bash
python3 Scripts/static_review.py
```

This verifies that the core layer imports no platform framework, that every
unconfirmed iPhone Duo symbol stays inside `Platform/`, that the app never
identifies the device by model name or screen size, that `UIScreen.main` is
never used, that brackets balance, and that no source file falsely claims to be
verified. **It is not a compiler** — passing it says nothing about whether the
code builds.

### 3. Generate and open the iOS app

```bash
brew install xcodegen
xcodegen generate
open PromptCam.xcodeproj
```

Then set your development team in **Signing & Capabilities**, change the bundle
identifier from `com.example.promptcam.PromptCam`, choose a simulator and press
⌘R.

### 4. Enable the iPhone Duo code paths

The Duo paths are **off by default**, so an unconfirmed API signature cannot
block the baseline build or the test run. Once steps 1–3 are clean, add
`PROMPTCAM_DUO` to `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in `project.yml` and
regenerate. See [`Sources/PromptCamiOS/Platform/README.md`](Sources/PromptCamiOS/Platform/README.md).

---

## Architecture in one picture

```
PromptCamCore   — Foundation only. Models, recording state machine,
  (15 files)      session engine, export, service protocols.
                  Testable with no Apple SDK.
        ▲
        │  protocols only
        ▼
PromptCamiOS    — SwiftUI, AVFoundation, SwiftData.
  (25 files)      Platform/ holds every unconfirmed Apple API,
                  behind the PROMPTCAM_DUO flag.
```

Two rules do most of the work:

- **`.saved` has exactly one inbound edge**, and it originates in
  AVFoundation's own "recording finished" callback. The app cannot structurally
  claim an interview was saved before the operating system confirmed the file.
- **The subject's screen renders from a type that cannot hold director data.**
  Upcoming questions and operator controls have nowhere to leak to.

Both surfaces read from one `InterviewSessionEngine`, so they cannot disagree
about the current question, the countdown, the recording state or the duration.
There is no message passing to go wrong.

---

## What V0 does

- Create, rename, delete decks; add, edit, delete, reorder questions; one
  genuinely usable sample deck; local persistence
- Choose what the subject sees before recording; explained permission requests
  with a recovery path for each refusal state
- Director console: viewfinder, current and next question, navigation, record
  and stop, duration, microphone level, timestamp markers, dismissal protection
  while recording
- Subject screen: current question in large high-contrast type, countdown,
  recording status, a subtle cue on question change — and nothing director-only
- Local video storage, interview metadata, timestamped question changes and
  markers, playback review, video and marker export (CSV and plain text)
- Complete function on an ordinary iPhone, with second-screen controls hidden
  entirely rather than shown broken

Deliberately excluded: AI, question generation, transcription, subtitles,
editing, cloud, accounts, teams, social publishing, analytics, subscriptions,
Android, general teleprompter, pose coaching, livestreaming, themes.

---

## Privacy

Everything is local. There is no networking code in either layer, zero
third-party dependencies, and no analytics. Recordings are never uploaded.

A captured file is never deleted because a later step failed — if filing a
recording fails, the app keeps the video and tells you where it is.

---

## Documentation

| Document | What it is for |
|---|---|
| [`HUMAN_SUMMARY.md`](docs/HUMAN_SUMMARY.md) | Plain-English status. **Read first** |
| [`MAC_VALIDATION.md`](docs/MAC_VALIDATION.md) | 20-step first-build handover |
| [`VERIFICATION_LEDGER.md`](docs/VERIFICATION_LEDGER.md) | What is proven, at which tier |
| [`ASSUMPTIONS.md`](docs/ASSUMPTIONS.md) | Supplied vs documented vs assumed |
| [`APPLE_API_CORRECTIONS.md`](docs/APPLE_API_CORRECTIONS.md) | 20 pre-filled questions for the first Mac session |
| [`PRODUCT.md`](docs/PRODUCT.md) | Problem, user, wedge, scope, risks |
| [`SDK_CAPABILITY_REPORT.md`](docs/SDK_CAPABILITY_REPORT.md) | Reconnaissance findings and evidence |
| [`UAT.md`](docs/UAT.md) | 17 manual test cases for a non-specialist tester |
| [`ENGINEERING_HANDOVER.md`](docs/ENGINEERING_HANDOVER.md) | Architecture, state ownership, failure strategy |
| [`THEDUCK_LEARNING.md`](docs/THEDUCK_LEARNING.md) | Reusable delivery lessons |
