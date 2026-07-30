# Tasks: update-tutor-stub-style

## 1. Write the convention

- [x] 1.1 Create `.claude/skills/tutor/references/stub-style.md` with: the consequence-not-procedure rule; the selection rule (every definition unless trivial ≡ fully recoverable from name and type); the no-file-wide-comments rule with the relocation targets (`openspec/specs/`, `design.md`, `lesson.md`); the test-file exemption
- [x] 1.2 Add the format section: `//` for one line, `/* */` for multi-sentence, `Inputs:`/`Returns:` only at ≥3 parameters carrying real contract with the receiver and defaulted allocator excluded from the count
- [x] 1.3 Add worked before/afters drawn from real files — `handle_pool.remove` (recipe → contract), `pacer.DEFAULT_FIXED_DT` (five lines → one), `app.odin`'s "WHY THE LOOP LIVES HERE" header (→ `game-loop` spec) — plus the ≈4-of-18 calibration table showing which declarations stay bare

## 2. Wire it into the skill

- [x] 2.1 `SKILL.md` §1: replace "stub declarations (signatures + doc comments + `unimplemented()` bodies)" with a definition that names the consequence-not-procedure rule, and point at `references/stub-style.md` alongside the existing rubric and lesson-type pointers
- [x] 2.2 `SKILL.md` §4 (hint ladder): note that stub comments are subject to the ladder — a comment describing implementation strategy is a rung-2/3 hint delivered unprompted
- [x] 2.3 Decide `unimplemented()` vs the current `// TODO(you)` + `_ =` discard pattern for stub bodies (design.md open question) and make `SKILL.md` §1 and `tasks.md` 3.1 agree on the answer — **`unimplemented()`, nothing else**; verified with `odin check` that its `-> !` return terminates parapoly bodies with named returns, so no discards or placeholder returns are needed
- [x] 2.4 `openspec/schemas/lesson/templates/tasks.md` task 3.1: name the convention so it is in front of the generator at stub-writing time, and apply the 2.3 decision
- [x] 2.5 `references/review-rubric.md`: add a documentation checklist item covering implementation narration, file-wide headers, leaked lesson content, and undocumented non-trivial declarations (new item 7; self-check renumbered to 9)

## 3. Verify

- [x] 3.1 Dry-run the convention against `4b7b827`'s handle-pool stub: rewrote it in full and type-checked with generics instantiated (`odin check`, exit 0). **46% → 23% comment density**, 130 → 84 lines, against a ~25% prediction. Bare: `has` plus the three type declarations whose contract sits on their fields. No comment describes a body
- [x] 3.2 Confirm the rewritten stub still supports red-before-green — verified empirically: `unimplemented()` yields a **clean per-test red** (`[FATAL] not yet implemented`, "1 test failed", re-run hint) and the runner isolates it, so sibling tests still execute. Strictly better than the `_ =` + placeholder pattern, whose red was an opaque value mismatch
- [x] 3.3 `openspec validate update-tutor-stub-style` passes
- [ ] 3.4 Commit

## 4. Hand off

- [ ] 4.1 Open the follow-up change `normalize-engine-doc-comments` for the retroactive pass over `engine/core/timing/{pacer,timing}.odin`, `engine/game/app.odin`, `engine/core/memory/{memory,logging}.odin`, `engine/core/containers/handle_pool/handle_pool.odin`, and `engine/platform/*` — noting that platform goes up from 0% and that this reverses part of the 2026-07-27 sweep by design
