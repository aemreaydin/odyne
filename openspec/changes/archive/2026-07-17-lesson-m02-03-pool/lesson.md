# Lesson: m02-03/pool — The pool allocator

> **Type:** kata · **Module:** m02 Memory & allocators · **Interface:** learner-designed (you sketch the pool's public API in `design.md`; the `Allocator_Proc` contract it plugs into is fixed by Odin, same as the arena)

## Goals

- Build the arena's counterpoint: an allocator that hands out **fixed-size blocks** and can **free any single block in O(1)** — then reuse it.
- Understand the intrusive **free list** — the trick where the list of free blocks lives *inside the free blocks themselves*, needing zero side metadata.
- Implement `.Free` for real this time (the arena couldn't), and see why fixed block size is exactly what makes that O(1) and fragmentation-free.
- Decide what the fixed-size constraint means for the other modes — especially `.Resize` and what a request larger than a block should do.

## Prerequisites

- **m02-02 (the arena)** — same harness, same `Allocator_Proc` contract, same borrowed-backing model. This lesson is a direct compare-and-contrast: hold the arena in mind the whole way.
- **m02-01 (the allocator model)** — the eight modes and errors-as-values.
- **m00-01** — `rawptr`, slices as (ptr, len), ZII.

## Explanation

The arena bought O(1) allocation and O(1) bulk reset by giving up one thing: freeing a single allocation. The pool allocator makes the opposite trade. It fixes **one thing** — every allocation is the same size, one *block* — and in exchange it can free and recycle any individual block in O(1), with no fragmentation ever [[GB-MEM pt.4]](https://www.gingerbill.org/article/2019/02/16/memory-allocation-strategies-004/). Where the arena suits "many allocations, one lifetime" (a frame, a level), the pool suits "many objects of the same kind, churning independently" — particles, bullets, network packets, entity slots.

You carve a backing buffer into `N` equal-size blocks up front. The allocator's entire job is to track *which blocks are free* and hand them out / take them back. The naïve way to track that is a side array of booleans or a bitmap — but there's a far better one.

### The free list lives in the free blocks

Here is the idea that makes a pool elegant: **a free block isn't doing anything, so store the bookkeeping in it.** Keep a single `head` pointer to the first free block. Inside that block's memory, store a pointer to the *next* free block; inside that one, a pointer to the next; and so on — a singly-linked list threaded through the free blocks, terminated by nil. No separate metadata, no bitmap: the list *is* the free memory [[GB-MEM pt.4]](https://www.gingerbill.org/article/2019/02/16/memory-allocation-strategies-004/).

Two operations, both O(1):

- **allocate** = pop the head: return `head`, and set `head` to the next pointer stored in that block. (The block's bytes are now the caller's to overwrite.)
- **free** = push onto the head: write the current `head` into the freed block's first bytes, then point `head` at the freed block.

That's it. No searching, no coalescing, no fragmentation — every block is interchangeable because every block is the same size. `init` (and `.Free_All`) just walks the buffer once, wiring each block's link to the next to build the initial list.

> **C++ delta — the block is a union of two roles.** When a block is *free*, its first bytes hold a `next`-free pointer; when *allocated*, those same bytes hold the caller's data. Same storage, two lives — in C++ you'd model it with a `union { Node* next; std::byte data[BlockSize]; }` or a `reinterpret_cast<Node*>(block)`. In Odin you reinterpret the block's `rawptr` (e.g. as a `^rawptr`, or a tiny header struct) to read/write the link. The consequence that bites: a block must be **at least `size_of(rawptr)` bytes** (and aligned enough to hold one), or the link doesn't fit. That's a real constraint on your block size.

### One procedure, eight modes — and this time `.Free` does something

The pool plugs into the same fixed `Allocator_Proc` contract from m02-01/02-02. What changes from the arena is where the interesting work moves — `.Free` is now a first-class operation, and the fixed size reshapes the others:

| Mode | What a pool does |
|---|---|
| `.Alloc` / `.Alloc_Non_Zeroed` | pop a block off the free list; `.Alloc` zeroes it. Free list empty → `.Out_Of_Memory` |
| `.Free` | **push the block back onto the free list** — real, O(1), and the whole point vs the arena |
| `.Free_All` | re-thread the entire buffer into one fresh free list (all blocks free again) |
| `.Resize` | the tricky one — blocks are fixed size (decide below) |
| `.Query_Features` | report the modes you support |
| `.Query_Info` | optional |

Two things to work out in your design (not answered here):

- **What does a request whose `size` exceeds the block size do?** A pool serves exactly one size class. Asking for more than a block holds isn't something it can satisfy — there's a right error to return.
- **What is `.Resize`, when every block is one size?** If the new size still fits in a block, resizing is a no-op that returns the same block. If it doesn't, the pool can't grow it in place (and can't split/coalesce). Decide what each case returns — this is genuinely different from the arena's bump-resize.

> **C++ habit vs DOD approach.** The instinct from C++ is `new Particle` / `delete Particle` per object — every create/destroy hits the global heap, fragments it, and pays malloc's bookkeeping and locking. The pool is the data-oriented answer for fixed-size objects: one up-front allocation, then create/destroy become a pointer pop/push into a contiguous slab. No fragmentation, no per-object heap overhead, cache-friendly layout, and you can cap the count (the pool *is* your budget). Reach for a pool the moment you have "lots of the same thing, coming and going."

### What "done" looks like structurally

Same shape as the arena: a **kata** under `katas/pool/`, unit-tested in isolation, graduating into `engine/core` at **m02-04** (the "core memory package" build) alongside the arena. Nothing here enters the engine tree or its living spec yet — the deliverable is a correct, leak-clean pool and the understanding of when to choose it over an arena.

## In the industry

Pool allocators are standard engine infrastructure for fixed-size objects. Gregory documents pool allocation as a core memory-management strategy: when you allocate many objects of the same size (his examples include matrices, iterators, links), a pool built from a preallocated block with a free list of elements gives allocation and freeing that are both fast and fragmentation-free [[GEA §6.2]](https://www.gameenginebook.com/). The pattern scales into the engine's object model — fixed pools for particles, projectiles, audio voices, and (with a generation counter, which is exactly m03's handle pool) entity slots. Ginger Bill presents the pool as the natural next step after the linear/stack allocators, precisely because it adds *individual* free back at the cost of a single fixed size — and shows the free-list-in-free-blocks construction this kata builds [[GB-MEM pt.4]](https://www.gingerbill.org/article/2019/02/16/memory-allocation-strategies-004/).

## Performance notes

Both operations are a handful of instructions with no loop: allocate pops the head (read a pointer, write `head`), free pushes (write two pointers). O(1), no search, no locking, and — unlike the arena — this holds under **churn**: alloc/free/alloc/free in steady state runs forever at constant memory, recycling slots, with zero fragmentation because the blocks are interchangeable [[GB-MEM pt.4]](https://www.gingerbill.org/article/2019/02/16/memory-allocation-strategies-004/). The costs the pool pays: **internal fragmentation** (a 40-byte object in a 64-byte block wastes 24 bytes per block) and **inflexibility** (one size only; a request larger than a block can't be served). The comparison that matters for this module: the arena frees *nothing* individually but resets everything in O(1); the pool frees *everything* individually in O(1) but only ever hands out one size. Same eight-mode interface, opposite trade.

**Measurement task (tutor-run; numbers recorded in `curriculum/JOURNAL.md`):** once your pool is green, the tutor will benchmark an **alloc→free churn cycle** (repeatedly allocate a block and free it, and a mixed pattern that keeps many live at once) for **(a)** your pool vs **(b)** the default heap doing `new`/`free` of the same size — reporting ns per alloc, ns per free, and the cycle throughput. Expect the pool's alloc *and* free to land in the single-digit-ns range (the arena couldn't post a "free" number at all), and the heap to be several times slower per operation. The tutor records **Built + Measured** and walks you through it; you write **Takeaways + Reflections**.

## Exercise

Build the pool in a new kata package, `katas/pool/`, and drive it to green with `odin test katas/pool`.

**Interface is learner-designed — that's your first task.** Before any code, sketch the pool's public API in `design.md` (§Learner sketch); the tutor critiques and records the agreed interface, then tests are written. Decisions that are yours:

- The **`Pool` struct**: what state does it need? (Backing buffer, block size, the free-list `head` — anything else? A free/used count worth tracking?)
- **Initialization**: how does a caller set up a pool over a fixed backing buffer *and* choose the block size (and alignment)? What has to be true about block size for the free-list link to fit? How do you thread the initial free list?
- **Getting an `Allocator`** and the `Allocator_Proc` mode switch (same fixed signature as the arena).
- **`.Free`**: how do you push a block back — and do you trust the pointer, or sanity-check it belongs to this pool?
- **`.Resize` and oversize requests**: what does each return, given one fixed block size?
- **Alignment**: how block size and the buffer base interact so every block is aligned and holds the link.

Fixed constraints (not yours to change): the pool borrows a **caller-provided fixed backing buffer**; block size is fixed at init; alloc/free are O(1) via an **intrusive free list** (no side metadata); free list empty → `.Out_Of_Memory`; the procedure matches `Allocator_Proc` exactly.

### Definition of done

- `odin test katas/pool` green · per-test leak check reports 0 leaks · `-vet -strict-style` clean
- alloc/free/reuse, out-of-memory (exhausted pool), oversize-request, and free-all-rethread behavior all covered by the tutor's tests and passing
- Review passed (per review-rubric.md), including ≥2 comprehension probes answered
- Measurement task run by the tutor; **Built + Measured** recorded in `curriculum/JOURNAL.md`
- **Takeaways + Reflections** written by you, in your own words

## Reading list

- **Required:** [Memory Allocation Strategies pt.4 — Pool Allocators [GB-MEM pt.4]](https://www.gingerbill.org/article/2019/02/16/memory-allocation-strategies-004/) — the pool end to end, including the intrusive free-list construction this kata builds. Re-skim the [`Allocator_Proc`/`Allocator_Mode` entries [ODIN-MEM]](https://pkg.odin-lang.org/base/runtime/) if the modes are fuzzy.
- **Recommended:** [`core:mem` [ODIN-MEM]](https://pkg.odin-lang.org/core/mem/) — for reference *after* you've designed yours, look at how the standard library shapes a pool-like allocator; don't copy it before you sketch your own.
- **Deeper:** [GEA §6.2](https://www.gameenginebook.com/) — pool allocation as an engine support system, and the bridge to generational handle pools (m03).
