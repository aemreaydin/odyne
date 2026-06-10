# Tasks: add-tutor-skill

## 1. Housekeeping

- [ ] 1.1 `git init`, create `.gitignore` (Odin build outputs: `*.exe`, `*.pdb`, `*.obj`, `*.bin`, build dirs; profiler traces; OS noise)
- [ ] 1.2 Initial commit of existing scaffolding (`openspec/`, `.claude/`) and this change's artifacts

## 2. Lesson workflow schema

- [ ] 2.1 `openspec schema fork spec-driven lesson` — confirm project-local schema files appear and `openspec schemas` lists `lesson`
- [ ] 2.2 Adapt schema artifact chain to: `lesson` → `design` → `specs` → `tasks`, with descriptions and dependency order matching the lesson-workflow spec
- [ ] 2.3 Probe D2: test whether a schema artifact can output to `curriculum/modules/**` (outside the change dir); record result in design.md Open Questions and pick D2 primary or fallback
- [ ] 2.4 Write `lesson` artifact template: Goals/Prereqs · Explanation (cite-keys only) · "In the industry" · Performance notes · Exercise spec · Definition of done · Reading list
- [ ] 2.5 Write `design` artifact template: learner interface sketch · tutor critique · agreed interface · `interface: provided` escape hatch with rationale field
- [ ] 2.6 Write `tasks` artifact template: constitution header (hard-stop rule), ownership-tagged task groups (orient/study/design/spec/build/review), finalize group (measurement results → journal, curriculum.yaml update, persist explanation if D2 fallback, commit)
- [ ] 2.7 `openspec schema validate lesson` passes

## 3. Tutor skill

- [ ] 3.1 Write `.claude/skills/tutor/SKILL.md`: full constitution (division of labor, hint ladder, C++-delta style, industry+performance requirements, modularity review duties), lesson lifecycle (one lesson = one change; propose→apply→archive), resume procedure (files only: curriculum.yaml → active change → tasks.md), single-active-lesson rule
- [ ] 3.2 Write `.claude/skills/tutor/references/review-rubric.md`: review checklist (correctness beyond tests, idioms, memory behavior, layering law, handle-based boundaries, ≥2 comprehension probes, tutor self-check: "did the tutor write any implementation this lesson?")
- [ ] 3.3 Write `.claude/skills/tutor/references/lesson-types.md`: the five types (concept/kata/build/design/milestone) with their definitions of done and how templates scale down for small lessons

## 4. OpenSpec config

- [ ] 4.1 Add `context` block to `openspec/config.yaml` (≤30 lines): project purpose, constitution summary, ownership-tag hard-stop rule, cite-key rule, layering law, pointer to tutor skill for the full version
- [ ] 4.2 Add per-artifact `rules` reinforcing: lesson explanations cite registered keys only; tasks must carry ownership tags

## 5. Curriculum scaffolding

- [ ] 5.1 Create `curriculum/curriculum.yaml`: schema comment block (module/lesson fields, statuses locked/available/active/done, active-change pointer) with empty module list awaiting Change 2
- [ ] 5.2 Create `curriculum/BIBLIOGRAPHY.md`: format header documenting entry fields (cite-key, title, author, type, URL/ISBN, verified date) and citation-granularity convention, with no entries yet
- [ ] 5.3 Create `curriculum/JOURNAL.md`: header documenting the per-lesson entry format (date, lesson, built, measurements, takeaways, reflections)

## 6. Verification

- [ ] 6.1 `openspec validate` passes across the project
- [ ] 6.2 End-to-end dry run: create a throwaway change under the `lesson` schema, generate all four artifacts from templates for a fake micro-lesson, confirm ownership tags + hard-stop wording render correctly, then delete it
- [ ] 6.3 Resume drill: from the dry-run state, confirm a files-only read (`curriculum.yaml` → change dir → `tasks.md`) reconstructs position per the curriculum-tracking spec
- [ ] 6.4 Final commit
