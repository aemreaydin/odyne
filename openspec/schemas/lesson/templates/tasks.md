<!-- TUTORED LESSON — CONSTITUTION (binding)
     Every task carries exactly one owner tag: [tutor] or [you].
     Agent: execute [tutor] tasks in order; HARD-STOP at the first incomplete
     [you] task — summarize state, say exactly what the learner should do, END TURN.
     NEVER write, complete, or check off a [you] deliverable.
     When the learner reports a [you] task done, verify the observable outcome
     (run `odin test`, check files) before marking it and continuing.
     Full constitution: .claude/skills/tutor/SKILL.md -->

## 1. Orient

- [ ] 1.1 [tutor] Verify/register cite-keys in BIBLIOGRAPHY.md; write lesson.md
- [ ] 1.2 [you] Read lesson.md and the required reading; note questions

## 2. Design

- [ ] 2.1 [you] Sketch the interface in design.md (skip only if interface: provided)
- [ ] 2.2 [tutor] Critique the sketch; record the agreed interface in design.md

## 3. Spec

- [ ] 3.1 [tutor] Write stubs at the agreed interface: signatures + doc comments, bodies are
      `unimplemented()` and nothing else. Comments state consequence, not procedure — a
      comment narrating the body is a rung-2/3 hint delivered unprompted. Every definition
      unless trivial; no file-wide comments. See `.claude/skills/tutor/references/stub-style.md`
- [ ] 3.2 [tutor] Write failing tests; run `odin test` to confirm red

## 4. Build

- [ ] 4.1 [you] Implement until tests are green and the leak check is clean

## 5. Review

- [ ] 5.1 [tutor] Verify green; review the diff per review-rubric.md; ask ≥2 comprehension probes
- [ ] 5.2 [you] Answer the probes; address review findings

## 6. Finalize

- [ ] 6.1 [tutor] Run the measurement task; record the numbers under "Performance notes → Measured" in lesson.md
- [ ] 6.2 [tutor] Walk the learner through what the numbers mean
- [ ] 6.3 [tutor] Copy lesson.md → curriculum/modules/<module>/<lesson>/LESSON.md
- [ ] 6.4 [tutor] Update curriculum/curriculum.yaml (status, unlocks, clear active pointer)
- [ ] 6.5 [tutor] Commit the lesson; hand off to /opsx:archive — which merges the spec
      deltas and, for any capability created by this lesson, writes its Purpose before
      archiving (no `TBD` placeholder survives the ritual)
