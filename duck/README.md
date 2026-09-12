# /duck — TheDuck milestone ledger

The authoritative delivery record for PromptCam. Where `/docs` holds the
long-form engineering and product documents, `/duck` holds the **milestone
ledger**: what was intended, what was assumed, what changed, what was proven,
and what was learned — in a form a reader can audit without reading the code.

## Records

| Record | Question it answers |
|---|---|
| [`MILESTONES.md`](MILESTONES.md) | What milestone are we on, and did it pass? |
| [`INTENT.md`](INTENT.md) | What was the human asking for, in their terms? |
| [`ASSUMPTIONS.md`](ASSUMPTIONS.md) | What is supplied, what is documented, what is a bet? |
| [`SCOPE_CHANGES.md`](SCOPE_CHANGES.md) | What changed after the brief, and who approved it? |
| [`VERIFICATION.md`](VERIFICATION.md) | What has actually been proven, at what tier? |
| [`HUMAN_SUMMARY.md`](HUMAN_SUMMARY.md) | What can the founder do right now? |
| [`HANDOVER.md`](HANDOVER.md) | What does the next engineer need? |
| [`LEARNING.md`](LEARNING.md) | What should the next project do differently? |

## Status vocabulary

Used identically across `/duck` and `/docs`. A label is only ever raised by an
actual execution.

| Label | Meaning |
|---|---|
| `VERIFIED_LINUX` | An executable check ran in the authoring environment and passed |
| `STATICALLY_REVIEWED` | Source read line by line; **never compiled** |
| `REQUIRES_MAC` | Needs Xcode 27.1 + the iOS 27.1 SDK |
| `REQUIRES_DUO_SIMULATOR` | Needs Device Hub + an iPhone Duo simulator |
| `REQUIRES_PHYSICAL_DUO` | Needs the physical device |
| `BLOCKED` | Cannot proceed at all from here |
| `FAILED` | Attempted and did not work |

**`STATICALLY_REVIEWED` is never edited into `VERIFIED`.** It is replaced by a
compiler or hardware result, or it stays as it is. Simulator evidence is never
recorded as physical-device evidence.
