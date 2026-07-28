<!-- TUTORED LESSON — CONSTITUTION (binding)
     Every task carries exactly one owner tag: [tutor] or [you].
     Agent: execute [tutor] tasks in order; HARD-STOP at the first incomplete
     [you] task — summarize state, say exactly what the learner should do, END TURN.
     NEVER write, complete, or check off a [you] deliverable.
     When the learner reports a [you] task done, verify the observable outcome
     (run `odin test`, check files) before marking it and continuing.
     Full constitution: .claude/skills/tutor/SKILL.md -->

<!-- Kata lesson, interface: LEARNER-DESIGNED — task 2.1 (learner sketch) is kept; the tutor
     critiques and records the agreed interface (2.2) before any tests exist.
     NO engine spec-delta in this change: the frame clock is built in isolation under
     katas/timing/ and does NOT enter engine/ yet. Its spec-delta lands at m11-02 ("The main
     loop & fixed timestep"), which graduates the clock into the engine and settles whether it
     lives in core (core:time source) or platform (SDL source) — so openspec/specs/ stays
     honest. The Spec group below is stubs + failing tests only. -->

## 1. Orient

- [x] 1.1 [tutor] Verify/register cite-keys in BIBLIOGRAPHY.md (registered this lesson: `MS-QPC`, `ODIN-TIME`; widened: `SDL` timing pages, `GEA` ch.8 numbering; already registered: `HMH`); write lesson.md
- [x] 1.2 [you] Read lesson.md and the required reading (GEA §8.4–8.5; MS-QPC guidance + FAQs); note questions

## 2. Design

- [x] 2.1 [you] Sketch the timing API in design.md §Learner sketch (time source + layering argument, type vocabulary/units, frame-clock shape + first-frame dt, spike policy and whose job it is, pause/scale, history capacity + statistics semantics, wait primitive shape, injection mechanism)
- [x] 2.2 [tutor] Critique the sketch against the cited designs (`accurate_sleep`, `SDL_DelayPrecise`, GEA timelines, MS-QPC conversion rules); record the agreed interface in design.md §Agreed interface

## 3. Spec (stubs + failing tests — no engine spec-delta; see header)

- [x] 3.1 [tutor] Write `katas/timing/timing.odin` — the agreed signatures with STUB bodies (benign values, not `unimplemented()`, so tests run RED instead of trapping the runner)
- [x] 3.2 [tutor] Write `katas/timing/timing_test.odin` (`core:testing`, fabricated timestamps only — monotonic sourcing, first-frame dt, elapsed-by-subtraction exactness over a long fake session, spike policy, pause/scale if agreed, history before/after the window fills, min/max/avg, wait-primitive contract); `odin test katas/timing` → RED, no panics, `-vet -strict-style` clean

## 4. Build

- [x] 4.1 [you] Implement the timing kata until `odin test katas/timing` is green and the leak check is clean

## 5. Review

- [x] 5.1 [tutor] Verify green; review the diff per references/review-rubric.md; ask ≥2 comprehension probes
- [x] 5.2 [you] Answer the probes; address review findings

## 6. Finalize

- [x] 6.1 [tutor] Run the measurement task (`katas/timing_bench/`: (a) clock-read ns/call vs `time.tick_now`; (b) sleep overshoot 1/5/16.7 ms across `time.sleep` / `time.accurate_sleep` / your wait, mean+max+spin cost; (c) f32 vs f64 vs i64 drift over 100k frames; (d) the tick→ns overflow demonstration at 10 MHz and 1 GHz; (e) per-frame overhead as % of 16.67 ms); record Built + Measured in curriculum/JOURNAL.md
- [x] 6.2 [tutor] Walk the learner through what the numbers mean
- [x] 6.3 [you] Write Takeaways + Reflections in curriculum/JOURNAL.md (your own words)
- [x] 6.4 [tutor] Copy lesson.md → curriculum/modules/m11/m11-01-timing/LESSON.md
- [x] 6.5 [tutor] Update curriculum/curriculum.yaml (m11-01 → done; m11-02 → available; clear active_change)
- [x] 6.6 [tutor] Commit the lesson; hand off to /opsx:archive
