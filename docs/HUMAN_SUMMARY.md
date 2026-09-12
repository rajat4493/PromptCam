# PromptCam — Where things actually stand

Plain English. No jargon. Read this first.

---

## The one-paragraph version

PromptCam is designed to turn a single iPhone into both a camera and an
interview producer: you get the camera controls and your question list, the
person you're interviewing gets the current question on a second screen. The
complete app has been **written** — roughly 5,600 lines of Swift across 45
files, plus 112 automated tests. **None of it has been compiled or run**,
because the machine I worked on was a Linux server with no Mac, no Xcode, and
no way to install Swift (the download servers were blocked by network policy).
So the right way to think about this repository is: a finished, carefully
structured first draft that has never been switched on.

---

## What has been built

**The core logic** — decks of questions, the recording lifecycle, the countdown,
marker timestamps, question tracking, export formats. This part is deliberately
written in plain Swift with no Apple frameworks at all, which means it can be
tested on any machine without a phone or a simulator.

**The app itself** — the camera screen for you, the question screen for your
subject, deck editing, a permissions flow, an interview library with playback,
and export of both the video and the marker list.

**One design decision worth knowing about.** The app can never tell you an
interview was saved unless the operating system has actually confirmed the file
exists. This isn't a check bolted on — the code is structured so that the
"saved" state is only reachable from one place, and that place is the system's
own confirmation callback. If saving fails, the app keeps your video file and
tells you where it is. It never deletes a recording to tidy up after itself.

**A second design decision.** The subject's screen is rendered from a small data
structure that physically cannot hold your upcoming questions, your notes, or
your controls. So the interviewee can't accidentally see what they shouldn't —
not because someone remembered to hide it, but because there's nowhere for it
to go.

---

## What you can personally test right now

**Nothing.** Not yet, and I want to be direct about that rather than dress it up.

You need a Mac with Xcode first. Once you have that, `docs/MAC_VALIDATION.md`
walks through it step by step. Realistically:

- **Steps 1–7** (about half a day, including fixing compiler errors) get you a
  running app on a simulator with the tests passing.
- After that, `docs/UAT.md` cases **4 and 11** can be done on a simulator —
  creating and editing decks, and checking the layout rotates properly.
- Cases **1, 2, 3, 5, 8, 9, 10, 14, 15, 16, 17** need a real iPhone, because the
  simulator has no camera. No camera means no real recording, no audio levels,
  and no interruptions to test.
- Cases **6, 7, 12, 13, 16** need a second display or an iPhone Duo.

**One genuinely useful shortcut:** the second-screen feature is built on an
Apple API that, according to Apple's own published documentation, also works
with ordinary external displays and AirPlay. So you may be able to test the
whole subject-screen experience by connecting an iPhone to a TV or an Apple TV —
no foldable required. Worth trying early, because it would de-risk the core idea
months before Duo hardware is in your hands.

---

## What has been proven

Honestly, not much — but the little that has been proven was genuinely executed,
not asserted:

- There is no Apple toolchain and no Swift compiler in this environment. I
  checked, and I tried three separate ways to install Swift. All blocked.
- Apple's published documentation **does** contain a real second-screen API
  (`sceneAccessory`, iOS 27.0), and I read its actual declarations and code
  samples rather than recalling them.
- A script I wrote and ran (`Scripts/static_review.py`) confirms the app's
  structural rules hold: the core logic imports no Apple frameworks; every
  unconfirmed iPhone Duo API is confined to five isolated files; the app never
  identifies the device by model name or screen size; `UIScreen.main` appears
  nowhere; and no source file falsely claims to be verified. This passes.

That script proves the **shape** of the code. It is not a compiler and it proves
nothing about whether the code works.

---

## What remains assumed

**The big one: that iPhone Duo's outer display is available to apps like
PromptCam at all.** The whole product rests on it, and it is untested.

There's a wrinkle here you should know about, because it affects how much to
trust the technical plan. You supplied a set of Apple APIs for iPhone Duo —
`CameraCaptureAccessory`, `onHingeChange`, reserved regions, Device Hub,
Xcode 27.1. I searched Apple's published documentation for all of them from
here. I found `sceneAccessory` exactly as described. I found **none** of the
Duo-specific ones, and Apple's published release notes showed iOS 27 and
Xcode 27 as release candidates with no 27.1.

The most likely explanation is simply that the Duo APIs are newer than the
public documentation I could reach — a device announced right about now, with
its tools arriving in 27.1. That's consistent with what you told me, and I've
built to your specification. But it does mean **I could not confirm a single
Duo API signature**, so the first Mac session should expect to correct some of
them. The code is arranged so that costs you five files, not a rewrite.

