<!-- TUTORED LESSON — CONSTITUTION (binding)
     Every task carries exactly one owner tag: [tutor] or [you].
     Agent: execute [tutor] tasks in order; HARD-STOP at the first incomplete
     [you] task — summarize state, say exactly what the learner should do, END TURN.
     NEVER write, complete, or check off a [you] deliverable.
     When the learner reports a [you] task done, verify the observable outcome
     (run `odin test`, build the app, check files) before marking it and continuing.
     Full constitution: .claude/skills/tutor/SKILL.md -->

<!-- BUILD (graduate) lesson, interface: LEARNER-DESIGNED (packaging/naming of the two
     allocators inside engine/core). Unlike the m02-02/03 katas, this change CARRIES an
     engine spec delta: specs/core-memory/spec.md merges into openspec/specs/ at archive —
     the first time the memory capability enters the engine's living spec. Includes a demo
     checkpoint (the engine allocates through a core allocator) per build-lesson rules. -->

## 1. Orient

- [x] 1.1 [tutor] Verify/register cite-keys (all registered: GEA, ODIN, ODIN-MEM, GB-MEM); write lesson.md
- [ ] 1.2 [you] Read lesson.md and re-skim m01-01's layering section + `core:mem`'s packaging; note questions

## 2. Design

- [x] 2.1 [you] Sketch the packaging + naming in design.md §Learner sketch (flat-in-core / mem sub-package / separate sub-packages; call-site trade-offs; scaling as core grows)
- [x] 2.2 [tutor] Critique the sketch; record the agreed layout in design.md §Agreed interface (chosen: `engine:core/mem`, prefixed `arena_*`/`pool_*`, stdlib aliased `cmem`)

## 3. Spec

- [x] 3.1 [tutor] Write the `core-memory` spec delta (specs/core-memory/spec.md — arena, pool, allocator conformance, layering)
- [x] 3.2 [tutor] Write failing conformance tests (engine/core/memory/memory_test.odin) + a red stub (memory.odin) against the agreed `package memory` surface; `odin test engine/core/memory -collection:engine=engine` → 9 RED, `-vet -strict-style` clean

## 4. Build

- [x] 4.1 [you] Move + adapt arena and pool into engine/core/memory (package memory, prefixed names); `odin test engine/core/memory` green, leak-clean, -vet -strict-style clean
- [x] 4.2 [you] Wire the demo checkpoint — testbed allocates through core arena + pool; builds and runs correctly (0xBB via arena; 0xAA/0xCC via pool)

## 5. Review

- [x] 5.1 [tutor] Verify green + demo + build; review per references/review-rubric.md (layering law especially: core imports only stdlib); ask ≥2 comprehension probes (folded logging into spec/tests; 10 green; no blocking findings)
- [x] 5.2 [you] Answer the probes; address review findings (3 probes answered well; no findings required fixing)

## 6. Finalize

- [x] 6.1 [tutor] Run the measurement task (engine test/build time + size vs m01-01 baseline; no-regression spot-check of a core alloc); record Built + Measured in curriculum/JOURNAL.md
- [x] 6.2 [tutor] Walk the learner through what the numbers mean
- [x] 6.3 [you] Write Takeaways + Reflections in curriculum/JOURNAL.md (your own words)
- [x] 6.4 [tutor] Copy lesson.md → curriculum/modules/m02/m02-04-core-memory/LESSON.md
- [x] 6.5 [tutor] Update curriculum/curriculum.yaml (m02-04 → done; m03-01 → available; clear active_change)
- [x] 6.6 [tutor] Commit the lesson; hand off to /opsx:archive (syncs the core-memory spec into openspec/specs/)
