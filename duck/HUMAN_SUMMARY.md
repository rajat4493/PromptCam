# Human summary

Full version: [`../docs/HUMAN_SUMMARY.md`](../docs/HUMAN_SUMMARY.md).

## Where things stand, in one paragraph

PromptCam is written — about 6,000 lines of Swift across 47 files, plus 130
automated tests — and **none of it has been compiled**, because this work
happened on a Linux server with no Mac, no Xcode, and no way to install Swift
(the download servers are blocked by network policy). A review then found three
serious bugs in how recordings were handled, all of which are now fixed. Treat
this as a carefully built first draft that has never been switched on.

## What you can test right now

**Nothing yet**, and I would rather say that plainly than dress it up.

You need a Mac with Xcode. `docs/MAC_VALIDATION.md` walks through it. Roughly
half a day, including fixing the compiler errors that a never-compiled codebase
always has, gets you a running app with the tests passing. Then:

- **Simulator:** create and edit decks, check the layout rotates properly.
- **Real iPhone:** everything about actual recording. The simulator has no
  camera, so it cannot test capture, audio levels, or interruptions at all.
- **Second display:** the subject screen.

## The shortcut worth trying early

The second-screen feature may work with ordinary external displays and AirPlay,
not just iPhone Duo. If so, you can test the whole subject-screen experience by
connecting an iPhone to a TV or an Apple TV — **no foldable needed**. That would
let you validate the core idea months before Duo hardware is in your hands.

## What was fixed after review

Three bugs that could have cost someone a real interview:

1. **A recording the app promised to keep was being deleted** when the next
   interview started. Files worth keeping now move to a separate folder the
   cleanup cannot reach.
2. **A phone call mid-interview could leave the video stranded** — saved to
   disk with nothing in the app pointing at it. There is now one path that
   handles a file arriving late, and it never claims the interview saved when
   it didn't.
3. **Tapping stop in the first moment of recording could hang the app** in
   "Saving" forever. Stop is now held until recording has genuinely begun, and
   a timer gives up with an explanation if it never does.

Also: if an interview doesn't save, you can now actually **recover the video**
from the interview's details screen — before, the app just printed a file path,
which is not something you can act on.

## What is still assumed

The big technical one: that iPhone Duo's outer display is available to apps
like PromptCam. Built to Apple's guidance, but unconfirmed by a compiler.

The bigger one isn't technical at all: **that interviewees actually give better
answers when they can read the question themselves.** That is the premise of
the whole product and there is no evidence either way. Three interviews, one
afternoon. I would do that before building anything else.

## The commands

```bash
swift test                          # the logic tests — no phone needed
python3 Scripts/static_review.py    # structural checks — works anywhere
brew install xcodegen && xcodegen generate && open PromptCam.xcodeproj
```

Pick the **PromptCam** scheme first. Only switch to **PromptCam (Duo)** once
the baseline builds and the tests pass.

## Still yours to do

Apple Developer membership; set your team ID in Xcode; change the bundle
identifier from the placeholder; App Store Connect record; privacy
questionnaire (the answer is genuinely "no data collected" — no networking
code, no third-party dependencies); screenshots; read the Review Guidelines.

One request: **don't claim iPhone Duo behaviour in the App Store listing until
someone has actually run PromptCam on an iPhone Duo.** "Works with a second
display" is true today. "Designed for iPhone Duo" isn't yet.