**The bigger assumption, which isn't technical at all:** that interviewees
actually give better answers when they can read the question themselves. That's
the premise of the entire product and there is no evidence for it either way.
It would take one afternoon and three interviews to find out. I'd do that before
building anything else.

---

## What is blocked by unavailable hardware or credentials

| Blocked | What it needs |
|---|---|
| Compiling anything at all | A Mac with Xcode 27.1 |
| Running the 112 tests | A Mac (or any machine with Swift installed) |
| Recording an actual video | A physical iPhone — the simulator has no camera |
| Anything about iPhone Duo | An iPhone Duo simulator, then a real iPhone Duo |
| Confirming the Duo API names | A Mac with the iOS 27.1 SDK |
| App Store signing | Your Apple Developer team ID |
| Whether the subject screen can show a live camera view | A Mac first, then real hardware |
| Reviewing App Store guidelines | A person reading them — I couldn't fetch them |

---

## What I deliberately left out

Everything on the exclusion list: no AI, no auto-generated questions, no
transcription, no subtitles, no video editing, no cloud, no accounts, no teams,
no social publishing, no analytics, no subscriptions, no Android, no general
teleprompter, no pose coaching, no livestreaming, no themes.

Three things I left out that you might have expected:

1. **A live camera preview on the subject's screen.** Whether it's even possible
   is unknown, and the brief said not to fake it. There's a switch in the code
   that turns it on the moment someone confirms it works. Until then the
   subject sees the question and the recording status, which is the part that
   actually matters.

2. **The camera-direction coordinator.** One of the supplied APIs had five
   unknowns in a single function call — the type name, three argument labels,
   and what kind of value it hands back. Guessing would either break the build
   or, worse, produce code that silently never runs. PromptCam records with the
   rear camera, which doesn't change when the phone folds, so nothing needs it.
   I left a documented placeholder with the five things to check.

3. **Hinge-angle-driven layout.** Your own guidance said to use reserved regions
   and standard containers for layout, and to treat hinge data as being for
   interaction and effects. So I did that.

---

## What should be built next

In this order:

1. **Get it to compile.** Half a day on a Mac. Nothing else can start until this
   does.
2. **Run the tests.** They cover all 23 scenarios you asked for. Expect some to
   need fixing on first run.
3. **Record one real interview on a real iPhone.** This is the first moment
   PromptCam becomes a real thing.
4. **Try the subject screen on a TV or Apple TV.** If this works, you can test
   the core idea now instead of waiting for hardware.
5. **Do the three-interview experiment.** Does a visible question actually help?
   This is cheap and it's the question that decides whether to keep going.
6. **Then, and only then**, worry about iPhone Duo specifics.

Note that steps 4 and 5 don't need a Duo at all. If the second-screen idea works
on an external display, that's a shippable product on its own, and Duo becomes
an upgrade rather than a dependency.

---

## The exact commands

**Run the logic tests** (any Mac, no simulator or phone needed):

```bash
cd PromptCam
swift test
```

**Check the structural rules** (works anywhere with Python):

```bash
python3 Scripts/static_review.py
```

**Build and open the app** (Mac with Xcode 27.1):

```bash
brew install xcodegen
cd PromptCam
xcodegen generate
open PromptCam.xcodeproj
```

Then pick a simulator in Xcode and press ⌘R.

Full details, including what to do when something doesn't compile, are in
`docs/MAC_VALIDATION.md`.

---

## Manual Apple Developer and App Store steps still to do

None of these can be done for you:

1. **Apple Developer Program membership** — $99/year, if you don't have it.
2. **Set your team ID** in Xcode's Signing & Capabilities. It's deliberately
   blank in the project file, because a committed team ID breaks everyone else's
   build.
3. **Change the bundle identifier** from `com.example.promptcam.PromptCam` to
   your own. Must be done before any device build.
4. **Create the App Store Connect record** — name, subtitle, category, age
   rating.
5. **Privacy questionnaire** — the answer is genuinely "no data collected".
   PromptCam has zero third-party dependencies and no networking code at all.
6. **Screenshots** on real devices.
7. **Read the App Store Review Guidelines** on camera use and external displays.
   I couldn't fetch them, so this is unverified.
8. **The one rule I'd ask you to hold to:** don't claim iPhone Duo behaviour in
   the App Store listing until someone has actually run PromptCam on an iPhone
   Duo. Until then, "works with a second display" is true and "designed for
   iPhone Duo" isn't yet.
