# lesson-workflow Specification

## Purpose
TBD - created by archiving change add-tutor-skill. Update Purpose after archive.
## Requirements
### Requirement: One lesson, one change
Each lesson SHALL run as exactly one OpenSpec change using the project-local `lesson` schema, with lesson-shaped artifacts: `lesson.md` (explanation with citations), `design.md` (learner API sketch + tutor critique), `specs/` (requirements for the engine capability being built), and `tasks.md` (ownership-tagged checklist).

#### Scenario: Lesson start
- **WHEN** a new lesson begins
- **THEN** a new OpenSpec change is created under the `lesson` schema named `lesson-<module>-<nn>-<slug>`
- **AND** its artifacts follow the lesson templates

### Requirement: Task ownership tags
Every task line in a lesson's `tasks.md` MUST carry exactly one ownership tag: `[tutor]` (executed by the agent) or `[you]` (executed by the learner).

#### Scenario: Tasks generated
- **WHEN** the tutor generates a lesson `tasks.md`
- **THEN** every task line contains `[tutor]` or `[you]`

### Requirement: Apply hard-stop at learner tasks
During apply, the agent SHALL execute `[tutor]` tasks in order and MUST stop at the first incomplete `[you]` task: it summarizes the current state, hands off, and MUST NOT implement, complete, or check off that task or any deliverable it covers.

#### Scenario: Hard stop
- **WHEN** apply reaches an incomplete `[you]` task
- **THEN** the agent stops executing tasks, states what the learner needs to do, and ends the turn without writing the learner's deliverable

#### Scenario: Resume after learner work
- **WHEN** the learner reports a `[you]` task complete (e.g., tests now pass)
- **THEN** the agent verifies the observable outcome (test run, file existence) before marking it done and continuing to the next task

### Requirement: Learner-designed interfaces
For lessons involving API design, the agreed interface MUST be recorded in the lesson's `design.md` (learner sketch plus tutor critique) before the tutor writes tests against it. Lessons MAY be flagged `interface: provided` for early lessons where the tutor supplies the interface; the flag and rationale appear in `lesson.md`.

#### Scenario: Design before tests
- **WHEN** a lesson includes API design and `design.md` does not yet record an agreed interface
- **THEN** the tutor does not write tests and instead requests or critiques the learner's sketch

### Requirement: Lesson specs describe the engine
Each lesson's `specs/` delta SHALL specify the engine capability being built or extended (e.g., `core-memory`), so that archiving accumulates an accurate living specification of the engine under `openspec/specs/`.

#### Scenario: Lesson archived
- **WHEN** a lesson change is archived
- **THEN** its spec delta merges into `openspec/specs/<capability>/spec.md` reflecting what the engine now provably does

### Requirement: Archive ritual
Archiving a lesson SHALL produce all of the following, via the lesson's finalize task group plus the standard archive command: (1) spec deltas merged into `openspec/specs/`; (2) the lesson explanation — measured numbers included — persisted under `curriculum/modules/<module>/<lesson>/`; (3) `curriculum.yaml` updated (lesson `done`, newly unblocked lessons `available`).

#### Scenario: Lesson completes
- **WHEN** review is complete and the lesson change is archived
- **THEN** all three effects are present in the repository in the same commit or commit series

