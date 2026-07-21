# Lesson: m03-02/handle-pool — The generational handle pool

> **Type:** kata · **Module:** m03 Containers & handles · **Interface:** learner-designed (m03-01 fixed the *concepts* — index + generation, stale detection, O(1) everything; the storage layout, bit budget, ownership story, and API shape are yours to design in `design.md`)

## Goals

- Build the container m03-01 described: a **generational handle pool** mapping `Handle` → item of type `T`, with O(1) add/remove/resolve and deterministic stale-handle detection.
- Write your first **parapoly container** — a struct generic over `$T` — and feel where Odin's parametric polymorphism differs from C++ templates in practice.
- **Commit to a storage layout** (array-with-holes or packed + index table), a **bit budget**, and a **wraparound policy** — and defend them in the design review.
- Beat the baselines: resolve at m03-01's measured levels (~0.4 ns sequential, ~1.6 ns shuffled), add/remove in the m02-03 pool's single-digit-ns territory.

## Prerequisites

- **m03-01 (handles, not pointers)** — the entire conceptual load: anatomy, staleness, the two layouts, the borrowing rule. This kata is that lesson made executable.
- **m02-03 (the pool)** — you've threaded a freelist through slots before; the handle pool is that machine with liveness made checkable.
- **m00-02 (warm-up katas)** — `find` already used `$T`; now a whole *struct* is generic.

## Explanation

The m02-03 pool recycles memory blocks in O(1) — but it hands back **raw pointers**, so a caller holding a freed block's pointer has the exact silent-wrong-object bug from m03-01. This kata closes that hole. Same slot-recycling core, three genuinely new things:

1. **Generations.** Each slot carries a counter; the pool hands out `Handle{index, generation}` instead of a pointer; resolve compares and refuses stale handles [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html). Use-after-free stops being undefined behavior and becomes a `false` you can test for.
2. **Typed items.** The m02-03 pool dealt in `[]byte`; this container stores *values of a type* — `Handle_Pool(Particle)`, `Handle_Pool(Texture)` — via parapoly, not `rawptr` casts.
3. **A container API, not an allocator.** No `Allocator_Proc`, no mode switch, no interface indirection: plain procedures (add, remove, resolve/get, valid, iterate — the names are yours). That's also a performance hypothesis worth testing: without the allocator-interface dispatch that dominated the m02-02/03 numbers, your add/remove should *beat* the m02-03 pool's ~11.5/4.5 ns.

### The layout is now a decision, not a comparison

m03-01 taught both storage designs [[BITSQUID]](https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html); the kata builds **one**. What the choice actually commits you to:

- **Array-with-holes** — items live at their slot, forever. Freelist threads the dead slots (your m02-03 muscle). Resolve is one indirection; item addresses are stable until freed; iteration must skip dead slots, so it degrades as occupancy drops.
- **Packed + index table** — items live in a dense array; slots hold `generation` + a dense index; remove swaps the last item into the gap and patches its slot. Iteration is a linear walk over purely live items at m03-01's case-(a) speed; resolve pays one extra hop; **item addresses change on any remove** — which sharpens the borrowing rule from "don't store the pointer across frames" to "don't hold it across *any* mutation of the pool."

Zylinski's Odin implementations ship as variants of exactly these trade-offs (fixed static array; growing arena-backed; pointer-stable) [[ZYL-HANDLES]](https://zylinski.se/posts/handle-based-arrays/) — evidence that there's no single right answer, only a right answer *for a workload*. Pick for the kata, name the workload you're picking for, and note what m03-03's graduation into `engine:core` might want later.

### The bit budget is a contract

Whatever the handle looks like — packed `u64`, packed `u32`, or a two-field struct — its widths are promises: index bits bound how many items can be live at once; generation bits bound how many times one slot can be reused before your probe-1 wraparound policy has to act (retire the slot vs. widths that make wrap unreachable). And the **zero handle must be invalid** — `Handle{}` from ZII must never resolve; *how* you arrange that (reserve slot 0, start generations at 1, or another trick) is a design decision the tests will check.

