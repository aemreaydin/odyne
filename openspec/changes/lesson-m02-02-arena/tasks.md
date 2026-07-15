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
     NO engine spec-delta in this change: the arena is built in isolation under
     katas/arena/ and does NOT enter engine/ yet. Its core-memory spec-delta lands at
     m02-04 ("Graduate: core memory package"), where arena + pool actually merge into
     engine/core — so the engine's living spec (openspec/specs/) stays honest. The Spec
     group below is stubs + failing tests only. -->

## 1. Orient

- [x] 1.1 [tutor] Verify/register cite-keys in BIBLIOGRAPHY.md (all already registered: GB-MEM, GEA, ODIN-MEM, ODIN; GB-MEM pt.2 arena URL verified); write lesson.md
- [ ] 1.2 [you] Read lesson.md and the required reading (GB-MEM pt.2; the `Allocator_Proc`/`Allocator_Mode`/`Allocator_Error` entries); note questions

## 2. Design

- [x] 2.1 [you] Sketch the arena's public API in design.md §Learner sketch (struct, init over borrowed backing, how you obtain an `Allocator`, reset shape, alignment approach, modes supported)
- [x] 2.2 [tutor] Critique the sketch; record the agreed interface in design.md §Agreed interface

## 3. Spec (stubs + failing tests — no engine spec-delta; see header)

- [x] 3.1 [tutor] Write `katas/arena/arena.odin` — the agreed signatures with STUB bodies (benign zero-returns, not `unimplemented()`, so tests run RED instead of trapping the runner)
- [x] 3.2 [tutor] Write `katas/arena/arena_test.odin` (`core:testing`; 14 tests: alloc/zeroing/alignment/OOM/free/free-all-reuse/resize/query/context); `odin test katas/arena` → 14 RED, `-vet -strict-style` clean

## 4. Build

- [ ] 4.1 [you] Implement the arena until `odin test katas/arena` is green and the leak check is clean

## 5. Review

- [x] 5.1 [tutor] Verify green; review the diff per references/review-rubric.md; ask ≥2 comprehension probes (added 4 resize regression tests; findings 1–3 confirmed failing)
- [x] 5.2 [you] Answer the probes; address review findings (all correctness findings fixed; 19 tests green; probes answered, #2/#3 corrected & confirmed)

## 6. Finalize

- [x] 6.1 [tutor] Run the measurement task (arena vs heap ns/alloc + speedup; free_all vs n individual frees); record Built + Measured in curriculum/JOURNAL.md
- [x] 6.2 [tutor] Walk the learner through what the numbers mean
- [x] 6.3 [you] Write Takeaways + Reflections in curriculum/JOURNAL.md (your own words)
- [x] 6.4 [tutor] Copy lesson.md → curriculum/modules/m02/m02-02-arena/LESSON.md
- [x] 6.5 [tutor] Update curriculum/curriculum.yaml (m02-02 → done; m02-03 pool → available; clear active_change)
- [x] 6.6 [tutor] Commit the lesson; hand off to /opsx:archive
