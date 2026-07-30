# Proposal: update-tutor-stub-style

## Why

The tutor skill tells itself to write "stub declarations (signatures + doc comments + `unimplemented()` bodies)" and never defines what a doc comment is. `tasks.md` 3.1 omits comments entirely. With the field unspecified, generation defaults to teaching prose, and the result is stubs whose comments restate `lesson.md` and `design.md` at length — noise next to the code, and duplication of the documents that already own that content.

Two consequences follow.

**The comments pre-spoil the exercise.** The constitution meters help through a four-rung hint ladder, then the stub hands over an algorithm walkthrough before the learner has asked for anything. `katas/handle_pool` shipped `// init ... threads the FIFO freelist 0→capacity-1, and sets every slot's generation to 1` — rung-3 pseudocode delivered at rung 0. `katas/arena` shipped a sixteen-line mode-by-mode table of what each `switch` branch must do.

**The prose survives into the engine, and it is compounding.** Stub comments outlive the lesson: `TODO(you)` markers get deleted, paragraphs do not. Comment density by lesson order, tutor-generated:

| Lesson | File | Density |
|---|---|---|
| m02-02 | `katas/arena/arena.odin` | 10% |
| m03-02 | `engine/core/containers/handle_pool/handle_pool.odin` | 19% |
| m11-01 | `engine/core/timing/timing.odin` | 40% |
| m11-02 | `engine/game/app.odin` | 51% |
| m11-02 | `engine/core/timing/pacer.odin` | 56% |

`engine/platform` sits at 0% only because it was swept by hand on 2026-07-27. The newest files carry teaching prose, lesson cross-references (`m11-01's "derive, don't accumulate" rule`), measurement numbers from the lesson's Performance notes, and cite-keys (`[SDL SDL_AppIterate]`) — all of which have homes in `openspec/specs/` and `curriculum/`.

The fix is to specify the missing field: a documentation convention modelled on Odin's own core library, enforced at stub-generation time and checked at review.

## What Changes

- **Define the convention** in a new `.claude/skills/tutor/references/stub-style.md`: selection rule (every definition unless trivial, where trivial means fully recoverable from name and type), content rule (state consequence, not procedure), no file-wide comments, and the two Odin formats with the threshold between them.
- **Replace "doc comments"** in `SKILL.md` §1 with a definition and a pointer to the reference.
- **Update `tasks.md` template 3.1** to name the convention. Reconcile the same line's `unimplemented()` instruction with what stubs actually emit (`// TODO(you)` plus `_ =` discards and placeholder returns) — the two produce different reds and the template should say which is intended.
- **Add a review-rubric check** so drift is caught on the lesson that introduces it rather than three modules later.
- **Amend the `tutor-constitution` spec**: stub comments are governed by the hint ladder, and documentation joins the review duties.

Out of scope: the retroactive pass over existing `engine/` files (separate change, `normalize-engine-doc-comments`, which depends on this one landing first so it has a written convention to normalize against). Katas are lesson snapshots and are not touched by either change.

## Capabilities

### Modified Capabilities

- `tutor-constitution`: gains a stub-documentation requirement (format and selection rule), extends the division-of-labor requirement so stub comments cannot bypass the hint ladder, and adds documentation to the review duties alongside the existing modularity check.

## Impact

- New files: `.claude/skills/tutor/references/stub-style.md`.
- Modified files: `.claude/skills/tutor/SKILL.md` (§1), `.claude/skills/tutor/references/review-rubric.md` (new checklist item), `openspec/schemas/lesson/templates/tasks.md` (task 3.1).
- No engine code changes, no test changes, no curriculum changes.
- Test files are explicitly exempt from the convention and stay as they are.
- Affects every lesson generated after this lands; the existing engine drift is addressed separately.
