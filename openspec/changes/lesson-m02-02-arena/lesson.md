# Lesson: m02-02/arena — The arena allocator

> **Type:** kata · **Module:** m02 Memory & allocators · **Interface:** learner-designed (you sketch the arena's public API in `design.md`; the `Allocator_Proc` contract it plugs into is fixed by Odin — see the Exercise brief)

## Goals

- Implement your first real allocator: a bump (arena) allocator that hands out memory by advancing a single offset, and reclaims everything at once.
- Write the one `switch mode` procedure that satisfies Odin's `Allocator_Proc` contract, and decide what each of the eight modes _means_ for an arena (which do real work, which are no-ops, which return "unsupported").
- Get alignment right — the detail that separates a toy bump pointer from a correct allocator.
- Feel the lifetime model in your hands: allocate freely, never free individually, reset the whole region — and see why that's the dominant pattern in engines.

## Prerequisites

- **m02-01 (Odin's allocator model)** — this kata is the implementation half of that lesson. You explained `Allocator{procedure, data}`, the eight-mode `Allocator_Proc`, and errors-as-values; now you build one. Re-read your recall answers if the mode enum is fuzzy.
- **m00-02 (the warm-up kata)** — same harness: `core:testing`, `@(test)`, per-test leak checking, `odin test <pkg>`.
- **m00-01** — slices as (ptr, len) views that don't own; `rawptr`; ZII.

## Explanation

An arena (also "linear" or "bump" allocator) is the simplest allocator that is still genuinely useful. You hold a contiguous block of memory and a single integer `offset`. To allocate `n` bytes: round `offset` up to the requested alignment, remember that aligned position `p`, advance `offset` to `p + n`, and hand back the block `[p, p+n)`. That's the entire allocation path — a bounds check and a pointer add [[GB-MEM pt.2]](https://www.gingerbill.org/article/2019/02/08/memory-allocation-strategies-002/). There is no per-allocation bookkeeping, no free list, no header on each block. The cost of that simplicity is the defining constraint: **you cannot free one allocation.** The offset only moves forward. You reclaim memory by resetting the whole arena — offset back to zero — which frees _everything_ at once in O(1) [[GB-MEM pt.2]](https://www.gingerbill.org/article/2019/02/08/memory-allocation-strategies-002/).

That constraint is not a limitation to work around; it's the whole point. m02-01's "C++ habit vs DOD" callout said: stop pairing every allocation with a matching free, and instead ask _"what's the lifetime group, and who frees the group?"_ An arena **is** a lifetime group made concrete. Everything allocated into it shares one lifetime and dies together — all of this frame's scratch, all of this level's data. You already met one: `context.temp_allocator` is a per-thread arena, and `free_all(context.temp_allocator)` is the reset [[ODIN §Implicit context system]](https://odin-lang.org/docs/overview/#implicit-context-system). This kata builds that machine yourself.

### Alignment: the detail that bites

CPUs require (or strongly prefer) that a value of a given type live at an address that is a multiple of its alignment — an `i32` at a 4-byte boundary, an `f64` or pointer at 8, a SIMD vector at 16. The allocator's job is to honor the `alignment` argument the caller passes. A naïve bump — "return the current offset, then add `n`" — is wrong: after allocating a 1-byte value, the offset is odd, and the next 8-byte allocation would start on an odd address. Reading it may fault or, worse, silently run slow.

So before you use `offset`, you round it **up** to the next multiple of `alignment`. The bytes skipped by that rounding are padding — waste the arena accepts to keep every allocation aligned. Conceptually: `aligned = (offset + alignment - 1)` rounded down to a multiple of `alignment`. Odin gives you `mem.align_forward` (and friends) in `core:mem` if you'd rather not hand-roll the arithmetic [[ODIN-MEM mem]](https://pkg.odin-lang.org/core/mem/) — deciding whether to call it or write the math yourself is one of the design choices you'll make. Either way, **alignment is not optional**: it's the first thing your tests will probe, and the most common place a homemade allocator is subtly broken.

### One procedure, eight modes

Your arena plugs into the fixed contract from m02-01. You do not get to change this signature — it's what `context.allocator = my_arena` requires, and it's why any allocator can stand in for any other [[ODIN-MEM runtime.Allocator]](https://pkg.odin-lang.org/base/runtime/):

```odin
Allocator_Proc :: proc(allocator_data: rawptr, mode: Allocator_Mode,
                       size, alignment: int, old_memory: rawptr, old_size: int,
                       location := #caller_location) -> ([]byte, Allocator_Error)
```

Your whole implementation is one procedure with this signature that recovers your arena from `allocator_data` and `switch`es on `mode`. What each mode means _for an arena_ is a design decision — here's the map, but the choices (and the correctness details) are yours to make and defend in review:

| Mode | What an arena does | Why |
|---|---|---|
| `Alloc` | align, bump, return **zeroed** bytes | the default; zeroing is what keeps ZII true for heap data [[ODIN-MEM]](https://pkg.odin-lang.org/base/runtime/) |
| `Alloc_Non_Zeroed` | align, bump, return bytes **as-is** | skip the zeroing cost when the caller will overwrite immediately |
| `Free` | nothing (a no-op that succeeds) | an arena can't free one allocation — this is the defining trait, not a bug |
| `Free_All` | offset back to zero | the reset; the _only_ way an arena reclaims |
| `Resize` / `Resize_Non_Zeroed` | general case: alloc-new + copy old bytes | growing an arbitrary past allocation can't happen in place… |
| `Query_Features` | report which modes you support | lets generic code ask before it assumes |
| `Query_Info` | optional; report what you can | rarely needed for a kata arena |

Two subtleties worth thinking about before you design (not answered here — that's the exercise):

- **What does `Free` _return_?** It succeeds but frees nothing. There's a right answer for the returned slice and error; the leak-checking tracking allocator cares.
- **`Resize` has a cheap special case.** If the block being resized happens to be the _most recent_ allocation (it ends exactly at the current offset), you can grow or shrink it in place by just moving the offset — no copy. Recognizing "is this the last allocation?" is the kind of detail that makes an arena feel real. Whether you implement the fast path or fall back to alloc-and-copy for everything is your call.

When a request doesn't fit in the remaining space, you don't panic and you don't grow — you return `.Out_Of_Memory` (an `Allocator_Error` value) and an empty slice. Errors are values here, the same discipline as `or_return` from the warm-up kata [[ODIN-MEM runtime.Allocator]](https://pkg.odin-lang.org/base/runtime/).

> **C++ delta — where the arena's state lives.** In C++ you'd write a `class LinearAllocator` with `allocate`/`reset` methods and the offset as a private member; the `this` pointer carries the state. Odin's allocator is a _value_ — `Allocator{procedure, data}` — so your arena's state doesn't ride in `this`; it rides in the `data: rawptr`, and your procedure casts it back to `^Arena` on entry. Same idea (state + code), unbundled: the code is a free procedure, the state is a struct you point at. No vtable, no base class — assigning `context.allocator` swaps a 16-byte value.

> **C++ habit vs DOD approach — backing storage.** The C++ reflex is for the allocator to _own_ a heap block it `new[]`s in its constructor and `delete[]`s in its destructor (RAII). For this kata, take the data-oriented path instead: the arena **borrows** a fixed backing buffer the caller already has (a stack array, or one up-front allocation), and owns _none_ of it. That keeps the kata about the bump logic, makes the arena trivially resettable and copyable-by-reset, and sidesteps lifetime questions — the backing outlives the arena because the caller says so. (Production arenas like Odin's `mem.Arena` add growth by chaining blocks from a _backing allocator_; that's a real feature and explicitly **out of scope** here. We'll note where it would hook in, and you'll meet it again at the m02-04 graduate step.)

### What "done" looks like structurally

This is a **kata**: the code lives in isolation under `katas/arena/`, unit-tested, graduating into `engine/core` later at **m02-04** (the "core memory package" build lesson) alongside the pool allocator. So nothing you write here enters the engine's package tree or its living spec yet — this lesson's deliverable is a correct, leak-clean arena and the understanding behind it. Design the public API well anyway; m02-04 integrates exactly what you build here.

## In the industry

Arena/linear allocators are foundational engine infrastructure, not an exotic optimization. Gregory documents stack-based allocators (a linear allocator whose reset can also roll back to a saved marker) and per-frame allocators as standard engine support systems: a single-frame arena is filled during a frame and **reset to empty at the top of the next frame**, giving effectively free allocation for transient per-frame data and zero fragmentation [[GEA §6.2]](https://www.gameenginebook.com/). The pattern recurs at every timescale an engine has a natural lifetime boundary — per-frame, per-level, per-job — because matching allocator lifetime to data lifetime is what makes the O(1) bulk reset legal. Ginger Bill — who designed Odin's allocator system precisely so this pattern is a language-level default — presents the linear allocator as the first and most important strategy to internalize, for the same reasons: it is the cheapest possible allocation and the model the rest build on [[GB-MEM pt.2]](https://www.gingerbill.org/article/2019/02/08/memory-allocation-strategies-002/). Odin's `context.temp_allocator` is this idea shipped in the standard library.

## Performance notes

The cost model from m02-01, now made concrete by code you own. An arena `Alloc` is: one comparison (does it fit?), one alignment round-up (a few integer ops), one pointer add. That's single-digit nanoseconds and, critically, **constant** — it does not depend on how many allocations came before, it never locks, and it never fragments [[GB-MEM pt.2]](https://www.gingerbill.org/article/2019/02/08/memory-allocation-strategies-002/). `Free_All` is a single store (offset ← 0) regardless of how many allocations it reclaims — O(1) where the heap would be O(n) individual `free`s. The costs the arena _does_ pay: **internal fragmentation** from alignment padding (bytes skipped to align each block — usually small, but measurable with many tiny odd-sized allocations), and the inability to reclaim any single allocation, which is why you must match it to a lifetime group. There's also the same fixed indirect-call overhead every allocator pays (the call goes through `Allocator.procedure`), which m02-01 measured as negligible against real allocation work.

**Measurement task (tutor-run; numbers recorded in `curriculum/JOURNAL.md`):** once your arena is green, the tutor will write and run an Odin benchmark that, for a fixed count of small allocations, times **(a)** the default heap `context.allocator` vs **(b)** your arena, reporting ns/alloc and the speedup ratio, and separately times `free_all` on your arena against freeing the same count of heap allocations one at a time. The result should land your arena in the single-digit-ns/alloc range from m02-01's baseline and show the bulk-reset advantage directly. The tutor records the **Built + Measured** facts and walks you through them; you write **Takeaways + Reflections**.

## Exercise

Build the arena in a new kata package, `katas/arena/`, and drive it to green with `odin test katas/arena`.

**This lesson's interface is learner-designed — that's your first task.** Before any code, sketch the arena's public API in `design.md` (§Learner sketch). The tutor then critiques it and records the agreed interface; **tests are written only after that**. Decisions that are yours to make (and defend in review):

- The **`Arena` struct**: what state does a bump allocator need? (Backing storage, current offset — what else? Is tracking peak usage worth a field?)
- **Initialization**: how does a caller set up an arena over a fixed backing buffer they provide? What's the signature?
- **Getting an `Allocator`**: what procedure turns your `^Arena` into the `Allocator{procedure, data}` value you can assign to `context.allocator`?
- **Reset**: is resetting expressed only through the allocator's `Free_All` mode, or also as a directly-callable helper? Both?
- **Alignment**: `mem.align_forward`, or your own arithmetic?
- **Which modes** your `Allocator_Proc` supports, and what each returns — including the two subtleties flagged above (`Free`'s return; the `Resize` last-allocation fast path).

Fixed constraints (not yours to change): the arena borrows a **caller-provided fixed backing buffer** and does **not** grow; when a request doesn't fit it returns `.Out_Of_Memory`; your procedure must satisfy the `Allocator_Proc` signature exactly so it's assignable to `context.allocator`.

### Definition of done

- `odin test katas/arena` green · per-test leak check reports 0 leaks · `-vet -strict-style` clean
- Alignment, out-of-memory, and reset(reuse) behavior all covered by the tutor's tests and passing
- Review passed (per review-rubric.md), including ≥2 comprehension probes answered
- Measurement task run by the tutor; **Built + Measured** recorded in `curriculum/JOURNAL.md`
- **Takeaways + Reflections** written by you, in your own words

## Reading list

- **Required:** [Memory Allocation Strategies pt.2 — Linear/Arena Allocators [GB-MEM pt.2]](https://www.gingerbill.org/article/2019/02/08/memory-allocation-strategies-002/) — the arena end to end, by Odin's designer; the alignment and reset discussion is exactly this kata. Re-read the [`base:runtime` allocator interface [ODIN-MEM]](https://pkg.odin-lang.org/base/runtime/) entries for `Allocator_Proc`, `Allocator_Mode`, `Allocator_Error`.
- **Recommended:** [`core:mem` [ODIN-MEM]](https://pkg.odin-lang.org/core/mem/) — skim `align_forward` and, for reference _after_ you've designed yours, the `Arena` type (see how the standard library shapes the same API — don't copy it before you sketch your own).
- **Deeper:** [GEA §6.2](https://www.gameenginebook.com/) — stack/frame allocators as engine support systems; the per-frame reset pattern and why lifetime-matched allocation wins.
