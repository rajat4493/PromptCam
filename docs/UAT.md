# PromptCam — Manual User Acceptance Testing

**Who this is for:** you, the founder, testing PromptCam yourself. No
engineering knowledge assumed. If a step doesn't make sense, that's a bug in
this document — note it.

**Before you start, one thing to know:** none of this code has ever been
compiled. It was written in an environment with no Mac and no Apple tools.
`docs/MAC_VALIDATION.md` steps 1–7 must be completed first, on a Mac, before
any case below can be attempted. Until then every case is **BLOCKED**.

## How to record a result

For each case, fill in **Result** (`PASS` / `FAIL` / `BLOCKED`), the date, and
attach the evidence asked for. Put screenshots in `docs/evidence/` named by
case, e.g. `docs/evidence/uat-05-saved.png`.

When something fails, follow the **Recovery** line, then record what you did.
A `FAIL` with a clear note is more useful than a retried `PASS`.

## What you cannot test without hardware

| Case | Needs |
|---|---|
| 6 | Device Hub + an iPhone Duo simulator (`REQUIRES_DUO_SIMULATOR`) |
| 12 | Device Hub + an iPhone Duo simulator, then a physical Duo for the real thing |
| 7, 13 | A second display: an iPhone Duo, or an external display / AirPlay target |
| 16 | A physical iPhone Duo (`REQUIRES_PHYSICAL_DUO`) |
| 5, 8, 9, 10, 14, 15, 17 | A physical iPhone — **the Simulator has no camera**, so real recording cannot be tested there at all |

Cases 1–4 and 11 can be done in an ordinary iPhone simulator.

---

## Case 1 — First launch and permissions accepted

**Preconditions:** PromptCam newly installed. It has never been opened. Use a
physical iPhone if you have one.

**Steps**
1. Open PromptCam.
2. Note what appears on the **Decks** tab.
3. Tap the deck named **Customer testimonial**.
4. Read the six questions, then tap **Cancel**.
5. Swipe right on **Customer testimonial** and tap **Record**.
6. On the **Get ready** screen, tap **Allow camera**. Tap **Allow** in the
   system prompt.
7. Tap **Allow microphone**. Tap **Allow**.
8. Tap **Start interview**.

**Expected result**
- Step 2: one deck, **Customer testimonial**, marked "Sample", "6 questions".
- Step 6–7: each system prompt is preceded by PromptCam's own explanation of
  why it needs access. The prompt text mentions that video stays on the device.
- Step 8: the camera view opens. You see the live camera, a status pill reading
  **Ready**, an audio meter, and the first question in a panel.

**Evidence to capture:** screenshot of the deck list; screenshot of the
**Get ready** screen; screenshot of the camera view.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If no sample deck appears, storage failed to
initialise — check for a yellow banner saying storage is unavailable. If the
camera view is black with "No camera available", you are on the Simulator;
repeat on a physical iPhone.

---

## Case 2 — Camera permission denied

**Preconditions:** Settings ▸ PromptCam ▸ Camera turned **off**. Microphone
**on**.

**Steps**
1. Open PromptCam, choose a deck, swipe right, tap **Record**.
2. Read the **Permissions needed** section.
3. Tap **Open Settings**.
4. Turn Camera on, return to PromptCam.
5. Confirm the **Start interview** button becomes available.

**Expected result**
- Step 2: a **Camera** row explaining that access was turned down, and telling
  you to open Settings ▸ PromptCam and switch Camera on.
- **Start interview** is greyed out, with a footer reading "Grant camera and
  microphone access to start."
- Step 3 opens iOS Settings on PromptCam's own page.
- Step 5: the button becomes tappable.
- **At no point does the app crash, show a black screen, or let you start a
  recording that cannot work.**

**Evidence to capture:** screenshot of the Permissions needed section.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If the app crashes, the privacy usage description is
missing from the build — check `NSCameraUsageDescription` in `project.yml`. If
the button is tappable while permission is denied, that is a real bug: report
it with the screenshot.

---

## Case 3 — Microphone permission denied

**Preconditions:** Camera **on**, Microphone **off**.

**Steps**
1. Choose a deck, tap **Record**.
2. Read the **Permissions needed** section.
3. Confirm only the microphone is listed.
4. Tap **Open Settings**, enable Microphone, return.

