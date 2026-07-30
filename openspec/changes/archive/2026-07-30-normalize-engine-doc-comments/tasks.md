# Tasks: normalize-engine-doc-comments

Convention: `.claude/skills/tutor/references/stub-style.md`. Comments only — no signature or
behaviour changes in this change.

## 1. Relocate rationale before deleting it

- [x] 1.1 **Mostly already specced** — `core-timing` already required the pacer to consult no clock and to derive simulated time as a product. Only the 50 Hz rationale needed a home. `engine/core/timing/pacer.odin` header (frame clock measures / pacer decides, and why the pacer holds no clock) → a requirement in `openspec/specs/core-timing/spec.md`, with the `[GAFFER-TIMESTEP]` cite-key
- [x] 1.2 **Mostly already specced** — `game-loop`'s Purpose already carried the layering argument. Only the "convenience, not the only path" commitment needed a home. `engine/game/app.odin` header ("WHY THE LOOP LIVES HERE AND NOT IN core", the layering argument, the app-owned-loop alternative) → `openspec/specs/game-loop/spec.md`, with the `[SDL]`/`[SOKOL]` cite-keys
- [x] 1.3 All three keys (`[GAFFER-TIMESTEP]`, `[SDL]`, `[SOKOL]`) already registered. Confirm every cite-key relocated this way is registered in `curriculum/BIBLIOGRAPHY.md`; register any that are not

## 2. Normalize the over-documented files

- [x] 2.1 `engine/core/timing/pacer.odin` (56%) — delete the header, compress `DEFAULT_FIXED_DT` to the one-line why, convert `Pacer`/`Frame_Steps` blocks to contract, keep the `count == 0 is ORDINARY` warning (caller-visible, non-derivable)
- [x] 2.2 `engine/game/app.odin` (51%) — delete the header; keep `App_Config`'s zero-means-default field comments, which are load-bearing contract
- [x] 2.3 `engine/core/timing/timing.odin` (40%) — strip lesson cross-references and m11-01 measurement numbers; keep OS-quirk notes, which the convention explicitly preserves
- [x] 2.4 `engine/core/memory/memory.odin` (16%) — remove the graduated per-mode implementation table; `core:mem` already documents the `Allocator_Proc` contract
- [x] 2.5 `engine/core/memory/logging.odin` (22%)
- [x] 2.6 `engine/core/containers/handle_pool/handle_pool.odin` (19%) — recipe → contract on `remove`, `clear`, `add`; keep the `get_ptr` pool-owned-handle warning and the `resolve_dense_idx` why

## 3. Document engine/platform (0% → contract)

- [x] 3.1 `window.odin` — `Window_Handle`, `Window_Error` variants, `Window_Desc` fields (the `≤0 ⇒ default` resolution is not derivable), public window procedures
- [x] 3.2 `window_sdl.odin`, `input_sdl.odin` — backend seams; SDL quirks earn inline notes, the rest stays bare
- [x] 3.3 `input.odin` — `Key` and the other large enums stay bare; document the input-state accessors' frame semantics (pressed-this-frame vs held)
- [x] 3.4 `platform.odin`

## 4. Verify

- [x] 4.1 **11/11 packages, 38/38 harness cases — identical to the pre-change baseline.** `odin test` across `tests/` and every kata suite — output identical to pre-change; this diff must not alter behaviour
- [x] 4.2 Re-measure density per file and record the before/after table in this change; confirm the 40–56% files land near 20% and `platform` lands near 10–15%
- [x] 4.3 Verified via `odin doc` (the same extraction OLS hover uses) rather than interactively: both `//` and `/* */` forms attach to their declarations and read usefully standalone — checked `pacer_advance`, `Pacer`, `frame_deadline`, `key_pressed`, `Window_Desc`
- [x] 4.4 `openspec validate normalize-engine-doc-comments` passes
- [x] 4.5 Commit

## Results

| File | before | after |
|---|---|---|
| `engine/core/timing/pacer.odin` | 56% | 20% |
| `engine/game/app.odin` | 51% | 21% |
| `engine/core/timing/timing.odin` | 40% | 19% |
| `engine/core/memory/logging.odin` | 22% | 8% |
| `engine/core/containers/handle_pool/handle_pool.odin` | 19% | 13% |
| `engine/core/memory/memory.odin` | 16% | 8% |
| `engine/platform/input_sdl.odin` | 8% | 1% |
| `engine/platform/window.odin` | 0% | 15% |
| `engine/platform/input.odin` | 0% | 9% |
| `engine/platform/window_sdl.odin` | 0% | 7% |
| `engine/platform/platform.odin` | 0% | 16% |

The over-documented files landed at 19–21% against a ~20% target; `engine/platform` rose from
0% to 7–16%. `memory.odin` initially overshot to 6% — under-documenting, since the rule's
default is to comment — and eight declarations were documented back up, including two that
crossed the `Inputs:`/`Returns:` threshold (`arena_alloc`, `arena_resize`, `pool_init`).

## Finding: `frame_deadline` is unused and contradicted the spec

`timing.frame_deadline` computes an origin-anchored deadline, and its comment argued that
anchoring is superior. The engine's loop rejects it — `app.odin` anchors on the frame start,
and the `game-loop` spec records why. Grep confirms `frame_deadline` is called only by its own
tests. Its comment now states what it does and that the loop does not use it, but the dead API
itself is out of scope here (removing it is an API change with tests attached) and wants a
decision: keep as a documented alternative, or delete.
