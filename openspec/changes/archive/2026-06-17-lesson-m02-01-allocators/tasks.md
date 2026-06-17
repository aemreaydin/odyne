<!-- TUTORED LESSON — CONSTITUTION (binding)
     Every task carries exactly one owner tag: [tutor] or [you].
     Agent: execute [tutor] tasks in order; HARD-STOP at the first incomplete
     [you] task — summarize state, say exactly what the learner should do, END TURN.
     NEVER write, complete, or check off a [you] deliverable.
     When the learner reports a [you] task done, verify the observable outcome
     (run `odin test`, check files) before marking it and continuing.
     Full constitution: .claude/skills/tutor/SKILL.md -->

<!-- Concept lesson: Design/Spec/Build groups dropped per references/lesson-types.md;
     Review uses recall questions instead of a diff review. design.md = "Not applicable". -->

## 1. Orient

- [x] 1.1 [tutor] Register cite-key ODIN-MEM in BIBLIOGRAPHY.md; write lesson.md
- [ ] 1.2 [you] Read lesson.md and the required reading ([ODIN] implicit context system, [ODIN-MEM] runtime allocator interface); note questions

## 2. Review

- [x] 2.1 [you] Answer the 8 recall questions from lesson.md §Exercise, in your own words
- [x] 2.2 [tutor] Review the answers against the sources; correct misconceptions; ask ≥2 follow-up probes
- [x] 2.3 [you] Answer the probes

## 3. Finalize

- [x] 3.1 [tutor] Run the measurement task (heap vs temp_allocator alloc cost + indirect-call overhead); record Built + Measured in curriculum/JOURNAL.md
- [x] 3.2 [tutor] Walk the learner through what the numbers mean
- [x] 3.3 [you] Write Takeaways + Reflections in curriculum/JOURNAL.md (your own words)
- [x] 3.4 [tutor] Copy lesson.md → curriculum/modules/m02/m02-01-allocators/LESSON.md
- [x] 3.5 [tutor] Update curriculum/curriculum.yaml (m02-01 → done; m02-02 → available; clear active_change)
- [x] 3.6 [tutor] Commit the lesson; hand off to /opsx:archive
