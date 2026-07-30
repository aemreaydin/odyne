# Proposal: normalize-engine-doc-comments

## Why

`update-tutor-stub-style` (`1cfb01f`) defined the documentation convention but deliberately
left existing code alone. Seven files under `engine/` predate it and sit far from it in both
directions — some carrying lesson prose, one package carrying nothing at all.

That matters beyond tidiness: `engine/core/containers/handle_pool` is the reference
implementation future lessons are read against, and it currently models the recipe style the
convention exists to prevent. Leaving it gives the tutor a bad example to pattern-match on.

| File | Density | Nature of the gap |
|---|---|---|
| `engine/core/timing/pacer.odin` | 56% | file header with `[GAFFER-TIMESTEP]` cite-key and lesson prose; `DEFAULT_FIXED_DT` explained across five lines |
| `engine/game/app.odin` | 51% | "WHY THE LOOP LIVES HERE AND NOT IN core" header with `[SDL]`/`[SOKOL]` cite-keys |
| `engine/core/timing/timing.odin` | 40% | lesson cross-references, m11-01 measurement numbers in source |
| `engine/core/memory/logging.odin` | 22% | light recipe |
| `engine/core/containers/handle_pool/handle_pool.odin` | 19% | recipe on `remove`, `clear`, `add` |
| `engine/core/memory/memory.odin` | 16% | arena's per-mode implementation table, graduated from the kata |
| `engine/platform/*` (5 files) | 0% | swept by hand 2026-07-27; non-trivial declarations now undocumented |

## What Changes

- **Strip lesson residue.** Teaching prose, cite-keys, lesson ids, and measurement numbers
  move out of source. Most of what those headers assert is **already in the specs** —
  `core-timing` already requires the pacer to consult no clock and to derive simulated time
  as a product rather than a sum; `game-loop`'s Purpose already carries the layering
  argument. So the headers are largely duplication and are simply deleted. Only two claims
  lack a home and are relocated rather than dropped: why the default rate is 50 Hz (to
  `core-timing`) and the commitment that the timing components stay usable without the
  engine-owned loop (to `game-loop`).
- **Convert recipe to contract.** Comments that narrate the body are rewritten to state
  caller-visible consequence, or removed where the signature already says it.
- **Document `engine/platform`.** Non-trivial declarations get one-line contracts:
  `Window_Handle`, `Window_Error` variants, `Window_Desc` fields, and the window/input
  procedures. `Key`'s sixty variants stay bare.
- **Remove file-wide headers** everywhere.

Out of scope: `katas/` (lesson snapshots — rewriting them edits the historical record),
test files (exempt by the convention), and any behavioural change. This is a comments-only
diff; `odin test` output must be identical before and after.

## Capabilities

### Modified Capabilities

- `core-timing`: absorbs the pacer/clock division-of-labour rationale currently living in
  `pacer.odin`'s header.
- `game-loop`: absorbs the "why the loop lives in `game` and not `core`" rationale currently
  living in `app.odin`'s header.

No requirement changes to `tutor-constitution` — the convention it already carries is what
this change applies.

## Impact

- Modified files: 7 named above plus `engine/platform/{window,window_sdl,input,input_sdl,platform}.odin`.
- Comments only — no signatures, no behaviour. Verified by `odin test` parity.
- **Partially reverses the 2026-07-27 sweep of `engine/platform`**, by design. That sweep
  removed rationale prose; what returns is one-line caller contract, including
  `// "" ⇒ "odyne"` and `// zero, stale, or foreign handle` verbatim. Confirmed as intended
  during the exploration that produced the convention.
- Expected direction of travel: the 40–56% files fall toward ~20%; `engine/platform` rises
  from 0% to roughly 10–15%.
