<!-- TUTORED LESSON — CONSTITUTION (binding)
     Every task carries exactly one owner tag: [tutor] or [you].
     Agent: execute [tutor] tasks in order; HARD-STOP at the first incomplete
     [you] task — summarize state, say exactly what the learner should do, END TURN.
     NEVER write, complete, or check off a [you] deliverable.
     When the learner reports a [you] task done, verify the observable outcome
     (run `odin test`, check files) before marking it and continuing.
     Full constitution: .claude/skills/tutor/SKILL.md -->

<!-- Kata lesson with interface: PROVIDED — the learner-sketch task (2.1 in the
     template) is dropped; the tutor supplies the interface (rationale in design.md).
     No engine spec-delta: this warm-up kata builds NO engine capability and does
     not graduate into engine/, so nothing merges into openspec/specs/. The Spec
     group below is stubs + failing tests only. -->

## 1. Orient

- [x] 1.1 [tutor] Verify/register cite-keys in BIBLIOGRAPHY.md; write lesson.md
- [x] 1.2 [you] Read lesson.md and design.md, plus the required reading; note questions
      (learner elected to proceed to stubs)

## 2. Design

- [x] 2.1 [tutor] Confirm the provided interface in design.md §Agreed interface (no learner sketch — interface: provided)

## 3. Spec (stubs + failing tests)

- [x] 3.1 [tutor] Create `katas/odin_warmup/warmup.odin` — the four signatures with `unimplemented()` bodies
- [x] 3.2 [tutor] Write `katas/odin_warmup/warmup_test.odin` (`core:testing`); run `odin test katas/odin_warmup` to confirm RED

## 4. Build

- [x] 4.1 [you] Implement the four bodies until `odin test katas/odin_warmup` is green and the leak check is clean

## 5. Review

- [x] 5.1 [tutor] Verify green; review the diff per references/review-rubric.md; ask ≥2 comprehension probes
- [x] 5.2 [you] Answer the probes; address review findings

## 6. Finalize

- [x] 6.1 [tutor] Run the measurement task (test time + leak summary; `find` micro-bench `-o:none` vs `-o:speed`); record Built + Measured in JOURNAL.md
- [x] 6.2 [tutor] Walk the learner through what the numbers mean
- [x] 6.3 [you] Write Takeaways + Reflections in curriculum/JOURNAL.md (your own words)
- [x] 6.4 [tutor] Copy lesson.md → curriculum/modules/m00/m00-02-odin-kata/LESSON.md
- [x] 6.5 [tutor] Update curriculum/curriculum.yaml (m00-02 → done; m01-01 → available; clear active_change)
- [x] 6.6 [tutor] Commit the lesson; hand off to /opsx:archive
