# Lesson: m03-03/core-containers — Graduate: the core containers package

> **Type:** build (graduate) · **Module:** m03 Containers & handles · **Interface:** learner-designed (packaging + naming inside `engine/core` **plus** the engine-boundary handle-type decision; the pool's per-operation contract is locked from m03-02 and does not reopen)

## Goals

- Graduate the generational handle pool (m03-02) out of throwaway `katas/` and into `engine/core` as the permanent, reusable **core-containers** capability.
- Settle the question m03-02 explicitly deferred (critique finding 5): does the engine's container expose **one shared `Handle` type**, or a **caller-supplied `distinct` handle type per pool** (`$HT`)? This decision shapes every handle-based package boundary odyne will have from the platform layer on.
- Write the engine's second spec delta: `core-containers` requirements that merge into `openspec/specs/` and join the living contract next to `core-memory`.
- Prove the integration end-to-end: the testbed exercises a pool *through* `engine:core` (demo checkpoint), and the layering law still holds.

## Prerequisites

- **m03-02 (handle-pool)** — the code you're graduating: green, leak-clean, its per-op contract locked in that lesson's `design.md`.
- **m02-04 (core-memory)** — you've graduated code before; same rhythm, and your `engine/core/memory` packaging is now a precedent to weigh.
- **m03-01 (handles)** — `distinct` handles + ZII, and the layering law's "handle-based cross-package APIs" rule this lesson makes concrete.

## Explanation

### Second graduation — same rhythm, one genuinely new question

m02-04 taught the mechanics: pick a home, settle names for coexistence, carry a spec delta, prove the engine uses it. All of that repeats here and should feel routine. What's new is that the thing you're moving is **generic** (`Handle_Pool($T)` — your first parapoly struct) and its handle is about to become the *currency other packages trade in*. A graduate decision that was mostly aesthetic for allocators — names, package shape — now has a type-safety dimension the whole engine will live with.

### Where containers live

Same argument as m02-04, and it should take you one sentence to make: the kata imports `base:intrinsics` and `core:mem` — standard library only, nothing from any engine layer — so the pool sits cleanly in `core`, the bottom of `core → platform → render → game`. Gregory's runtime architecture puts container libraries in exactly this stratum: core low-level systems next to memory and math, beneath everything engine-specific [[GEA ch.1]](https://www.gameenginebook.com/). The compiler will re-verify acyclicity; you should be able to state *why* before it does.

### Packaging & naming: you now have two precedents

- **Your own:** `engine/core/memory` — *one package, many things*, coexistence via type prefixes (`arena_init`, `pool_init`), the `core:mem` shape. Your m02-04 journal note is worth re-reading: "for bigger packages this might be hard to maintain."
- **The stdlib's containers do the opposite:** `core:container` is a *family of sub-packages* — `queue`, `small_array`, `priority_queue`, `handle_map`, … — each holding **one** container with **unprefixed** names, so call sites read `queue.push_back(&q, x)` [[ODIN-CONTAINER]](https://pkg.odin-lang.org/core/container/queue/).

So the packaging question is live, not settled by precedent: `engine/core/containers` (one package; prefixed `pool_*` or `handle_pool_*` names; m41's job queue and m42's component storage move in later) versus `engine/core/handle_pool` or `engine/core/containers/handle_pool` (one sub-package per container; the kata's unprefixed `add`/`get`/`remove` survive as `handle_pool.add`). Weigh what call sites read like, where the future containers land, and the m02-04 lesson that a package cannot share a name with a stdlib package it imports (`package mem` vs `core:mem` — not a problem for any name proposed here, but check).

> **C++ delta:** in C++ this is namespace organization (`odyne::core::containers` vs one header per container) and costs almost nothing to change later. In Odin the package is the directory *and* the import path *and* the visibility boundary — call sites everywhere spell it — so it's cheaper to get right now than to migrate after three more containers exist.

### The handle-type decision (the crux)

Your m03-02 sketch proposed `Handle_Pool($T, $HT)` — a caller-supplied handle type — and the critique deferred it to keep the kata small: *"you chose shared-`Handle`-now, `distinct`-at-engine-boundaries-later — revisit at m03-03 where the engine wraps its own types."* This is that revisit, and it's the design conversation's main event:

- **(a) Shared core `Handle`.** The pool's API deals in one `Handle` type; each system that exposes handles across a package boundary wraps it (`Texture_Handle :: distinct u64`, explicit casts at the seam). Core stays exactly as simple as the kata. The cost is discipline: the wrap is manual, an unwrapped core `Handle` can leak through an API, and a texture handle passed to an entity lookup is only a compile error where someone remembered to wrap.
- **(b) Caller-supplied distinct handle type — `Handle_Pool($T, $HT)`.** `add` returns `$HT`, `get`/`remove`/`has` take `$HT`; each system instantiates the pool with its own `distinct` handle type, and wrong-system handles become compile errors *everywhere, by construction* — at zero runtime cost, since `distinct` changes the type, not the representation [[ODIN §Distinct types]](https://odin-lang.org/docs/overview/#distinct-types). This is Zylinski's `odin-handle-map` shape [[ZYL-HANDLES]](https://zylinski.se/posts/handle-based-maps-three-implementations/), and it is now the *standard library's* shape too: `core:container/handle_map` is generic over `$Handle_Type` [[ODIN-CONTAINER handle_map]](https://pkg.odin-lang.org/core/container/handle_map/). The cost lands in the pool's internals: pack/unpack must work through the caller's type (casts/transmute under a parapoly parameter, possibly a `where` constraint), and the ZII guarantee — the zero handle never validates — must provably survive the parametrization.

floooh argues the same position from C, where it's hardest: sokol wraps every public resource handle in its own single-field struct precisely so handles of different systems can't cross-assign [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html).

An instructive aside while you're in the stdlib's `handle_map`: it uses struct handles (`{idx, gen}` fields) with the **zero index reserved** as sentinel, where your kata packs a `u64` and starts **generations at 1** [[ODIN-CONTAINER handle_map]](https://pkg.odin-lang.org/core/container/handle_map/). Two different mechanisms enforcing the same invariant — ZII zero handle is invalid. The design space is real; your contract stays yours.

**What stays fixed either way:** the m03-02 agreed contract — packed + index table, FIFO freelist, retire-on-wrap, generations start at 1, garbage-safe validation, the whole per-op table. This lesson may change the *surface* (package, names, handle typing); it does not reopen semantics. The conformance tests will re-enforce the same table against the new surface.

> **C++ habit vs DOD approach:** option (b) is the phantom-tag idiom — `template<class Tag> struct Id { uint32_t v; };` — which C++ makes you build and maintain by hand, so the C++ instinct is "one Handle class, be careful at the boundaries" (a). Engine practice has drifted to per-system distinct handles precisely because "be careful" doesn't scale across a codebase; Odin gives you the idiom natively (`distinct` + parapoly), so the usual cost argument against (b) mostly evaporates. That doesn't decide it — (a) is a legitimate simplicity position — but decide on the merits, not the habit.

### The spec becomes real, part two

Like m02-04, this change carries an engine spec delta: `core-containers` — the observable guarantees of generational-handle storage (add/remove semantics, stale and garbage handle rejection, iteration over live items, ownership via the stored allocator, layering). The tutor writes it against the *agreed* interface, your tests trace to its scenarios, and it merges into `openspec/specs/core-containers/` at archive. After this lesson, "what may engine code assume about handles?" has a versioned answer.

### Prove it runs

The demo checkpoint keeps the graduation honest: the testbed builds a pool of something through `engine:core`, adds a few items, resolves and mutates through handles, demonstrates that a deliberately stale handle is refused, iterates via `slice` — and runs clean under the leak check. Small and observed, not benchmarked.

## In the industry

Containers sit in every engine's foundation layer — Gregory's core-systems stratum lists container libraries alongside the memory and math the rest of the engine is built on [[GEA ch.1]](https://www.gameenginebook.com/) — and referencing game objects by handle rather than pointer is the standard discipline [[GEA 3e §16.5]](https://www.gameenginebook.com/). The design you built is Bitsquid's ID lookup table [[BITSQUID]](https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html); the public-API version of this lesson's crux is visible in shipping code: sokol's per-resource distinct handle structs [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html), Zylinski's caller-typed Odin handle maps [[ZYL-HANDLES]](https://zylinski.se/posts/handle-based-arrays/), and the Odin stdlib's `core:container/handle_map` doing the same [[ODIN-CONTAINER handle_map]](https://pkg.odin-lang.org/core/container/handle_map/). When odyne's render layer arrives in phase 2, `Texture_Handle` and friends will be whatever you decide here.

## Performance notes

The pool's runtime numbers already exist (m03-02: add ≈ 4.5 / remove ≈ 3.0 ns, churn ≈ 3.9 ns/cycle, resolve ≈ 1.08 in-order / 3.8 shuffled ns/visit, iterate ≈ 0.24–0.30 ns/visit). The graduation adds no new runtime work, so this lesson measures the *move* and one sharp question:

**Measurement task (tutor-run; numbers recorded in `curriculum/JOURNAL.md`):**
1. **Build cost:** `odin test` time + test count for the new core package; testbed clean build (`-o:speed`) time + binary size vs m02-04's 464,384 B baseline — the "zero point" moves again.
2. **No-regression:** re-run the m03-02 bench against the engine package (import path changes only) — same ns within noise, since the bodies are unchanged.
3. **The distinct-type tax is zero — prove it:** if the agreed interface is (b), bench the same ops through a `distinct` `$HT` instantiation vs the kata's shared `Handle` — identical numbers expected, since `distinct` changes the type, not the representation [[ODIN §Distinct types]](https://odin-lang.org/docs/overview/#distinct-types). If (a), bench a system-side wrap/unwrap shim instead. Either way the claim "type safety is free at runtime" gets a number instead of an assertion.

## Exercise

Graduate the handle pool into `engine/core`, tested under the `engine` collection, with the testbed exercising it.

**Interface is learner-designed — that's your first task.** Sketch in `design.md` (§Learner sketch):

- **Packaging + naming:** package path and name, proc-naming shape, with the two precedents weighed (your `memory` package vs the stdlib's one-sub-package-per-container) and a stated landing spot for m41's job queue and m42's component storage.
- **The handle type (the crux):** shared core `Handle` with per-system wrapping, or `Handle_Pool($T, $HT)` with caller-supplied distinct handles — signatures either way, how the ZII zero-invalid guarantee survives, and how phase 2's render layer will consume it.
- **Everything else the surface changes**, if anything: `Handle_Error`'s name/home, `SENTINEL` exposure, `Slot` visibility.

The tutor critiques against the cited references and records the agreed surface; only then are the spec delta and failing conformance tests placed against it.

- **Move + adapt:** relocate the pool (and adapt its tests) into `engine/core` per the agreed surface. The m03-02 semantics don't change — packaging and typing do.
- **Layering:** the new package imports stdlib only; build stays acyclic under `-collection:engine=engine`.
- **Tested seam:** the tutor provides the `core-containers` spec delta and failing tests; you make them green in-engine.
- **Demo checkpoint:** the testbed exercises the pool through `engine:core` (add / get / mutate / stale-handle-refused / slice) and runs clean — confirmed by observation + leak check.
- **Constraints:** `odin test` green · leak-clean · `-vet -strict-style` clean across the tree.

### Definition of done

- `odin test` green for the new core package · leak check clean · `-vet -strict-style` clean across the engine
- Demo checkpoint confirmed: the testbed exercises the pool through `engine:core` and runs clean
- `core-containers` spec delta written and its scenarios covered by passing tests
- Layering verified (no upward/sideways imports; graph acyclic)
- Measurement recorded in `curriculum/JOURNAL.md` · review passed · ≥2 comprehension probes answered
- Journal **Takeaways + Reflections** in your own words

## Reading list

- **Required:** [ODIN §Packages](https://odin-lang.org/docs/overview/#packages) — sub-package import paths under a collection; [core:container/handle_map [ODIN-CONTAINER]](https://pkg.odin-lang.org/core/container/handle_map/) — skim the API: caller-supplied `$Handle_Type` in the stdlib, and how their variant differs from your kata; [ZYL-HANDLES three-implementations](https://zylinski.se/posts/handle-based-maps-three-implementations/) — the `$HT` shape in idiomatic Odin.
- **Recommended:** [FLOOOH](https://floooh.github.io/2018/06/17/handles-vs-pointers.html) — the typed-handles argument from C; [GEA ch.1](https://www.gameenginebook.com/) — containers in the core-systems layer; [GEA 3e §16.5](https://www.gameenginebook.com/) — object references via handles.
- **Deeper:** [BITSQUID](https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html) — re-read with your implementation behind you; your own m02-04 LESSON — the graduation you already did, and what you'd repeat or change.
