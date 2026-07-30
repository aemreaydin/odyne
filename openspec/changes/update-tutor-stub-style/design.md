# Design: update-tutor-stub-style

## The four species

Auditing tutor-generated stubs (`4b7b827`, the m03-02 handle-pool stub: 61 of 130 lines carry a comment) separates four things currently wearing one costume:

| # | Species | Example | Verdict |
|---|---|---|---|
| ① | File header recap | 18 lines restating design.md's packed-plus-index-table layout | delete |
| ② | Recipe | `init ... threads the FIFO freelist 0→capacity-1` | delete |
| ③ | Contract | `get_ptr returns a LOAN, valid only until the next remove/clear/destroy` | keep |
| ④ | Lesson residue | `m11-01 measured 1,989.9 ms over 100,000 frames`; `[SDL SDL_AppIterate]` | relocate to specs |

① and ④ are file-wide by nature. ② is the hint-ladder bypass. Only ③ is documentation.

## The governing distinction: consequence, not procedure

A doc comment serves the **caller**, not the implementer.

```
          stub doc comment
                 │
      ┌──────────┴───────────┐
      ▼                      ▼
 the learner, today     the caller, forever
 "what do I build?"     "how do I call this?"
      │                      │
      │                      └─▶ ownership, lifetime, invalidation,
      │                          error conditions, units, invariants
      │
      └─▶ already served by lesson.md + design.md + the failing
          tests. Serving it a fourth time in the stub is both
          duplication and a hint-ladder bypass.
```

This single rule separates the `get_ptr` comment (keep — nothing in the signature says the pointer is a loan) from the `remove` comment (cut — it narrates the swap-with-last algorithm sitting directly beneath).

It is also why the rule is worth stating as *consequence, not procedure* rather than merely *be brief*: brevity alone would compress the recipe rather than remove it, and the recipe is the part that costs the learner the exercise.

## Selection: every definition unless trivial

> **Trivial ≡ fully recoverable from the declaration's name and type.**

Applies to procs, structs, enums, distinct types, constants, and struct fields. Calibrated against `handle_pool`'s 18 declarations:

```
comment                                     │  bare (trivial)
────────────────────────────────────────────┼──────────────────
SENTINEL       what it terminates            │  is_empty
Handle         packing is invisible          │  increment_gen
Error.Full     "full" of what, when          │  pack_handle
Slot.gen       gen 0 = retired forever       │  unpack_handle
init           capacity range, ownership     │
clear          how it differs from destroy   │
add            when .Full happens            │
remove         reordering invalidates loans  │
get_ptr        the loan rule                 │
slice          invalidation + order          │
resolve_*      the why (private, non-obvious)│
```

≈4 of 18 bare. The test keeps genuinely load-bearing field comments (`fixed_dt: time.Duration, // 0 ⇒ timing.DEFAULT_FIXED_DT`) and rules out `Key`'s sixty enum variants before they are written.

## Format

Both forms are extracted by `odin doc` and shown on OLS hover, so the choice is calibration, not capability.

**One line → `//`. Multi-sentence → `/* */`.** Matches what `engine/core/containers/handle_pool` already does. The block form costs two lines of delimiter per comment; measured on a full rewrite of the handle-pool stub, blocks-everywhere landed at ~34% density where `//` for one-liners lands at ~25%, against 47% today.

**The `Inputs:`/`Returns:` form only at ≥3 parameters carrying real contract.** Odin core uses it in 44 of 981 files — it is the exception, not the default. The raw parameter count misfires, so the receiver and an idiomatic `allocator := context.allocator` do not count toward the three:

```odin
init :: proc(p: ^Handle_Pool($T, $HT), capacity: int, allocator := context.allocator)
//           └ receiver        └ 1 real constraint    └ idiomatic boilerplate
//   raw count = 3 → would fire, and produce "- p: The pool" — restatement noise.
//   adjusted count = 1 → stays with the short form. Correct.

alloc :: proc(a: ^Arena, size: int, alignment: int, zero: bool)
//            └ receiver  └ 3 params each carrying contract: alignment must be a
//                          power of two, zero changes semantics, size interacts
//   adjusted count = 3 → fires, and earns it.
```

## Worked example

```odin
// ── before (tutor stub, 4b7b827) ──────────────────────────────────
// remove deletes the item `h` refers to: the last dense item is swapped into
// the gap and its slot is patched via dense_to_slot; the freed slot's
// generation is bumped (wrap-to-0 ⇒ retired, else FIFO-enqueued).
// Invalid/stale/zero/garbage handle → .Invalid_Handle (never panics).

// ── after ─────────────────────────────────────────────────────────
/*
Removes the item `h` refers to. Remaining items may be reordered, invalidating
pointers from `get_ptr` and slices from `slice`. An invalid handle returns
`.Invalid_Handle` rather than panicking.
*/
```

Everything a caller can act on survives. The algorithm — the learner's exercise — does not.

## Decisions

| Decision | Rationale |
|---|---|
| Convention lives in `references/stub-style.md`, not inline in `SKILL.md` | `SKILL.md` is the constitution and stays scannable; the reference carries before/afters, which is what makes the rule reproducible |
| Scope is uniform across `engine/`, `platform` included | `platform` is a library surface — `render` and `game` call it. A carve-out would need re-litigating at every new package |
| Test files exempt | Their comments explain why a tier exists, which is not caller contract and has proven useful |
| Katas untouched | Lesson snapshots; rewriting them edits the historical record for no maintenance gain |
| Retroactive pass split into its own change | Large mechanical diff would drown a four-file convention change in review; also wants the written convention to exist first |

## Risks

- **"Trivial" is a judgment call and will drift.** Mitigated by stating the operational test rather than the adjective, and by the review-rubric check. Some drift is acceptable; the rule is meant to leave `Init_Failed`-style borderline cases open.
- **The convention restores comments deleted on 2026-07-27.** `// "" ⇒ "odyne"` and `// zero, stale, or foreign handle` come back verbatim in `engine/platform` under the derivability test. This is consistent with the sweep's intent — it targeted rationale prose, and these were collateral — but it is a visible reversal and is called out here so it is not discovered in a diff. Confirmed in the exploration that `platform` is in scope.
- **Under-documenting is the opposite failure.** The rule's default is *comment*, with trivial as the escape, precisely so the correction does not overshoot into `engine/platform`'s 0%.

## Resolved: stub bodies are `unimplemented()`

Settled on evidence rather than taste. `unimplemented` is declared `-> !`, so it terminates
a body of any return signature — `odin check` accepts it for parapoly procedures with named
returns, with no `_ =` discards and no placeholder returns. That removes four lines of
scaffolding per procedure.

The concern worth testing was the red: `unimplemented()` panics, and a panic could abort the
test binary rather than failing one test. It does not — Odin's runner isolates it:

```
[FATAL] --- [thing.odin:6:add()] not yet implemented:
Finished 2 tests in 431µs. 1 test failed.
 - redtest.add_returns_none    not yet implemented:
```

The sibling test still ran, and the failure names the cause. The discard pattern's red was an
opaque value mismatch (`expected 0, got 1`), which is strictly worse for red-before-green.
