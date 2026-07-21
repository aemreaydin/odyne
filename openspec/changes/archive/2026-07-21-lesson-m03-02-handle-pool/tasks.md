<!-- TUTORED LESSON — CONSTITUTION (binding)
     Every task carries exactly one owner tag: [tutor] or [you].
     Agent: execute [tutor] tasks in order; HARD-STOP at the first incomplete
     [you] task — summarize state, say exactly what the learner should do, END TURN.
     NEVER write, complete, or check off a [you] deliverable.
     When the learner reports a [you] task done, verify the observable outcome
     (run `odin test`, check files) before marking it and continuing.
     Full constitution: .claude/skills/tutor/SKILL.md -->

<!-- Kata lesson, interface: LEARNER-DESIGNED — task 2.1 (learner sketch) is kept;
     the tutor critiques and records the agreed interface (2.2) before any tests exist.
     NO engine spec-delta in this change: the handle pool is built in isolation under
     katas/handle_pool/ and does NOT enter engine/ yet. Its core-containers spec-delta
     lands at m03-03 ("Graduate: core containers package"), where it merges into
     engine/core — so openspec/specs/ stays honest. The Spec group below is stubs +
     failing tests only. -->

## 1. Orient

- [x] 1.1 [tutor] Verify cite-keys in BIBLIOGRAPHY.md (all registered: FLOOOH, BITSQUID, ZYL-HANDLES, GEA §16.5, ECS-FAQ, ODIN); write lesson.md
- [x] 1.2 [you] Read lesson.md and the required reading (ZYL-HANDLES follow-up article; BITSQUID re-read); note questions

## 2. Design

- [x] 2.1 [you] Sketch the handle pool's public API in design.md §Learner sketch (layout commitment, Handle representation + bit budget + zero-invalid mechanism, ownership story, generation/wrap policy, API surface + edge semantics)
- [x] 2.2 [tutor] Critique the sketch against the cited designs; record the agreed interface in design.md §Agreed interface

## 3. Spec (stubs + failing tests — no engine spec-delta; see header)

- [x] 3.1 [tutor] Write `katas/handle_pool/handle_pool.odin` — the agreed signatures with STUB bodies (benign values, not `unimplemented()`, so tests run RED instead of trapping the runner)
- [x] 3.2 [tutor] Write `katas/handle_pool/handle_pool_test.odin` (`core:testing`: 12 tests — add/get roundtrip, get vs get_ptr semantics, has lifecycle, zero-handle rejection, garbage-handle safety, stale + double remove, slot-reuse generation bump, exhaustion + recovery, swap-with-last patch, FIFO reuse order, clear, retire-at-max); `odin test katas/handle_pool` → 12 RED, no panics, `-vet -strict-style` clean

## 4. Build

- [x] 4.1 [you] Implement the handle pool until `odin test katas/handle_pool` is green and the leak check is clean

## 5. Review

- [x] 5.1 [tutor] Verify green; review the diff per references/review-rubric.md; ask ≥2 comprehension probes
- [x] 5.2 [you] Answer the probes; address review findings

## 6. Finalize

- [x] 6.1 [tutor] Run the measurement task (`katas/handle_pool_bench/`: add/remove churn vs m02-03 pool + heap; resolve in-order/shuffled/stale-mix vs m03-01 baselines; iteration at high/low occupancy); record Built + Measured in curriculum/JOURNAL.md
- [x] 6.2 [tutor] Walk the learner through what the numbers mean
- [x] 6.3 [you] Write Takeaways + Reflections in curriculum/JOURNAL.md (your own words)
- [x] 6.4 [tutor] Copy lesson.md → curriculum/modules/m03/m03-02-handle-pool/LESSON.md
- [x] 6.5 [tutor] Update curriculum/curriculum.yaml (m03-02 → done; m03-03 → available; clear active_change)
- [x] 6.6 [tutor] Commit the lesson; hand off to /opsx:archive
