# Design: add-tutor-skill

## Context

odyne's curriculum will run as a long series of tutored lessons across many fresh AI sessions. All teaching state must therefore live in files, and the rules that protect the learning value (the learner implements; the tutor explains, tests, reviews) must survive session boundaries and different entry points (tutor skill, raw `opsx:*` commands). OpenSpec is already initialized with the stock `spec-driven` schema; its experimental `schema` feature supports project-local forks (`openspec schema fork`), per-artifact templates, and `config.yaml` carries a project-wide `context` block plus per-artifact `rules`.

## Goals / Non-Goals

**Goals:**
- A lesson lifecycle that is fully file-backed and resumable from disk alone.
- A constitution that no fresh session can miss, regardless of which command it enters through.
- Lesson artifacts shaped for teaching (explanation, learner-designed interface, engine spec delta, ownership-tagged tasks).
- The repo becomes a git repository with sensible Odin ignores.

**Non-Goals:**
- Curriculum content, module DAG entries, bibliography entries (Change 2: `add-engine-curriculum`).
- Engine code, build scripts, or Vulkan SDK setup.
- New slash commands or external tooling.

## Decisions

### D1: Lesson workflow as a forked OpenSpec schema
`openspec schema fork spec-driven lesson`, then adapt artifacts to: `lesson` (explanation) → `design` (interface) → `specs` (engine capability delta) → `tasks` (ownership-tagged). Templates bake the constitution into the artifact structure itself.
- *Alternative considered*: stock schema + naming conventions only — weaker, because templates are the one thing every generating session reads.
- *Fallback* (the feature is experimental): keep the stock `spec-driven` schema for lessons and carry the lesson templates inside the tutor skill (`.claude/skills/tutor/templates/`), enforced via `config.yaml` per-artifact `rules`. The implementation task probes the fork end-to-end (create dummy lesson change, generate artifacts, validate, delete) and selects primary or fallback based on what actually works.

### D2: Where the lesson explanation lives
Primary: the `lesson` artifact's output path targets `curriculum/modules/<module>/<lesson>/LESSON.md` directly (outside the change dir) if the schema supports it — explanations are permanent course material, not change ephemera, and must survive archive without a copy step. Fallback: `lesson.md` inside the change dir plus a `[tutor]` finalize task that copies it into `curriculum/modules/` before archive.

### D3: Constitution stated three times
The division-of-labor rules appear in (1) the tutor skill, (2) `openspec/config.yaml`'s `context` block (≤ ~30 lines, so every artifact generation inherits it), and (3) the lesson `tasks.md` template header. Redundancy is deliberate: sessions enter through different doors (tutor conversation, `opsx:apply` directly), and the failure mode being prevented — the agent helpfully implementing the learner's exercise — destroys the project's entire value.

### D4: Ownership tag format
`- [ ] 1.2 [tutor] Write failing arena tests` / `- [ ] 2.1 [you] Implement arena push/alloc`. Hard-stop semantics: the agent never writes, completes, or checks off a `[you]` deliverable; after the learner reports completion, a subsequent `[tutor]` verification task confirms the observable outcome (e.g., runs `odin test`) and only then marks progress.

### D5: Archive ritual as in-lesson tasks, not a customized archive command
The extra archive effects (persist explanation if D2 fallback, update `curriculum.yaml`, journal entry) are the final task group of every lesson's `tasks.md`, executed before running stock `/opsx:archive` (which handles spec-delta merging). Customizing the archive skill itself is avoided — less surface against experimental/updating OpenSpec internals.

### D6: Single source of truth for position
`curriculum.yaml` holds the map and the active-change pointer; per-lesson state lives only in that lesson's change dir (`tasks.md` checkboxes). Nothing else duplicates status. Resume = read `curriculum.yaml` → follow pointer → read `tasks.md`.

### D7: No new slash commands
The tutor skill is invoked conversationally ("start the next lesson", "resume", "status") and delegates lifecycle mechanics to the existing `opsx:propose/apply/archive` skills. Wrapper commands can be added later if real friction appears; starting without them keeps one fewer layer to maintain.

### D8: Git from day one
`git init` + Odin-appropriate `.gitignore` + initial commit in this change. Lessons end with a commit at finalize; the learner's implementation history becomes reviewable diffs and an auxiliary journal.

## Risks / Trade-offs

- [Experimental schema breaks on an OpenSpec upgrade] → Schema files are committed to the repo; D1 fallback is documented in the tutor skill and can be adopted without data loss (artifacts are plain markdown either way).
- [Agent drift: a future session implements a `[you]` task anyway] → Triple-stated constitution (D3) + hard-stop spec + review rubric includes a self-check line ("did the tutor write any implementation this lesson?").
- [Config `context` bloat slows every artifact generation] → Cap at ~30 lines; the full constitution lives in the skill, config carries only the summary and a pointer.
- [Lesson-per-change overhead feels heavy for tiny concept lessons] → Lesson templates scale down (a concept lesson's tasks.md may be 4 lines); if overhead still grates, batch micro-lessons into one change per module section — decide after the pilot module.

## Open Questions

- ~~Does the experimental schema support output paths outside the change dir (D2 primary)?~~ **Resolved 2026-06-10**: `openspec schema validate` accepts path traversal in `generates`, but the field is a static pattern with no per-lesson variables — a fixed outside path would collide across lessons, and out-of-dir artifacts would not move with the change at archive. **D2 fallback adopted**: `lesson.md` lives in the change dir; finalize task 6.3 copies it to `curriculum/modules/<module>/<lesson>/LESSON.md`.
