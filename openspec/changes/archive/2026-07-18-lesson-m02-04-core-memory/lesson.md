# Lesson: m02-04/core-memory — Graduate: the core memory package

> **Type:** build (graduate) · **Module:** m02 Memory & allocators · **Interface:** learner-designed (you decide how the two allocators are packaged and named inside `engine/core`; the allocator APIs themselves are already agreed from m02-02/03)

## Goals

- Graduate the arena (m02-02) and pool (m02-03) out of throwaway `katas/` and into `engine/core` as a permanent, reusable **core-memory** capability.
- Make two allocators coexist in one package — the naming/packaging decision you dodged while each kata lived alone.
- Write your first **engine spec delta**: `core-memory` requirements that merge into `openspec/specs/` and become part of the engine's living contract.
- Prove the integration end-to-end: the engine actually *allocates through* a core allocator (a demo checkpoint), and the layering law still holds.

## Prerequisites

- **m02-02 (arena)** and **m02-03 (pool)** — the code you're graduating. Both are done, green, leak-clean.
- **m01-01 (skeleton)** — the `engine:` collection, the `core → platform → render → game` layering, `-vet -strict-style`, and the `odin test <pkg>` / `odin build` workflow. This lesson lands code into the spine you built there.

## Explanation

A kata proves a data structure works in isolation. Graduating it is a different skill: deciding where it lives, what its public surface is once other code depends on it, and how it coexists with its siblings. That's the whole job here — almost no new allocator code, all integration and API judgment.

### Where memory lives: the bottom of the stack

Allocators are foundational — everything above them allocates *through* them — so they belong in the lowest layer, `core`. m01-01's law is `core → platform → render → game`, imports pointing down only [[GEA ch.1]](https://www.gameenginebook.com/). `core` may import nothing else in-engine. Check your allocators against that: the arena and pool depend only on `base:runtime` (the `Allocator` interface) and `core:mem` (helpers like `align_forward`) — both *standard library*, not engine layers. So they sit cleanly at the bottom; nothing about them reaches upward. The compiler will confirm it (an upward import is a `Cyclic importation` error), but you should be able to say *why* it holds before you rely on the toolchain.

### Two allocators, one package: the naming problem

While each allocator lived alone in its own kata package, unqualified names were free: `arena.init`, `pool.init` — the *package* disambiguated. Put both into a single package and that breaks: you can't have two `init` procedures, two `allocator` procedures, in the same package. Odin resolves a name within a package once; a collision is a compile error. You have to decide the shape:

- **Flat in `package core`, type-prefixed names** — `Arena`, `arena_init`, `arena_allocator`; `Pool`, `pool_init`, `pool_alloc`. This is exactly what Odin's own `core:mem` does (`arena_init`, `pool_init`, …) precisely because it holds many allocators in one package [[ODIN-MEM mem]](https://pkg.odin-lang.org/core/mem/). Call sites read `core.arena_init(...)`.
- **A dedicated sub-package** — e.g. `engine/core/mem/`, imported as `engine:core/mem`, giving `mem.Arena` / `mem.arena_init`. Watch the clash: you already `import "core:mem"` for the stdlib; two things called `mem` in one file need an import alias.
- **Separate sub-packages** — `engine/core/arena/` and `engine/core/pool/`, keeping the katas' unprefixed names (`arena.init`, `pool.init`) at the cost of two packages instead of one.

None is "wrong" — but the lesson title says *package* (singular), and there's a real trade between a flat prefixed surface and nested packages. You'll sketch your choice in `design.md` and defend it: which reads best at the call site, which matches the engine's conventions, which you'd still be happy with when `core` also holds containers (m03), math (m30), and logging.

> **C++ delta:** this is the promotion every prototype faces — from a `.cpp` you were hacking on to a header-stable module other translation units include. In C++ you'd fret over the header's public surface, ABI, and namespace (`odyne::core::mem`). Odin's version is lighter — no header, the "namespace" is just the package/directory — but the *decision* is the same: what's the public API, and what's the internal helper (`@(private="file")`)? Your kata already sorted public-vs-private; now settle the naming across two of them.

### The spec becomes real

The katas built genuine capability but merged *no* spec delta — the engine's living spec (`openspec/specs/`) only ever claimed what was actually in `engine/`. Now it's true: arena + pool enter `engine/core`, so this change carries a `core-memory` spec delta that describes the observable engine behavior (allocation, bulk reset, individual free, alignment, error modes) and merges into `openspec/specs/core-memory/` at archive. The tutor writes the requirements; your tests trace to their scenarios. From here on, "what does the engine's memory layer guarantee?" has a written, versioned answer.

