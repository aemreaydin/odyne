# Lesson: m03-01/handles — Handles, not pointers

> **Type:** concept · **Module:** m03 Containers & handles · **Interface:** not applicable (concept lesson — no exercise interface; the m03-02 kata designs and implements the generational handle pool against this model)

## Goals

- Explain why engines refer to objects owned by another system through **handles** instead of pointers — what goes wrong with stored pointers, and what C++ smart pointers do and don't fix.
- Know the anatomy of a **generational handle** (index bits + generation bits), what the owning system stores per slot, and exactly how a stale handle is caught at lookup time.
- Compare the two classic storage layouts behind a handle table — **array-with-holes** and **packed-array + index-table** — and their lookup/delete/iteration trade-offs.
- Connect the discipline to odyne: `distinct` handle types, ZII (the zero handle is the invalid handle), and the layering law's handle-based package boundaries you'll live under from the platform layer on.

## Prerequisites

- m00-01 (ZII, `distinct` types, slices-don't-own) — the zero-value and type-safety ideas handles lean on.
- m02-02 / m02-03 (arena, pool) — you've already built slots + an intrusive freelist; the handle pool is that machinery plus a liveness check.
- m01-01 (layered skeleton) — the layering law this lesson turns into an API rule.

## Explanation

Module m02 answered "who owns the *memory*?" — group allocations by lifetime, free the group. This module answers the follow-up: "how does everyone *else* refer to the things living in that memory?" The C++ instinct says: by address. This lesson is about why shipping engines say: by **handle** — a small integer that names an object without pointing at it [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html).

### Why stored pointers rot

Suppose gameplay code keeps `target: ^Enemy` across frames. Three distinct things can go wrong with it:

1. **The object dies** — the enemy is destroyed; the pointer dangles; the next dereference is use-after-free (UB, and often *silently* wrong long before it crashes).
2. **The storage moves** — the system that owns enemies grows, compacts, or reloads its array; every outstanding pointer into it is invalidated, even though the *objects* are all still alive.
3. **The slot is reused** — the memory is recycled for a *different* live enemy. Nothing faults. Your turret just quietly shoots the wrong thing. (Your C++ ear should recognize the shape of the ABA problem here.)

The standard C++ toolbox only partially helps. A raw pointer or reference fixes nothing. `shared_ptr` "fixes" (1) by mutating the design: the moment consumers co-own the object, the enemy system no longer decides when enemies die — lifetime authority leaks outward, plus you pay a heap-allocated control block and atomic reference counts per object. `weak_ptr` is the honest one — `lock()` answers "is it still there?" — but it exists only on top of `shared_ptr`'s ownership model and its costs, and neither survives (2): smart pointers pin an object to the address where it was allocated, so the owning system can never relocate its storage.

The handle answer inverts the whole arrangement [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html): move memory management into the systems themselves; each system owns a private array of its same-type items; everything public deals in **index-handles**; the base pointers never leave the system. When you genuinely need a pointer, you convert the handle at the moment of use — and the conversion *checks liveness first*. Failure modes (1) and (3) become detected conditions instead of UB, and (2) disappears entirely: the system can reallocate or reorganize its array freely because nobody outside holds an address into it [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html).

### Anatomy of a generational handle

A handle packs two integers [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html):

- **index bits** — which slot in the owning system's array; and
- **generation bits** (floooh: "unique pattern", Bitsquid: "inner id") — *which lifetime* of that slot you mean.

Each slot keeps its own generation counter, bumped when the slot's item is freed [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html). Lookup: split the handle; compare its generation against the slot's current generation; on mismatch the handle is **stale** — return invalid instead of a pointer. A freed-and-reused slot has a newer generation than any old handle to it, so scenario (3) — the silent wrong-object bug, the one that's nearly undebuggable with pointers — is caught deterministically at every single access. The check has an arithmetic honesty clause: with k generation bits, the counter wraps after 2^k reuses of one slot, so bit-budgeting is a real design decision — even a 16-bit handle can split into 10 index bits (1024 live items) and 6 generation bits, and the split is yours to choose [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html).

Two conventions complete the picture for odyne. First, **the zero handle is the invalid handle** — then ZII from m00-01 does the rest: a zero-initialized struct containing a handle already means "refers to nothing", no `nullptr`, no sentinel invention. Second, handles are **opaque**: callers never do arithmetic on them or peek at the bits — Bitsquid's definition is exactly "an opaque data structure of n bits" [[BITSQUID]](https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html).

### The storage underneath: holes or packed

The handle table needs a policy for where objects actually live. The Bitsquid article walks the three classic designs and measures them [[BITSQUID]](https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html):

- **`std::map<id, object>`** — the baseline: simple, and slow (heap nodes, tree traversal). Their tests put the array designs ~40× faster.
- **Array with holes** — objects sit at fixed slots; a freelist is threaded *through the holes themselves* (exactly the intrusive-freelist trick you built in the m02-03 pool); ids carry index + inner_id. Lookup is direct; objects never move; iteration must skip dead slots.
- **Packed array + index table** — one extra level: a sparse index array maps id → position in a *dense* object array; deleting swaps the last object into the gap and fixes up its index entry. Objects move (only the system cares — nobody else holds addresses!), lookup pays one more indirection, and iteration becomes a linear walk over purely live, contiguous objects.

The trade is lookup-cost vs iteration-density: holes win when you mostly resolve individual handles and want stable storage; packed wins when you iterate the whole collection hot every frame. Keep both shapes in your head — in m03-02's design conversation *you* will pick one for the kata and defend the choice.

> **C++ habit vs DOD approach:** the OOP instinct builds an object *graph* — `Player` holds `Weapon*`, `Weapon` holds an owner back-pointer, smart pointers arbitrate lifetimes pairwise, and identity *is* the address. The data-oriented approach builds object *tables* — each system owns a dense array of same-type items [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html), identity is a small stable integer, and the address is a private, transient detail. Notice what falling out of love with addresses buys you: an integer survives a save file, a network packet, and a debugger dump; an address survives none of them. When you catch yourself designing `^T` members between systems, stop and ask what the table is.

### The borrowing rule

The pointer you get from resolving a handle is a **loan**: convert, use it right here, let it go — don't store it, don't pass it onward for keeping [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html). Store the handle; re-resolve at next use. Every re-resolve re-checks liveness, and the rule is precisely what frees the owning system to compact, grow, or hot-reload its storage between frames. This is `weak_ptr::lock()`'s discipline — check, use, drop — minus the control block, the atomics, and the shared-ownership model underneath, for the price of an array index and an integer compare.

### Type safety: `distinct` handles

If handles are just integers, what stops `texture_destroy(entity_handle)`? In C++: nothing, until you hand-roll a strong-typedef wrapper class per handle type. Odin ships the fix as a keyword [[ODIN §Distinct types]](https://odin-lang.org/docs/overview/#distinct-types):

```odin
Texture_Handle :: distinct u32
Entity_Handle  :: distinct u32
// same representation, same semantics — but the compiler
// rejects passing one where the other is expected
```

`distinct` creates a new type with identical underlying semantics that the type system refuses to conflate [[ODIN §Distinct types]](https://odin-lang.org/docs/overview/#distinct-types). Every handle type odyne exposes across a package boundary will be `distinct` — wrong-system handles become compile errors, not runtime mysteries.

## In the industry

This is not a niche trick — it's the reference discipline of shipping engines. Gregory devotes a section to exactly this choice — pointers vs smart pointers vs handles vs unique object ids for referencing game objects, and the queries that resolve them [[GEA §16.5]](https://www.gameenginebook.com/) — and on the asset side, resources are addressed by GUID and mediated by the resource manager rather than passed around as raw pointers, so assets can be loaded, unloaded, and moved at will [[GEA §7.2]](https://www.gameenginebook.com/). The Bitsquid engine (later Autodesk Stingray) documented its production ID lookup table in the article you're reading this week [[BITSQUID]](https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html).

The API you'll spend phase 2 inside made the same call: "At the API level, all objects are referred to by handles" — Vulkan's dispatchable handles are opaque pointers, its non-dispatchable handles are 64-bit integers [[VKSPEC §Fundamentals — Object Model]](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html#fundamentals-objectmodel). That's why odyne's layering law demands handle-based cross-package APIs: the render package will wrap Vulkan's handles in *engine* handles, so no `vk*` type ever leaks upward — which is precisely the seam that lets a DX12 backend slide in behind the same API in phase 5.

In the Odin ecosystem, Karl Zylinski's handle-map write-ups and library translate floooh's design into idiomatic Odin — index + generation handles over three storage variants (fixed static array, growing virtual-memory arena, and a pointer-stable growing variant) [[ZYL-HANDLES]](https://zylinski.se/posts/handle-based-arrays/). And the endgame of the idea is ECS, where the entity itself is "generally represented as a unique integer value" [[ECS-FAQ]](https://github.com/SanderMertens/ecs-faq) — an id with *no* object behind it at all; that story is m42's.

## Performance notes

The cost model to carry forward:

- **Reference size:** a handle is 4 bytes (often less) against a 64-bit pointer — references-to-things get smaller and denser, and unlike a pointer, a handle is *checkable*.
- **Resolve cost:** one array index + one integer compare + a predictable branch, plus one extra indirection in the packed design [[BITSQUID]](https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html). That's the toll booth at a system boundary — nanoseconds, paid only when crossing.
- **The structural win:** same-type items grouped in arrays means whole-collection work is a linear walk over contiguous memory — full cache lines of useful data [[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html) — where an object graph turns every hop into a potential cache miss. Container choice alone was worth ~40× in Bitsquid's map-vs-array measurements [[BITSQUID]](https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html).

**Measurement task (tutor-run; numbers recorded in `curriculum/JOURNAL.md`):** the tutor will write and run a benchmark (`katas/handles_bench/`) that builds N small objects and times, per element: **(a)** iterating the dense array directly — the owning system's private view; **(b)** resolving every element through a handle table (slot → generation check → object) — the boundary-crossing toll; **(c)** chasing pointers to individually heap-allocated objects visited in shuffled order — the C++-habit object graph after some allocation churn; **(d)** looking each object up in an Odin `map` by id — Bitsquid's "STL method" analog. Reported as ns/element and ratios; the tutor records **Built + Measured** and walks you through the numbers; you write **Takeaways + Reflections**. These are the baseline numbers m03-02's handle pool must live up to.

## Exercise

Concept lesson — recall questions, answered in your own words (in chat; the tutor reviews against the sources and asks ≥2 follow-up probes). No code this lesson; m03-02 is where you design and build the generational handle pool, and m03-03 graduates it into `engine:core`.

1. You're tempted to store `target: ^Enemy` inside a turret so it can shoot next frame. Name the three distinct ways that pointer can go bad, and say which of them `shared_ptr`/`weak_ptr` actually fix — and what each "fix" costs or changes about ownership.
  An object can be deleted and the past references would be invalidated, the storage might be moved somewhere else or the object might be replaced by another object before the next frame.
  `shared_ptr` fixes this by reference counting, however this adds overhead. `weak_ptr` uses `lock()` to check if the object is still valid but doesn't fix the storage moved issue.

2. From memory, roughly: what two things are packed into a generational handle, what does the owning system store per slot, and what are the exact steps of a lookup that ends in "stale"?
  We store an index and a generation to keep track of the objects index and generation to check whether they are stale or not. If the generation is not the same it's stale.
3. Slot reuse: handle H referred to an object in slot 7; that object died and slot 7 now holds a fresh one. Walk through why resolving H fails rather than silently returning the new object — and state the arithmetic limit of the generation check.
  When a new object created, the generation is increased - so when the generation is different the resolving fails. The arithmetic limit for the generation is basically so that the generation doesn't wrap back to 0 and invalidate valid objects.
4. Contrast Bitsquid's array-with-holes and packed-array + index-table designs: what does each cost on lookup, on delete, and on iterating all live objects? Name one collection where you'd pick each, and why.
  array-with-holes: lookup and delete is O(1), however iterating is a bit problematic because there will be holes in the array when the objects are deleted and not used.
  packed-array + index-table: There is an extra array lookup - however the objects are now packed and the iterating is trivial and cache-friendly.
5. State the borrowing rule for the pointer a resolve gives you, and explain what the owning system becomes free to do *because* everyone follows it.
  If everyone follows the borrowing rule - so re-resolve each time they use it, it gives the system flexible to compact/grow the array or hot-reload the engine.
6. `weak_ptr` also answers "is it still alive?" — give two concrete reasons engines reach for generational handles instead.
  weak_ptr has extra overload to check availability and when the storage moves, weak_ptr will be invalidated.
7. What does `distinct` add over a bare `u32` handle, and how does ZII plus "zero handle = invalid" give you null-safety without nullable pointers? Sketch what each would cost you to replicate in C++.
  distinct gives you the ability to create "distinct" types based on already existing types and you can't pass the existing type for the "distinct type" - the ZII ensures that during object creation and zero handle
  automatically gives you an "invalid" handle. In C++ you'd need a `typedef-wrapper` to do it.
8. odyne's layering law requires handle-based cross-package APIs. Using the render layer as the example — Vulkan objects being themselves handles — what does that seam buy us when DX12 arrives in phase 5?
  No `vk` or `dx` handles are exposed outside of the rendering system - just the handles. This enables easy switching between rendering systems.

### Definition of done

- Recall questions answered well (tutor-reviewed) · ≥2 follow-up probes answered
- Measurement task run by the tutor; **Built + Measured** recorded in `curriculum/JOURNAL.md`
- Journal entry completed — **Takeaways + Reflections** in your own words

## Reading list

- **Required:** [Handles are the better pointers [FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html) — the manifesto, whole article; [Managing Decoupling Part 4 — The ID Lookup Table [BITSQUID]](https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html) — the three storage designs, whole post.
- **Recommended:** ["Handles are the better pointers": An Odin gamedev follow-up [ZYL-HANDLES]](https://zylinski.se/posts/handle-based-arrays/) — the same ideas in Odin; read before the m03-02 kata; [GEA §16.5](https://www.gameenginebook.com/) — object references and world queries, the industry survey.
- **Deeper:** [GEA §7.2](https://www.gameenginebook.com/) — the resource manager, handles on the asset side; [Vulkan object model [VKSPEC]](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html#fundamentals-objectmodel) — the handle-based API you'll meet in phase 2; [ECS FAQ [ECS-FAQ]](https://github.com/SanderMertens/ecs-faq) — where entity ids take this in m42.
