# Lesson types

Five types. The `tasks.md` template scales to fit — keep the canonical group order
(Orient, Design, Spec, Build, Review, Finalize), drop groups that don't apply,
**never drop Finalize**.

## concept
Reading/understanding lesson, no code exercise.
- Groups: Orient, Review (recall questions instead of diff review), Finalize.
- `design.md` Agreed interface: "Not applicable".
- Definition of done: recall questions answered well; LESSON.md persisted.

## kata
Isolated implementation exercise in `katas/<topic>/`, unit-testable.
- All groups. Tutor writes stubs + failing tests; learner implements to green.
- Definition of done: tests green · leak check clean · measurement recorded under the
  lesson's Performance notes · review passed · probes answered.
- Often followed by a graduate task (small `build` lesson) moving the code into `engine/`.

## build
Code integrated into `engine/` (or a kata graduating into it).
- All groups. Unit tests where possible **plus** a demo checkpoint: "run it; you should
  see X" — graphics/audio correctness is verified by observation, not only by tests.
- Definition of done: tests green where applicable · demo checkpoint confirmed ·
  measurement recorded · review passed (layering law especially).

## design
The deliverable is a design, not an implementation (e.g., the RHI seam).
- Groups: Orient, Design (the main event — learner proposes, tutor critiques against
  cited industry references), Review, Finalize.
- Definition of done: agreed design recorded in `design.md`; spec delta captures any
  requirements it implies; probes answered.

## milestone
A playable thing (Breakout, Game 2). Integration project spanning multiple sessions.
- All groups; Build is dominant and may iterate Spec↔Build several times.
- Definition of done: it runs and is playable · stats overlay shows frame numbers ·
  retrospective recorded in the re-planning change that follows (what the engine was
  missing, what hurt) — that retrospective sets the next module's priorities.
