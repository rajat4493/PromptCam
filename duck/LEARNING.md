# Learning

Full capture: [`../docs/THEDUCK_LEARNING.md`](../docs/THEDUCK_LEARNING.md).
This is the short list worth carrying into the next foldable project.

## The single most useful pattern

**Concentrate every unverified API in one directory, behind one compile flag,
off in the default configuration.**

Five files, one flag. It meant a wrong signature costs an adapter file instead
of a rewrite, and — critically — it meant the baseline build and the test run
could never be blocked by an API nobody had confirmed.

The review found the cost of getting the *default* wrong: with the flag absent
from both configurations, the committed app was an ordinary camera app. The fix
was a dedicated `Duo` configuration and scheme, not flipping the default. Both
halves matter: isolate the uncertainty, **and** give it a first-class way to be
built.

## Where a coding agent produces false confidence

Ranked by how convincing the wrong answer would have looked:

1. **Pasting a supplied snippet and calling the feature done.** The direction
   coordinator had five simultaneous unknowns, one of which (the handler's
   parameter type) could have compiled and silently never fired. Not
   implementing it, returning `false`, and documenting the five unknowns was
   the honest deliverable.
2. **Substituting a second window for the accessory.** Easy, demos beautifully,
   fabricates the one capability the product depends on.
3. **Saying the tests pass.** 130 cases exist; zero have run. A scoreboard at
   the top of the ledger and a checker that fails on the word `VERIFIED` in
   source make that hard to fudge.
4. **Treating documentation presence as verification.** Reading a real
   declaration beats recall and is still not a compiler. Separate labels for
   each, and a ten-second `swiftc -typecheck` probe as step 2 of the handover.
5. **Asserting absence as a finding.** My searches from a sandbox with no Apple
   toolchain did not find the Duo APIs, and I wrote that up as "these do not
   exist". That was wrong, and putting it in an executive summary would have
   told the next agent that real APIs were fictional. **Absence of evidence
   from a restricted environment is a fact about the environment, not about the
   SDK** — scope such findings to what the tooling could actually see.

## What the review taught that the design did not

The architecture was sound and the *lifecycle* was not. Three P0s all lived in
the seam between a synchronous state machine and an asynchronous pipeline:

- cleanup ran on a schedule that knew nothing about what was worth keeping;
- a callback could arrive after the state machine had already come to rest;
- a stop could arrive before the thing it was stopping had started.

**Lesson: a state machine proves the states are legal, not that the world
arrives in that order.** Next time, enumerate the out-of-order arrivals
explicitly — late completion, early stop, double completion — and write those
tests alongside the transition table, not after a reviewer finds them.

**Corollary: "the file is kept" is a claim about the file system, not about a
variable.** A preserved path pointing into a swept directory is not
preservation, and a path printed on screen is not recovery. Promises about
durability need a durable location and a user-reachable action.

## What to ask earlier

1. "Do you have the hardware, and do you have the SDK?" — minute one.
2. "Where did these API names come from: a compiler, Xcode's documentation, or
   an announcement?" — a neutral question with a decisive answer.
3. "Can this be tested on hardware you already own?" — the external-display
   insight would have reframed the whole schedule on day one.
4. "Which single claim, if false, kills the product?" — check that first.
5. "What is the cheapest test of the *user* assumption?" — here it is three
   interviews, and it is still unrun.

## Product insights for the next Duo app

- **A foldable's value is two audiences, not more pixels.** The productive
  question was never "what do I do with a bigger screen" but "what should the
  *other* person see?"
- **Ask what the second surface must NOT show.** That constraint shaped the
  architecture more than any feature did, and it became a property of a type.
- **Non-interactive is a feature.** The interviewee should not be able to
  change anything.
- **Design for the accessory's absence first.** The platform requires it, and
  it forces the app to be genuinely useful on hardware people already own.
- **The marquee foldable APIs were the least useful ones.** The value came from
  a second-surface content API plus size classes — a decade-old primitive.
