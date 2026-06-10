# Proposal: add-tutor-skill

## Why

odyne is a game engine built in Odin/Vulkan whose primary purpose is teaching its author engine programming. Before any curriculum content or engine code exists, the project needs the learning infrastructure itself: a tutor system that explains topics with verified citations, writes failing tests, hands implementation to the learner, reviews the result — and preserves all of that context in files so any future session can resume from disk instead of from chat history.

## What Changes

- Add a project-local **tutor skill** (`.claude/skills/tutor/`) carrying the tutor constitution: the AI writes explanations, citations, stubs, tests, and reviews; the learner writes **all** implementations. Includes the hint ladder, C++-delta explanation style, and per-lesson "In the industry" + performance-measurement requirements.
- Add a custom OpenSpec **`lesson` workflow schema** (fork of `spec-driven`) so every future lesson runs as one OpenSpec change (`propose → apply → archive`) with lesson-shaped artifacts: `lesson.md` (explanation), `design.md` (learner's API sketch + critique), `specs/` (engine requirements), `tasks.md` (ownership-tagged checklist). `[you]`-tagged tasks are hard-stops for the agent.
- Update **`openspec/config.yaml`** with a project `context` block summarizing the constitution so every artifact generated in any session inherits the rules.
- Scaffold **`curriculum/`**: `curriculum.yaml` (progress map: module DAG, lesson statuses `done/active/locked`), `BIBLIOGRAPHY.md` (cite-key registry format), `JOURNAL.md` (learning devlog).
- Housekeeping: `git init`, `.gitignore` suitable for Odin builds, initial commit.

Out of scope: curriculum content (module DAG entries, lessons, bibliography entries — that is Change 2, `add-engine-curriculum`) and any engine code.

## Capabilities

### New Capabilities
- `tutor-constitution`: Rules of engagement for tutored lessons — division of labor (tutor explains/specs/tests/reviews; learner implements), hint ladder escalation, C++-delta explanation style, mandatory "In the industry" and performance-measurement sections, modularity/layering review duties.
- `lesson-workflow`: Lifecycle of a lesson as an OpenSpec change — the `lesson` schema's artifacts, task ownership tags, apply-time hard-stop semantics, and the archive ritual (spec deltas merge into `openspec/specs/`, lesson explanation persists under `curriculum/`, progress map and journal update).
- `curriculum-tracking`: The progress map — `curriculum.yaml` structure, lesson status transitions, prerequisite gating, and the session-resume procedure (reconstruct position from files alone).
- `bibliography`: Citation discipline — cite-key registry format, "cite only registered keys" rule, link-verification requirement for new entries.

### Modified Capabilities
(none — no specs exist yet)

## Impact

- New files: `.claude/skills/tutor/SKILL.md` (+ reference docs), `openspec/schemas/lesson/` (schema + templates), `curriculum/curriculum.yaml`, `curriculum/BIBLIOGRAPHY.md`, `curriculum/JOURNAL.md`, `.gitignore`.
- Modified files: `openspec/config.yaml` (context block; per-artifact rules).
- Repo becomes a git repository (currently not initialized).
- No engine code, no external dependencies. The OpenSpec `schema` feature is experimental; design.md defines a fallback if forking proves unworkable.
