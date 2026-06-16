<!-- TUTORED LESSON — CONSTITUTION (binding)
     Every task carries exactly one owner tag: [tutor] or [you].
     Agent: execute [tutor] tasks in order; HARD-STOP at the first incomplete
     [you] task — summarize state, say exactly what the learner should do, END TURN.
     NEVER write, complete, or check off a [you] deliverable.
     When the learner reports a [you] task done, verify the observable outcome
     (run `odin test`, build, check files) before marking it and continuing.
     Full constitution: .claude/skills/tutor/SKILL.md -->

<!-- Build lesson, interface: LEARNER-DESIGNED (the learner's first). The Design group
     is live: learner sketches in design.md (2.1), tutor critiques + records the agreed
     interface (2.2). Stubs/tests (group 3) MUST NOT exist before 2.2 is filled. The
     tutor stubs only the `core` build-info seam for the red test; the learner builds out
     the rest of the skeleton (platform/render/game/app/build script). Engine capability
     `engine-skeleton` merges into openspec/specs/ at archive. -->

## 1. Orient

- [x] 1.1 [tutor] Verify/register cite-keys in BIBLIOGRAPHY.md; verify build mechanics against the compiler; write lesson.md
- [ ] 1.2 [you] Read lesson.md and the required reading (ODIN §Packages, `odin build -help`, GEA ch.1); note questions

## 2. Design

- [x] 2.1 [you] Sketch the skeleton interface in design.md (package layout, the downward DAG, the `core` build-info seam, each layer's boot surface, the app banner)
- [x] 2.2 [tutor] Critique the sketch (layering-law check especially); record the agreed interface in design.md

## 3. Spec (stubs + failing test)

- [x] 3.1 [tutor] Stub `engine/core/core.odin` — the agreed core build-info seam (empty-string placeholder, not `unimplemented()`, so the test fails cleanly instead of trapping the runner)
- [x] 3.2 [tutor] Write `engine/core/core_test.odin` (`core:testing`); ran `odin test engine/core` — confirmed RED (both tests fail on assertion)

## 4. Build

- [x] 4.1 [you] Build the skeleton: create `platform`/`render`/`game` packages + `app` entry + `build.ps1`; wire the downward imports; implement the core seam until `odin test engine/core` is green, the whole tree is `-vet -strict-style` clean, and the build graph is acyclic
- [x] 4.2 [you] Demo checkpoint: build & run `examples/testbed`; confirm the boot banner walks all four layers

## 5. Review

- [x] 5.1 [tutor] Verify green + demo; review the diff per references/review-rubric.md (layering law, acyclic graph, handle/boundary discipline); ask ≥2 comprehension probes
- [x] 5.2 [you] Answer the probes; address review findings

## 6. Finalize

- [x] 6.1 [tutor] Run the measurement task (clean vs incremental build time, `-o:none` vs `-o:speed` size, package count, `odin test` time); record Built + Measured in curriculum/JOURNAL.md
- [x] 6.2 [tutor] Walk the learner through what the numbers mean
- [x] 6.3 [you] Write Takeaways + Reflections in curriculum/JOURNAL.md (your own words)
- [x] 6.4 [tutor] Copy lesson.md → curriculum/modules/m01/m01-01-skeleton/LESSON.md
- [x] 6.5 [tutor] Update curriculum/curriculum.yaml (m01-01 → done; m02-01 → available; clear active_change)
- [ ] 6.6 [tutor] Commit the lesson; hand off to /opsx:archive
