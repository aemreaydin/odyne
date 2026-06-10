# curriculum-tracking Specification

## Purpose
TBD - created by archiving change add-tutor-skill. Update Purpose after archive.
## Requirements
### Requirement: Progress map structure
`curriculum/curriculum.yaml` SHALL be the single source of truth for curriculum position. It SHALL define modules (id, title, phase, prerequisite module ids) and their lessons (id, title, type ∈ {concept, kata, build, design, milestone}, status), plus a pointer to the active lesson's OpenSpec change name when one is in flight.

#### Scenario: Reading position
- **WHEN** any session needs to know curriculum position
- **THEN** `curriculum.yaml` alone identifies the active lesson (if any) and the set of available next lessons

### Requirement: Lesson status lifecycle
Each lesson SHALL have exactly one status: `locked` (prerequisites unmet), `available` (prerequisites done), `active` (in flight as an OpenSpec change), or `done` (archived). Statuses SHALL only transition `locked → available → active → done`.

#### Scenario: Prerequisites satisfied
- **WHEN** the last prerequisite lesson of a locked lesson reaches `done`
- **THEN** that lesson's status becomes `available`

### Requirement: Single active lesson
At most one lesson SHALL be `active` at a time.

#### Scenario: Starting a second lesson
- **WHEN** the learner asks to start a new lesson while another is `active`
- **THEN** the tutor warns, names the active lesson, and proceeds only on explicit confirmation (parking the active lesson with a state note in its `tasks.md`)

### Requirement: Resume from files alone
A fresh session SHALL be able to reconstruct full working position from files only — `curriculum.yaml`, the active change directory (its `tasks.md` checkboxes give position within the lesson), the lesson's `lesson.md`, and `openspec/specs/` — with no dependence on prior chat history.

#### Scenario: New session with active lesson
- **WHEN** a new session begins and `curriculum.yaml` points at an active lesson
- **THEN** the tutor summarizes the lesson, the completed tasks, and the first incomplete task, then continues from exactly there

### Requirement: Journal
Each completed lesson SHALL append one entry to `curriculum/JOURNAL.md` containing: date, lesson id, what was built, measured performance numbers (when the lesson had a measurement task), review takeaways, and the learner's reflections.

#### Scenario: Lesson archived
- **WHEN** a lesson is archived
- **THEN** `JOURNAL.md` contains an entry for it with the required fields

### Requirement: Progress report
On request, the tutor SHALL report progress as a module/lesson tree with statuses and a short "you are here" summary derived from `curriculum.yaml`.

#### Scenario: Learner asks for status
- **WHEN** the learner asks where they are in the curriculum
- **THEN** the tutor renders the tree with per-module completion and names the active or next available lesson

