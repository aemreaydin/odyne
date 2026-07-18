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
     NO engine spec-delta in this change: the pool is built in isolation under katas/pool/
     and does NOT enter engine/ yet. Its core-memory spec-delta lands at m02-04
     ("Graduate: core memory package"), where arena + pool merge into engine/core — so
     openspec/specs/ stays honest. The Spec group below is stubs + failing tests only. -->

## 1. Orient

- [x] 1.1 [tutor] Verify/register cite-keys in BIBLIOGRAPHY.md (all already registered: GB-MEM pt.4 = Pool Allocators, GEA, ODIN-MEM); write lesson.md
- [x] 1.2 [you] Read lesson.md and the required reading (GB-MEM pt.4; the `Allocator_Proc`/`Allocator_Mode` entries); note questions

## 2. Design

- [x] 2.1 [you] Sketch the pool's public API in design.md §Learner sketch (struct, init over borrowed backing + block size, free-list threading, how you obtain an `Allocator`, `.Free`/`.Resize`/oversize semantics, alignment)
- [x] 2.2 [tutor] Critique the sketch; record the agreed interface in design.md §Agreed interface

## 3. Spec (stubs + failing tests — no engine spec-delta; see header)

- [x] 3.1 [tutor] Write `katas/pool/pool.odin` — the agreed signatures with STUB bodies (benign values, not `unimplemented()`, so tests run RED instead of trapping the runner)
- [x] 3.2 [tutor] Write `katas/pool/pool_test.odin` (`core:testing`; 13 tests: init/alloc-size/zeroing/non-zeroed/distinct/exhaustion→OOM/oversize→Invalid_Argument/free-reuse/free-all-rethread/alignment/query/context); `odin test katas/pool` → 13 RED, `-vet -strict-style` clean

## 4. Build

- [ ] 4.1 [you] Implement the pool until `odin test katas/pool` is green and the leak check is clean

## 5. Review

- [x] 5.1 [tutor] Verify green; review the diff per references/review-rubric.md; ask ≥2 comprehension probes (13 green; findings on free_all head-reset, init pad guard, double-free)
- [ ] 5.2 [you] Answer the probes; address review findings

## 6. Finalize

- [x] 6.1 [tutor] Run the measurement task (pool alloc/free churn vs heap new/free; ns per op + throughput); record Built + Measured in curriculum/JOURNAL.md
- [x] 6.2 [tutor] Walk the learner through what the numbers mean
- [x] 6.3 [you] Write Takeaways + Reflections in curriculum/JOURNAL.md (your own words)
- [x] 6.4 [tutor] Copy lesson.md → curriculum/modules/m02/m02-03-pool/LESSON.md
- [x] 6.5 [tutor] Update curriculum/curriculum.yaml (m02-03 → done; m02-04 core-memory → available; clear active_change)
- [x] 6.6 [tutor] Commit the lesson; hand off to /opsx:archive
