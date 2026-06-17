# Lesson: m02-01/allocators — Odin's allocator model

> **Type:** concept · **Module:** m02 Memory & allocators · **Interface:** not applicable (concept lesson — no exercise interface; the katas m02-02/m02-03 implement against this model)

## Goals

- Explain _why_ allocation is a runtime policy in Odin, not a hardcoded call to a global heap — and what that buys an engine.
- Read the concrete allocator interface: `Allocator{procedure, data}`, the eight-mode `Allocator_Proc`, and `Allocator_Error` — and recognize it as a type-erased object you'll implement twice this module.
- Trace how `context.allocator` and `context.temp_allocator` thread through every allocating call (`new`, `make`, `append`, maps) and how a scope override propagates to callees without touching a single signature.
- Map all of it onto your C++ mental models (`std::pmr`, global `new` override, manual allocator parameters) and know exactly where those models break.

## Prerequisites

- m00-01 (the implicit `context`, ZII, slices-don't-own) — this lesson is the allocator half of the `context` story that lesson opened.
- m01-01 (the layered package skeleton) — `core:mem` lives at the bottom layer everything else allocates through.

## Explanation

In C++ the _act_ of allocating and the _policy_ of where memory comes from are welded together at the call site: `new T` means "the global heap, right now." To change the policy you reach for blunt instruments — override global `operator new` (process-wide, one hook), pass allocator template parameters that infect every type (`std::vector<T, MyAlloc>`), or adopt `std::pmr` and thread a `memory_resource*` through your APIs. Odin unwelds the two. _Allocating_ is a call like `new(T)`; _policy_ is a value — an `Allocator` — that the call reads out of the ambient `context`. Change the value, and everything allocated downstream changes where it comes from. This is the single most important idea in the whole memory module [[GB-MEM pt.1]](https://www.gingerbill.org/article/2019/02/01/memory-allocation-strategies-001/).

### The allocator is a value, not a type

The interface is deliberately tiny [[ODIN-MEM runtime.Allocator]](https://pkg.odin-lang.org/base/runtime/):

```odin
Allocator :: struct {
    procedure: Allocator_Proc,
    data:      rawptr,
}
```

A function pointer and a `rawptr` of state — sixteen bytes, passed by value, no inheritance. That's the entire abstraction. Every allocator (the heap, an arena, a pool) is the same struct; only `procedure` and the `data` it operates on differ. One procedure handles _all_ operations, dispatched by a `mode` argument [[ODIN-MEM runtime.Allocator]](https://pkg.odin-lang.org/base/runtime/):

```odin
Allocator_Proc :: proc(allocator_data: rawptr, mode: Allocator_Mode,
                       size, alignment: int, old_memory: rawptr, old_size: int,
                       location := #caller_location) -> ([]byte, Allocator_Error)

Allocator_Mode :: enum u8 {
    Alloc, Free, Free_All, Resize,
    Query_Features, Query_Info,
    Alloc_Non_Zeroed, Resize_Non_Zeroed,
}
```

So implementing an allocator means writing one `switch mode` procedure — which is exactly what you'll do for the arena (m02-02) and the pool (m02-03). Note `Alloc` vs `Alloc_Non_Zeroed`: the default path zeroes memory, which is what makes m00-01's ZII hold for heap-allocated data — a freshly allocated struct is already in its valid zero state. And there is no exception path: out-of-memory is a returned `Allocator_Error` value [[ODIN-MEM runtime.Allocator]](https://pkg.odin-lang.org/base/runtime/), the same errors-as-values discipline as `or_return`.

> **C++ delta:** the closest analogue is `std::pmr::memory_resource` — a polymorphic allocator behind a virtual interface. The differences that matter: Odin's allocator is a _value type_ (no vtable, no base class, no heap-allocated resource object), it's _one_ procedure switching on a mode rather than several virtual methods, and — the big one — it's carried _implicitly_, so containers don't need to be a different type (`pmr::vector` vs `vector`) to use it. An Odin dynamic array is always just `[dynamic]T`; which allocator backs it is a runtime fact, not part of its type.

### The context carries the policy

Every Odin procedure implicitly receives a `context`, and the context holds two allocators: `context.allocator` (the general-purpose one) and `context.temp_allocator` (per-thread scratch) [[ODIN §Implicit context system]](https://odin-lang.org/docs/overview/#implicit-context-system). The built-in allocating operations — `new`, `free`, `make`, `delete`, `append`, dynamic arrays, maps — all route through `context.allocator` by default. So this:

```odin
p := new(Player)          // uses context.allocator
xs := make([]int, 100)    // uses context.allocator
```

…and to change _where all of that comes from_, you assign the context once and it propagates to every callee, transitively, with zero signature changes:

```odin
context.allocator = my_arena_allocator
load_level()              // everything load_level and its callees allocate now lands in the arena
```

This is the `context` mechanism from m00-01 doing the job it was built for. Crucially each allocating builtin _also_ takes an explicit `allocator` parameter that defaults to the context one (`new(Player, my_alloc)`, `make([]int, 100, my_alloc)`) — so you choose per call site when you want to be explicit, or per scope when you want it ambient.

> **C++ habit vs DOD approach:** the C++ instinct is per-object lifetime — every `new` pairs with a `delete` (or a smart pointer that hides the `delete`), each object freed individually. The data-oriented approach groups allocations _by lifetime_ and frees the whole group at once: all of this level's memory, all of this frame's scratch. Odin makes the dominant case the path of least resistance — see `temp_allocator` next. Fight the urge to give every allocation its own matching free; first ask "what's the lifetime group, and who frees the group?"

### `temp_allocator`: the arena you already have

`context.temp_allocator` is a per-thread scratch arena that's always available. You allocate from it freely during a frame (or any bounded scope) and reclaim _everything at once_ with `free_all(context.temp_allocator)` — no individual frees [[ODIN §Implicit context system]](https://odin-lang.org/docs/overview/#implicit-context-system). `fmt.tprintf` (the `t` is "temp") and the `make([]T, n, context.temp_allocator)` idiom build on it; you used `tprintf` in m01-01 without knowing it was riding a scratch arena. This is the arena allocation pattern (m02-02's kata) promoted to an ambient, language-blessed default — and it has no built-in C++ equivalent; you'd hand-roll a frame arena and remember to pass it everywhere.

### Ownership lives in your head, not the type

A slice or pointer does _not_ record which allocator produced it — that's the question m00-01 said slices "deliberately don't answer." The rule is: whoever allocated with allocator _A_ frees with allocator _A_ (or relies on _A_'s `Free_All`/destruction to reclaim it in bulk). Memory from the temp allocator must not outlive the next `free_all`; memory from an arena dies when the arena is reset. Tracking that discipline is the programmer's job — and the m02 katas are where you build the muscle. (The `core:mem` tracking allocator, which wraps another allocator to flag leaks and double-frees, is how the test harness checks you got it right — that's the leak-check you've seen pass in earlier lessons.) [[ODIN-MEM runtime.Allocator]](https://pkg.odin-lang.org/core/mem/)

## In the industry

Custom allocators are not an optimization in shipping engines — they're baseline infrastructure. Gregory treats engine-specific memory management (stack/arena allocators, pool allocators, per-frame scratch) as a core support system that almost every engine builds, precisely because the general-purpose heap is too slow, too unpredictable, and too prone to fragmentation for a frame-time budget [[GEA §6.2]](https://www.gameenginebook.com/). Engines route allocation through their own allocators so they can budget and track memory per subsystem, eliminate fragmentation, control cache layout, and avoid the OS heap's locking on hot paths [[GEA §6.2]](https://www.gameenginebook.com/). Odin's design is a direct response to that reality: the allocator interface and the whole allocator-aware standard library exist so an engine can swap allocation policy wholesale — exactly the lever C++ engines build by hand with `pmr`, custom containers, and bespoke arena classes [[GB-MEM pt.1]](https://www.gingerbill.org/article/2019/02/01/memory-allocation-strategies-001/).

## Performance notes

The cost model to carry forward: a general-purpose heap allocation (`malloc`/default `context.allocator`) typically costs tens to hundreds of nanoseconds, must be thread-safe (locking or per-thread caches), can fragment over time, and gives back memory one object at a time. An arena bump-allocation is a pointer add plus a bounds check — single-digit nanoseconds — and frees the entire region with one pointer reset, no per-object work [[GB-MEM pt.1]](https://www.gingerbill.org/article/2019/02/01/memory-allocation-strategies-001/). The trade is generality for speed and predictability: the arena can't free individual objects, which is exactly why you match allocator to lifetime. There's also a small, fixed cost the interface itself imposes — every allocation is an _indirect_ call through `Allocator.procedure` — which is negligible against the allocation work but real, and worth seeing measured at least once.

**Measurement task (tutor-run; numbers recorded in `curriculum/JOURNAL.md`):** the tutor will write and run a small Odin benchmark that, for a fixed count of small allocations, times (a) the default heap `context.allocator` and (b) `context.temp_allocator` (arena) — reporting ns/alloc and the ratio — and separately estimates the indirect-call overhead of going through the allocator procedure. The tutor records the **Built + Measured** facts and walks you through what they mean; you write the **Takeaways + Reflections**. These become m02's baseline numbers that the arena and pool katas build on.

## Exercise

Concept lesson — recall questions, answered in your own words (in chat; the tutor reviews against the sources and asks follow-up probes). No code this lesson; m02-02 and m02-03 are where you implement allocators against this model.

1. In one or two sentences, what does Odin "unweld" that C++ welds together at a `new` call site, and why does that matter for an engine?
   Allocating and the policy of where the memory is in C++ lives in the allocation keywords. Odin separates this - allocation is a call - policy is a definition of `Allocator`
2. Write out (from memory, roughly) the two fields of the `Allocator` struct and explain why one procedure with a `mode` argument is used instead of several separate procedures.
   raw_ptr data and prodecure which is the Allocator_Proc - mode gives the ability to Alloc/Free/Free_all etc. options for the user.
3. What is the difference between `context.allocator` and `context.temp_allocator`, and what is the lifetime rule for memory you get from the temp allocator?
   ONe is the global allocator, the other is the thread-scoped (block scoped) allocator - where you free_all at the same time. It is used for short-lived objects.
4. You set `context.allocator = arena` at the top of `load_level()`. Which allocations are affected, and how far does that override reach? Contrast with C++'s global `operator new` override.
   Anything inside the scope of the context definition is affected. Leaving the scope reverts the context to default. if you globally override new - its the same everywhere until you override again.
5. How does Odin's allocator model compare to C++ `std::pmr` — name two concrete differences.
   It's a runtime polymorphism so uses vtables/heap allocations - odin has basically a procedure that can be switched easily.
6. A slice doesn't know which allocator created it. State the ownership rule that fills that gap, and give one way the temp allocator's rule can bite you.
   The slice doesn't really own anything - its just a pointer and a size. The allocator creates the slice - based on the allocation - it might be short-lived or it might live longer. If we use a temp-allocator to create it and try to access it after
   free there will be free errors.
7. Why does the default `Alloc` mode zero memory, and how does that connect to ZII from m00-01? When would you reach for `Alloc_Non_Zeroed`?
   The default Alloc zeroes memory as per the ZII principle. I think we'd use Alloc_Non_Zeroes for objects where we know the size of. Maybe creating an object pool with set amount of telements?
8. From the industry/performance view: give one reason shipping engines route allocation through custom allocators rather than the OS heap, and the rough cost gap between a heap alloc and an arena bump.
   OS heap is slow - if we use malloc/new for everything - we have to make system calls for each allocation. Also, there will be fragmentation when we constantly make allocations. Arena allocation
   is basically one allocation and then pointer incrementing and the free_all.

### Definition of done

- Recall questions answered well (tutor-reviewed) · ≥2 follow-up probes answered
- Measurement task run by the tutor; **Built + Measured** recorded in `curriculum/JOURNAL.md`
- Journal entry completed — **Takeaways + Reflections** in your own words

## Reading list

- **Required:** [the Odin overview — Implicit context system [ODIN]](https://odin-lang.org/docs/overview/#implicit-context-system); [the `base:runtime` allocator interface [ODIN-MEM]](https://pkg.odin-lang.org/base/runtime/) — read the `Allocator`, `Allocator_Proc`, `Allocator_Mode`, `Allocator_Error` entries.
- **Recommended:** [Thinking About Memory and Allocation [GB-MEM pt.1]](https://www.gingerbill.org/article/2019/02/01/memory-allocation-strategies-001/) — the conceptual frame; skim [`core:mem` [ODIN-MEM]](https://pkg.odin-lang.org/core/mem/) for the helpers (`mem.alloc`, the tracking allocator) you'll meet in the katas.
- **Deeper:** [GEA §6.2](https://www.gameenginebook.com/) — engine memory management as a support system; sets up why m02 exists.