### Prove it runs

A graduate isn't done when the moved tests pass — it's done when the *engine* uses it. The demo checkpoint: something in the running app allocates through a core allocator and works. Keep it honest and small (e.g., the testbed sets up a core arena over a buffer, allocates a few things via `context.allocator`, and the program runs clean under the leak check). Not a benchmark — a proof of integration.

## In the industry

Every engine has a memory module sitting in its foundation layer, beneath everything else, exposing the allocators the rest of the engine is built on. Gregory places memory management among the core low-level systems that the entire engine depends upon, deliberately at the bottom so every higher system can allocate through it while it depends on nothing above [[GEA §6.2]](https://www.gameenginebook.com/), [[GEA ch.1]](https://www.gameenginebook.com/). Odin's standard library models the same shape — one `core:mem` package holding arena, pool, stack, and more, each type-prefixed — which is why "flat, prefixed, in one package" is the path of least surprise for an Odin engine [[ODIN-MEM mem]](https://pkg.odin-lang.org/core/mem/). The graduation discipline itself (prototype in isolation, then promote into the layered tree with a stable surface and a spec) is standard engineering hygiene, not ceremony.

## Performance notes

This lesson's cost is mostly about the *build*, not new runtime work — the allocators already have their numbers (m02-02: arena ~15 ns/alloc; m02-03: pool ~11.5/4.5 ns alloc/free). What changes is the engine's compile: `core` grows from a near-empty package to one holding two allocators, and Odin recompiles a package as a unit [[ODIN §Packages]](https://odin-lang.org/docs/overview/#packages). m01-01 recorded the "zero point" (a nearly-empty four-package build); this is the first real addition to watch against it.

**Measurement task (tutor-run; numbers recorded in `curriculum/JOURNAL.md`):**
1. `odin test engine/core` time and test count before vs after the graduate (the core package's test-build cost with the allocators in it).
2. Clean build of the testbed (`-o:speed`) time + binary size vs m01-01's baseline — how much the memory package adds to the "zero point."
3. A quick re-confirm that an arena/pool allocation through `engine:core` still hits the same ns/op it did in the kata (no regression from the move).

## Exercise

Graduate the arena and pool into `engine/core`, tested under the `engine` collection, with the engine using a core allocator.

**Interface is learner-designed — that's your first task.** Sketch in `design.md` (§Learner sketch) the packaging + naming: flat-in-`core` (type-prefixed), a `mem` sub-package, or separate sub-packages — with the call-site trade-offs and how it scales when `core` later holds containers/math/logging. The tutor critiques and records the agreed shape; then the failing tests are placed against it.

- **Move + adapt:** relocate the arena and pool (and their tests) into `engine/core` per your agreed layout, renaming for coexistence. The *bodies* don't change — this is packaging, not reimplementation.
- **Layering:** `core` imports only `base:runtime` / `core:mem` (stdlib), nothing from `platform`/`render`/`game`. Build stays acyclic.
- **Tested seam:** the tutor provides the `core-memory` spec delta and the failing engine tests (adapted from your kata suites); you make them green in-engine.
- **Demo checkpoint:** the testbed (or app) allocates through a core allocator and runs clean — proof of integration, confirmed by observation + leak check.
- **Constraints:** `odin test engine/core` green · leak-clean · `-vet -strict-style` clean across the tree.

### Definition of done

- `odin test engine/core` green · leak check clean · `-vet -strict-style` clean across the engine
- Demo checkpoint confirmed: the app allocates through a core allocator and runs clean
- `core-memory` spec delta written and its scenarios covered by passing tests
- Layering verified (no upward/sideways imports; graph acyclic)
- Measurement recorded in `curriculum/JOURNAL.md` · review passed · ≥2 comprehension probes answered
- Journal **Takeaways + Reflections** in your own words

## Reading list

- **Required:** [ODIN §Packages](https://odin-lang.org/docs/overview/#packages) — packages-as-directories, collections, and sub-package import paths (`engine:core/mem`); skim [`core:mem` [ODIN-MEM]](https://pkg.odin-lang.org/core/mem/) to see how the stdlib names many allocators in one package.
- **Recommended:** [GEA §6.2](https://www.gameenginebook.com/) — engine memory management as a foundation system; [GEA ch.1](https://www.gameenginebook.com/) — the layered stack and why memory sits at the bottom.
- **Deeper:** your own m01-01 LESSON — re-read the layering-law section; this is the first capability that tests it with real, depended-upon code.
