<!-- TUTORED LESSON — CONSTITUTION (binding)
     Every task carries exactly one owner tag: [tutor] or [you].
     Agent: execute [tutor] tasks in order; HARD-STOP at the first incomplete
     [you] task — summarize state, say exactly what the learner should do, END TURN.
     NEVER write, complete, or check off a [you] deliverable.
     When the learner reports a [you] task done, verify the observable outcome
     (run `odin test`, check files) before marking it and continuing.
     Full constitution: .claude/skills/tutor/SKILL.md -->

<!-- Concept lesson: Spec and Build groups dropped per references/lesson-types.md;
     Review uses recall questions instead of a diff review. -->

## 1. Orient

- [x] 1.1 [tutor] Verify/register cite-keys in BIBLIOGRAPHY.md; write lesson.md
- [x] 1.2 [you] Read lesson.md and the required reading ([ODIN] overview, end to end); note questions

## 2. Review

- [x] 2.1 [you] Answer the 8 recall questions from lesson.md §Exercise, in your own words
- [x] 2.2 [tutor] Review the answers against the sources; correct misconceptions; ask ≥2 follow-up probes
- [x] 2.3 [you] Answer the probes

## 3. Finalize

- [x] 3.1 [you] Run the measurement task (toolchain install, compile timings, binary sizes); record the numbers
- [x] 3.2 [you] Write the journal entry in curriculum/JOURNAL.md (Built/Measured/Takeaways/Reflections)
- [x] 3.3 [tutor] Copy lesson.md → curriculum/modules/m00/m00-01-odin-tour/LESSON.md
- [x] 3.4 [tutor] Update curriculum/curriculum.yaml (m00-01 → done; m00-02 → available; clear active_change)
- [x] 3.5 [tutor] Commit the lesson; hand off to /opsx:archive
