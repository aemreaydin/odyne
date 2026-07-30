# Proposal: require-capability-purpose

## Why

When `openspec archive` first creates a capability spec it writes a placeholder Purpose —
`TBD - created by archiving change <name>. Update Purpose after archive.` — and nothing ever
comes back to replace it. Ten of twelve specs still carried theirs when they were fixed in
`3c0eecc`, some since June 10. The placeholder is the first thing a reader meets in the spec,
and it is a note to the author sitting where the description belongs.

Fixing the ten was a one-time cleanup. The mechanism that produced them is untouched: the
next lesson that introduces a capability writes a fresh placeholder, because the archive
ritual has no step that closes it. The instruction is even in the placeholder's own text —
"Update Purpose after archive" — it just belongs to nobody.

## What Changes

- **Amend the Archive ritual requirement** in `lesson-workflow` with a fourth required
  effect: a capability spec created by the archive carries a written Purpose before the
  archive is considered done.
- **Add the step to the archive skill**, after spec sync and before the summary — that is
  the point at which the placeholder exists, so it is the only place the check can run. A
  task in the lesson's finalize group cannot do it: `/opsx:archive` runs after the last
  finalize task, so the placeholder does not exist yet when those tasks execute.
- **Note it in the lesson `tasks.md` template** at the hand-off task, so the requirement is
  visible from the lesson side rather than only inside the archive skill.

Out of scope: the ten Purposes already written (`3c0eecc`), and the blank line
`openspec archive` strips between `## Purpose` and `## Requirements` — that is CLI
formatting this repo does not control, and it is recorded in `3c0eecc`'s message rather than
worked around.

## Capabilities

### Modified Capabilities

- `lesson-workflow`: the Archive ritual requirement gains a fourth effect covering the
  Purpose of any newly created capability spec.

## Impact

- Modified files: `.claude/skills/openspec-archive-change/SKILL.md` (new step),
  `openspec/schemas/lesson/templates/tasks.md` (hand-off task wording).
- No engine code, no tests, no curriculum changes.
- Affects every future lesson that introduces a capability. Lessons that only extend
  existing capabilities are unaffected, since no new spec file is created.
