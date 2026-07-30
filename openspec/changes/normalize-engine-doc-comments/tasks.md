# Tasks: normalize-engine-doc-comments

Convention: `.claude/skills/tutor/references/stub-style.md`. Comments only — no signature or
behaviour changes in this change.

## 1. Relocate rationale before deleting it

- [ ] 1.1 `engine/core/timing/pacer.odin` header (frame clock measures / pacer decides, and why the pacer holds no clock) → a requirement in `openspec/specs/core-timing/spec.md`, with the `[GAFFER-TIMESTEP]` cite-key
- [ ] 1.2 `engine/game/app.odin` header ("WHY THE LOOP LIVES HERE AND NOT IN core", the layering argument, the app-owned-loop alternative) → `openspec/specs/game-loop/spec.md`, with the `[SDL]`/`[SOKOL]` cite-keys
- [ ] 1.3 Confirm every cite-key relocated this way is registered in `curriculum/BIBLIOGRAPHY.md`; register any that are not

## 2. Normalize the over-documented files

- [ ] 2.1 `engine/core/timing/pacer.odin` (56%) — delete the header, compress `DEFAULT_FIXED_DT` to the one-line why, convert `Pacer`/`Frame_Steps` blocks to contract, keep the `count == 0 is ORDINARY` warning (caller-visible, non-derivable)
- [ ] 2.2 `engine/game/app.odin` (51%) — delete the header; keep `App_Config`'s zero-means-default field comments, which are load-bearing contract
- [ ] 2.3 `engine/core/timing/timing.odin` (40%) — strip lesson cross-references and m11-01 measurement numbers; keep OS-quirk notes, which the convention explicitly preserves
- [ ] 2.4 `engine/core/memory/memory.odin` (16%) — remove the graduated per-mode implementation table; `core:mem` already documents the `Allocator_Proc` contract
- [ ] 2.5 `engine/core/memory/logging.odin` (22%)
- [ ] 2.6 `engine/core/containers/handle_pool/handle_pool.odin` (19%) — recipe → contract on `remove`, `clear`, `add`; keep the `get_ptr` pool-owned-handle warning and the `resolve_dense_idx` why

## 3. Document engine/platform (0% → contract)

- [ ] 3.1 `window.odin` — `Window_Handle`, `Window_Error` variants, `Window_Desc` fields (the `≤0 ⇒ default` resolution is not derivable), public window procedures
- [ ] 3.2 `window_sdl.odin`, `input_sdl.odin` — backend seams; SDL quirks earn inline notes, the rest stays bare
- [ ] 3.3 `input.odin` — `Key` and the other large enums stay bare; document the input-state accessors' frame semantics (pressed-this-frame vs held)
- [ ] 3.4 `platform.odin`

## 4. Verify

- [ ] 4.1 `odin test` across `tests/` and every kata suite — output identical to pre-change; this diff must not alter behaviour
- [ ] 4.2 Re-measure density per file and record the before/after table in this change; confirm the 40–56% files land near 20% and `platform` lands near 10–15%
- [ ] 4.3 Spot-check hover text in OLS on three normalized procedures — the contract should read usefully without the surrounding file
- [ ] 4.4 `openspec validate normalize-engine-doc-comments` passes
- [ ] 4.5 Commit