**Expected result**
- Only a **Microphone** row appears — not camera.
- The wording is about audio, not video ("what the person you are interviewing
  says").
- **Start interview** stays disabled until microphone is granted.

**Evidence to capture:** screenshot showing the microphone row alone.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If both are listed when only one is denied, the
permission snapshot is wrong. If the microphone row shows camera wording, the
copy is mismatched.

**Bonus check (optional):** if you have a device with Screen Time restrictions
on camera access, the row should say access is blocked by a restriction and
**not** offer an Open Settings button, because you cannot fix it there.

---

## Case 4 — Create and edit an interview deck

**Preconditions:** App open, permissions irrelevant. Simulator is fine.

**Steps**
1. On **Decks**, tap **+**.
2. Name it `Street interviews`.
3. Add: `What's your name?`
4. Add: `What brought you here today?`
5. Add: `What would you change about this city?`
6. Tap **Edit**, drag the third question to the top.
7. Swipe left on `What's your name?` and delete it.
8. Tap the remaining first question and change a word.
9. Tap **Done**.
10. Force-quit PromptCam (swipe up from the app switcher).
11. Reopen it and open `Street interviews`.

**Expected result**
- Step 6: the order becomes `What would you change…`, `What's your name?`,
  `What brought you here…`.
- Step 7: two questions remain, in the order from step 6 minus the deleted one.
- Step 11: **the name, the two questions, the edit and the order are all exactly
  as you left them.**
- While the deck has no questions, a footer says to add at least one before
  recording.

**Evidence to capture:** screenshot after step 9 and after step 11, side by side.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If the order is wrong after reopening, question
ordering is not persisting. If everything is gone, check for the yellow
"storage is unavailable" banner — that means it fell back to memory-only.

---

## Case 5 — Record a complete interview on an ordinary iPhone

**Preconditions:** **Physical iPhone.** Both permissions granted. A deck with
at least three questions. Someone (or something) to point the camera at.

**Steps**
1. Choose the deck, tap **Record**, tap **Start interview**.
2. Tap the big red record button.
3. Watch the countdown: 3, 2, 1.
4. Let it record for about 20 seconds. Talk, so the audio meter moves.
5. Tap **›** to move to question 2.
6. Record about 10 seconds more.
7. Tap the stop button (the white square).
8. Tap **✕** to close.
9. Go to the **Interviews** tab and open the top entry.
10. Play it.

**Expected result**
- Step 3: a countdown appears; the status pill reads "Starting in 3", etc.
- Step 4: status pill reads **Recording** with a pulsing red dot. The timer
  counts up. The audio meter moves green when you speak.
- Step 5: the question panel updates. The recording does not stop.
- Step 7: the pill briefly reads **Saving**, then **Saved**.
- Step 9: the entry is labelled **Saved**, with the correct duration.
- Step 10: **the video plays, with picture and sound, for roughly the length you
  recorded.**
- Since this iPhone has no second display, **no subject-screen toggle and no
  empty secondary panel appears anywhere.**

**Evidence to capture:** screenshot mid-recording; screenshot of the library
entry; a short screen recording of playback.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If it says Saved but will not play, that is the most
serious possible bug — capture the library screenshot and the exact duration
shown, and report it immediately. If it never reaches Saved, note the last
status shown and whether any alert appeared.

---

## Case 6 — Record using the iPhone Duo simulator

**Preconditions:** Mac, Xcode 27.1, `PROMPTCAM_DUO` enabled
(`MAC_VALIDATION.md` step 8), an iPhone Duo simulator created via Device Hub
(step 10).

**This case is `REQUIRES_DUO_SIMULATOR` and may be impossible.** If
`xcrun simctl list devicetypes | grep -i duo` returns nothing, mark it
`BLOCKED` and move on.

**Steps**
1. Run PromptCam on the Duo simulator with the inner display open.
2. Choose a deck, tap **Record**, then **Start interview**.
3. Look for a **Subject screen** toggle in the question panel.
4. Turn it on.
5. Tap record and let the countdown run.

**Expected result**
- Step 3: the toggle appears **only** once the camera is running. It must not
  be visible on the **Get ready** screen.
- Step 4: the outer display shows the current question.
- Step 5: the outer display shows the countdown, then the recording status.
- The simulator has no camera, so the viewfinder reads "No camera available".
  That is expected and correct here.

**Evidence to capture:** screenshots of both displays.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If the toggle never appears, the accessory API is not
resolving or availability is not firing — see `MAC_VALIDATION.md` step 13, and
record the finding in `APPLE_API_CORRECTIONS.md`.

---

## Case 7 — Verify the subject-facing question display

**Preconditions:** A second display. Either an iPhone Duo, or — because the
underlying API is documented for external displays and AirPlay — an ordinary
iPhone connected to a TV or an Apple TV.

**Steps**
1. Start an interview with the subject screen enabled.
2. Stand **1 metre** from the subject display. Read the question aloud.
3. Stand **2 metres** away. Read it again.
4. Look carefully at the subject display and list everything on it.
5. Compare that list against what the director screen shows.

**Expected result**
- Steps 2–3: the question is comfortably readable at both distances, white on
  near-black.
- Step 4, the subject display shows **only**: the question, "Question N of M",
  and a recording indicator when recording.
- Step 5, the subject display must **not** show: the next question, the deck
  name, the timer, the marker count, the audio meter, or any button.

**Evidence to capture:** a photograph of the subject display taken from 2
metres away, plus your written list from step 4.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If the text is too small at 2 m, that is criterion
S14 failing — record the distance at which it *does* become readable. If any
director-only information appears on the subject display, that is a privacy
defect: report it with a photograph.

---

## Case 8 — Change questions while recording

**Preconditions:** Physical iPhone. A deck with at least four questions.

**Steps**
1. Start recording.
2. Every 10 seconds, tap **›**, until you reach the last question.
3. Tap **›** once more on the last question.
4. Tap **‹** twice to go back.
5. Stop, then open the interview in the library.
6. Read the **Timeline** section.

**Expected result**
- Step 2: each tap changes the question. Recording never stops. The timer keeps
  running.
- Step 3: nothing happens — **›** is greyed out on the last question.
- Step 4: it goes back, and recording still continues.
- Step 6: the timeline lists each question change with a timecode roughly
  matching when you tapped, including the two backwards moves.

**Evidence to capture:** screenshot of the timeline.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If recording stops when you change question, that is
a serious bug. If timecodes are all `00:00`, the timeline is not being stamped.

---

## Case 9 — Add several timestamp markers

**Preconditions:** Physical iPhone.

**Steps**
1. Start recording. Note the time on a watch or a second phone's stopwatch.
2. At roughly 5 s, tap the bookmark button.
3. At roughly 15 s, tap it again.
4. At roughly 30 s, tap it again.
5. Before recording, try tapping the bookmark — note that it is greyed out.
6. Stop, open the interview, read the timeline.

**Expected result**
- Steps 2–4: the number beside the bookmark increments 1, 2, 3.
- Step 5: the bookmark is disabled when not recording.
- Step 6: three markers, named "Marker 1/2/3", at timecodes within about a
  second of 5, 15 and 30.
- Tapping a timeline row jumps the video to that moment.

**Evidence to capture:** screenshot of the timeline with all three markers, and
your stopwatch times for comparison.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If offsets are consistently a second or two late,
note the size of the error — the app rebases timing onto the first recorded
frame, so a consistent offset points at that logic.

---

## Case 10 — Interrupt a recording

**Preconditions:** Physical iPhone with a SIM, and a second phone to call from.

**Steps**
1. Start recording. Let it run 15 seconds.
2. Call the iPhone from the second phone.
3. Answer, or let it ring.
4. Return to PromptCam.
5. Read any message shown.
6. Go to the **Interviews** tab.

**Expected result**
- Step 4–5: an alert saying recording was interrupted, naming the reason, and
  saying any video captured so far has been kept.
- Step 6: an entry marked **Interrupted**, not Saved.
- Opening it shows the interruption reason and, if a partial file survived, a
  **Kept file** path.
- **It must not be offered for playback as a normal interview, and it must not
  be labelled Saved.**
- Repeat with backgrounding instead of a call (swipe to the home screen
  mid-recording). Same expectations.

**Evidence to capture:** screenshot of the alert; screenshot of the library
entry.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If it shows **Saved** after an interruption, that is
a false-success bug and the most important thing in this document to report. If
nothing appears in the library at all, the interview vanished silently — also
report immediately.

---

## Case 11 — Rotate and resize the app

**Preconditions:** Simulator or device. An iPad also works and is a good proxy
for the open inner display.

**Steps**
1. Start an interview (Simulator is fine).
2. Rotate to landscape. Check every control is reachable.
3. Rotate back to portrait.
4. On iPad, put PromptCam in Split View and drag the divider narrow, then wide.
5. Go to Settings ▸ Accessibility ▸ Display & Text Size ▸ Larger Text and set
   the largest size. Return to PromptCam.
6. Turn on Settings ▸ Accessibility ▸ Motion ▸ Reduce Motion. Start recording.
7. Turn on VoiceOver and swipe through the camera screen.

**Expected result**
- Steps 2–4: nothing is clipped or off-screen. The record button is always
  fully visible and tappable. On a wide layout the camera and the console sit
  side by side; when narrow they stack.
- Step 5: text grows. Buttons remain tappable and labels are not cut off.
- Step 6: the recording dot stops pulsing but stays visibly red.
- Step 7: every control is announced — "Start recording", "Add marker",
  "Previous question", "Next question", "Close interview", "Microphone level".

**Evidence to capture:** screenshots in portrait, landscape, narrow Split View,
and at the largest text size.

**Result:** ______  **Date:** ______

**Recovery if it fails:** Note which control is unreachable and in which
configuration. If VoiceOver reads a button as just "Button", it is missing a
label.

---

## Case 12 — Open, close and partially fold the simulated Duo

**Preconditions:** iPhone Duo simulator (`REQUIRES_DUO_SIMULATOR`). Some of
this is only truly testable on a physical Duo.

**Steps**
1. Start an interview with the device open.
2. Change the pose to partially folded.
3. Look at where the record button sits relative to the hinge.
4. Change to fully open. Then closed. Then open again.
5. Do all of this while recording.

**Expected result**
- Step 3: **the record button does not sit on or across the hinge.** Neither do
  the question-navigation buttons.
- Step 4: the layout adapts each time. Nothing is clipped.
- Step 5: **recording continues throughout.** The timer keeps running.
- If hinge reporting is enabled, a partially-folded device shows a warning
  before recording — but not during.

**Evidence to capture:** screenshots at each pose, clearly showing the record
button's position relative to the hinge.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If a control lands on the hinge, reserved-region
handling needs fixing — see `MAC_VALIDATION.md` step 11. If recording stops
when the device folds, that is the highest-risk unknown in the whole project
(assumption A4); report it immediately.

---

## Case 13 — Remove secondary-display availability during a session

**Preconditions:** A working subject display (Duo, external display, or
AirPlay).

**Steps**
1. Start recording with the subject screen on and showing a question.
2. While recording, remove the second display: disconnect it, stop AirPlay, or
   turn the **Subject screen** toggle off.
3. Watch the director screen closely.
4. Add a marker. Move to the next question.
5. Stop recording and open the interview.

**Expected result**
- Step 3: **recording continues. The timer does not reset or stop.** No alert
  appears — losing the subject screen is not an error.
- The subject-screen toggle disappears cleanly. **No empty panel, no error
  placeholder, no broken layout.**
- Step 4: marker and question navigation still work.
- Step 5: the interview is **Saved**, and the timeline includes the marker and
  question change made *after* the display was removed.

**Evidence to capture:** screen recording of the director screen across step 2.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If recording stops, that contradicts the intended
design and the engine test `accessoryDisappearsWhileRecording`; report it. If a
blank panel is left behind, the availability state is not propagating.

---

## Case 14 — Save and review a recording

**Preconditions:** Physical iPhone, at least one completed interview.

**Steps**
1. Go to **Interviews**.
2. Check the top entry's label, date, duration and marker count.
3. Open it. Play the video.
4. Scrub to the middle. Confirm picture and sound.
5. Tap a timeline row.
6. Force-quit and reopen the app. Go back to **Interviews**.

**Expected result**
- Step 2: labelled **Saved**, with a plausible duration and the right marker
  count.
- Steps 3–4: it plays with picture and sound.
- Step 5: the video jumps to that timecode.
- Step 6: the entry is still there with everything intact.

**Evidence to capture:** screenshot of the detail screen showing status,
duration and timeline.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If the entry survives but playback says the file
could not be found, the video and the database have diverged — note the exact
message.

---

## Case 15 — Export the recording and marker list

**Preconditions:** Physical iPhone, a completed interview with at least two
markers and one question change.

**Steps**
1. Open the interview. Scroll to **Export**.
2. Tap **Share video**. Save to Files or send to yourself.
3. Tap **Markers — CSV (for editing tools)**. Save it.
4. Tap **Markers — Plain text (to read)**. Save it.
5. Open the CSV on a computer, in a spreadsheet.
6. Open the text file and read it.

**Expected result**
- Step 2: the standard share sheet appears; the video saves and plays elsewhere.
- Step 5: four columns — `timecode`, `seconds`, `type`, `label`. One row per
  marker and per question change, in time order. A question containing a comma
  stays in a single cell.
- Step 6: a readable list with the interview name, date, duration, status, and
  rows labelled `MARKER` / `QUESTION`.

**Evidence to capture:** the exported CSV and text files; a screenshot of the
CSV opened in a spreadsheet.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If an export row shows a warning triangle instead of
a share option, the file could not be written — note the alert text. If the CSV
columns are misaligned, a label is breaking the quoting.

---

## Case 16 — Simulate a save or export failure

**Preconditions:** Physical iPhone. This one needs a little setup — ask whoever
did the Mac validation to help, or use the storage-filling method below.

**Steps**
1. Fill the device's storage almost completely (large video downloads work).
2. Start an interview and record for about 30 seconds.
3. Stop.
4. Read what the app tells you.
5. Go to **Interviews** and open the entry.
6. Free up space. Try the export again.

**Expected result**
- Step 4: an alert explaining that the interview was recorded but could not be
  filed, **and that the video file has been kept**.
- Step 5: the entry is labelled **Not saved** — never **Saved**.
- The detail screen shows the failure reason and a **Kept file** path.
- **The interview is not offered for playback as if it were fine, and it is not
  deleted.**
- Step 6: export may now work; the recording entry is unchanged either way.

**Evidence to capture:** screenshot of the alert; screenshot of the detail
screen showing "Not saved" and the kept file path.

**Result:** ______  **Date:** ______

**Recovery if it fails:** If it reports **Saved** when it was not, stop and
report — that is the failure this whole design exists to prevent. If the file
was deleted, that is equally serious.

---

## Case 17 — Confirm no recording is reported as saved when it is not

**Preconditions:** Cases 10 and 16 completed. Physical iPhone.

**This is the most important case in this document.** Everything else is
features; this is trust.

**Steps**
1. Go to **Interviews** and list every entry with its label.
2. For each labelled **Saved**, open it and play it.
3. For each labelled **Not saved**, **Interrupted** or **Failed**, open it and
   confirm it is **not** offered as a normal playable interview.
4. Count: does every **Saved** entry actually play?

**Expected result**
- **Every single entry labelled Saved plays back successfully.** No exceptions.
- Every entry not labelled Saved says why, and offers a kept-file path where
  one exists.
- No entry is missing. An interview that failed still appears in the list —
  failures are visible, not hidden.

**Evidence to capture:** a photograph or screenshot of the full library list
with labels, plus a note of which ones you played and whether each worked.

**Result:** ______  **Date:** ______

**Recovery if it fails:** A **Saved** entry that does not play is a
release-blocking defect. Record the entry's date, duration and marker count,
and do not ship until it is fixed and this case passes.

---

## Summary sheet

| # | Case | Needs | Result | Date |
|---|---|---|---|---|
| 1 | First launch and permissions accepted | physical iPhone | | |
| 2 | Camera permission denied | physical iPhone | | |
| 3 | Microphone permission denied | physical iPhone | | |
| 4 | Create and edit a deck | simulator OK | | |
| 5 | Record a complete interview | physical iPhone | | |
| 6 | Record on the Duo simulator | Duo simulator | | |
| 7 | Subject-facing question display | second display | | |
| 8 | Change questions while recording | physical iPhone | | |
| 9 | Add several markers | physical iPhone | | |
| 10 | Interrupt a recording | physical iPhone + call | | |
| 11 | Rotate, resize, accessibility | simulator OK | | |
| 12 | Open, close, partially fold | Duo simulator / physical Duo | | |
| 13 | Remove secondary display mid-session | second display | | |
| 14 | Save and review | physical iPhone | | |
| 15 | Export video and markers | physical iPhone | | |
| 16 | Simulate a save/export failure | physical iPhone | | |
| 17 | **No false "saved"** | physical iPhone | | |