> **C++ delta — parapoly is not templates.** An Odin generic struct takes its type parameter explicitly — roughly `Handle_Pool :: struct($T: typeid) {...}` — and procedures constrain against it; each instantiation monomorphizes, like templates, but there's no SFINAE, no implicit duck typing, no header-only contortions: the polymorphic parameter is declared, visible, and checked at the call boundary ([the overview's parametric-polymorphism material [ODIN]](https://odin-lang.org/docs/overview/)). One consequence to design around: a shared `Handle` struct works for every `Handle_Pool(T)` — if you want *compile-time* separation between, say, texture handles and entity handles, that's a `distinct` wrapper decision (m03-01), and worth a sentence in your sketch: does the kata's pool mint one handle type, or per-type handles? (There's no wrong answer at kata scope — the engine will make distinct types at package boundaries in m03-03 regardless.)

> **C++ habit vs DOD approach.** The C++ reflex for "generic container of game objects with stable references" is `std::unordered_map<Id, T>` or `std::vector<std::unique_ptr<T>>` — per-node heap allocations, pointer identity, and invalidation rules you memorize from cppreference. m03-01's bench put the map at ~4× the array designs and 24–30× dense iteration. The DOD shape you're building instead: **value storage in flat arrays allocated once, integer identity, invalidation as data** (the generation), zero per-item heap traffic after init. When the resolve API tempts you to return something clever — a wrapper that auto-revalidates, a "smart handle" — resist: return `(^T, bool)` and let the borrowing rule be a *convention with a test*, not machinery. That's how the shipping designs do it [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html).

### What "done" looks like structurally

Same shape as m02: a **kata** under `katas/handle_pool/`, unit-tested in isolation with `odin test katas/handle_pool`, leak-clean, vet-clean. Nothing enters `engine/` yet — m03-03 ("Graduate: core containers package") moves it into `engine:core` and lands the `core-containers` spec delta, the same rhythm as m02-04 did for the allocators.

## In the industry

This exact container, under different names, is production furniture: Bitsquid's ID lookup table is the same slots + freelist + id-check design documented from their shipping engine [[BITSQUID]](https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html); floooh's rules — central per-type arrays, index-handles public, pointers transient — distill the same structure from the sokol-style C libraries [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html); Gregory's survey of object-referencing schemes lands on handles/ids for exactly the liveness-and-relocation reasons you measured [[GEA §16.5]](https://www.gameenginebook.com/); and in the Odin ecosystem the community reference is Zylinski's `odin-handle-map` with its three storage variants [[ZYL-HANDLES]](https://zylinski.se/posts/handle-based-arrays/). Downstream of this kata: the same structure carries entity ids in ECS designs, where the entity is "generally represented as a unique integer value" [[ECS-FAQ]](https://github.com/SanderMertens/ecs-faq) — m42 will build on precisely what you build here.

## Performance notes

The baselines this pool must live up to are already in your journal (m03-01, tutor-run):

- **Resolve:** ~0.41 ns/visit in storage order, ~1.61 ns shuffled — the generation check itself was ~0.2 ns. Your real pool's resolve should match the scaffolding's numbers; if it's meaningfully slower, something structural crept in (an extra indirection, a branch that doesn't predict, a fat slot struct blowing cache density).
- **Add/remove:** the m02-03 pool posted ~11.5 ns alloc / ~4.5 ns free *through the allocator interface*, and we attributed most of that to interface dispatch + mode switch + zeroing. Your add/remove are direct calls — the hypothesis is single-digit ns for both, and the measurement will confirm or embarrass it.
- **Iteration:** holes-layout iteration cost depends on occupancy (skipping dead slots); packed-layout iteration should sit at dense-array speed (~0.23 ns/item). Whichever you build, the bench will show the shape.

**Measurement task (tutor-run; numbers recorded in `curriculum/JOURNAL.md`):** once your pool is green, the tutor benchmarks it (`katas/handle_pool_bench/`): **(a)** add/remove churn ns/op vs the m02-03 pool and the heap; **(b)** resolve ns/visit in storage order and shuffled, vs the m03-01 scaffolding baselines; **(c)** a stale-mix resolve (e.g. half the handles stale) to price the failed-check path and its branch behavior; **(d)** full iteration at high and low occupancy. Tutor records **Built + Measured** and walks you through it; you write **Takeaways + Reflections**.

## Exercise

Build the generational handle pool in a new kata package, `katas/handle_pool/`, and drive it to green with `odin test katas/handle_pool`.

**Interface is learner-designed — that's your first task.** Sketch the public API in `design.md` (§Learner sketch); the tutor critiques against the sources, the agreed interface is recorded, and only then are stubs and failing tests written. Decisions that are yours:

- **Storage layout:** holes or packed + index table — commit, and name the workload you're optimizing for.
- **The `Handle`:** representation (packed integer or struct; widths), how "zero is invalid" is guaranteed, and whether pools of different `T` share one handle type or get distinct ones.
- **Generation policy:** when the counter bumps (m03-01 said on free — where exactly in your remove path?), and your wraparound answer from probe 1 (retire vs. wide) made concrete: field width + the branch that enforces it.
- **Memory & ownership:** caller-provided backing slices at init (the m02 kata convention) or allocator-owned via `make` with an explicit allocator parameter — either is defensible; state who owns what, what init requires, and what (if anything) needs a destroy.
- **API surface & semantics:** the names (add/insert, remove/free, get/resolve, valid, len/count, iteration) and the edge cases — full pool, remove with a stale handle, double-remove, resolve of the zero handle. Every edge needs a defined answer; the tests will bind to all of them.

Fixed constraints (not yours to change): add, remove, and resolve are **O(1)**; stale handles are **detected** (generation mismatch resolves to failure, never to the wrong item); the **zero handle is invalid**; **no per-item heap allocation** after init; the tests bind to the agreed interface and run under `core:testing` with the leak check clean.

### Definition of done

- `odin test katas/handle_pool` green · per-test leak check 0 leaks · `-vet -strict-style` clean
- Stale-handle detection, slot reuse, zero-handle rejection, exhaustion, remove edge cases, and iteration all covered by the tutor's tests and passing
- Review passed (per review-rubric.md), including ≥2 comprehension probes answered
- Measurement task run by the tutor; **Built + Measured** recorded in `curriculum/JOURNAL.md`
- **Takeaways + Reflections** written by you, in your own words

## Reading list

- **Required:** ["Handles are the better pointers": An Odin gamedev follow-up [ZYL-HANDLES]](https://zylinski.se/posts/handle-based-arrays/) — the design in Odin terms, before you sketch; [the ID lookup table [BITSQUID]](https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html) — re-read the two array designs with implementer's eyes.
- **Recommended:** [Handles are the better pointers [FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html) — re-skim the "what to do / what to avoid" rules; the [parametric-polymorphism material in the Odin overview [ODIN]](https://odin-lang.org/docs/overview/) before writing your first generic struct.
- **Deeper:** the [`odin-handle-map` repo [ZYL-HANDLES]](https://github.com/karl-zylinski/odin-handle-map) — **after** your sketch is agreed, compare against the three variants; [GEA §16.5](https://www.gameenginebook.com/) — where this sits among the referencing schemes.
