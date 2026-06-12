# Lesson: m00-01/odin-tour — The Odin tour, deltas from C++

> **Type:** concept · **Module:** m00 Odin for C++ programmers · **Interface:** not applicable (concept lesson — no exercise interface)

## Goals

- Map Odin's core semantics onto your C++ mental models — and know exactly where those models break.
- Explain, in your own words: `defer` vs RAII, ZII vs constructors, the implicit `context` vs singletons/TLS, slices vs `span`/pointer+length, parapoly vs templates, `or_return` vs exceptions.
- Recognize the data-oriented affordances built into the language (`distinct` types, `bit_set`, `#soa`) that this engine will lean on for the whole curriculum.
- Get a working Odin toolchain and record your first measurements.

## Prerequisites

None — this is the curriculum root.

## Explanation

Odin will feel like the C you wish C was, with the parts of C++ you actually use redesigned. The deep difference is cultural: C++ gives you machinery to build abstractions that hide costs (constructors, destructors, overloads, exceptions); Odin removes the hiding places. Almost everything below is in the official overview — this section orients, [the overview [ODIN]](https://odin-lang.org/docs/overview/) teaches.

### No classes, no ctors/dtors, no exceptions

There are structs, procedures, and explicit data. No inheritance, no member functions, no function overloading (there are explicit procedure groups instead), no constructors or destructors, no exceptions [[ODIN]](https://odin-lang.org/docs/overview/). Every C++ idiom you own that depends on "code runs implicitly when an object is created/destroyed/copied" needs a new home. The next three deltas are where those idioms go.

### ZII — zero is initialization

Every variable is zero-initialized unless you say otherwise [[ODIN §Zero values]](https://odin-lang.org/docs/overview/#zero-values). The idiom is to *design types so that the zero value is a valid, useful state* — an empty dynamic array is `{}`, an unbound handle is `0`. Where C++ culture says "establish invariants in the constructor," Odin culture says "choose invariants the zero value already satisfies."

> **C++ habit vs DOD approach:** the constructor habit makes you write `init()` functions for everything and fear uninitialized memory. Fight it: first ask "can zero just be valid?" A struct whose zero value works needs no init call, no `is_initialized` flag, and can live happily in a big zeroed array — which is exactly how data-oriented systems want to store things.

### `defer` vs RAII

Cleanup is explicit and local: `defer close(f)` runs at scope exit [[ODIN §`defer` statement]](https://odin-lang.org/docs/overview/#defer-statement). RAII attaches cleanup to a *type* (the destructor); `defer` attaches it to a *usage site*. You lose "impossible to forget"; you gain seeing the cleanup at the call site and paying for it only where it happens. In engine code most cleanup is bulk anyway (free the whole arena, not 10,000 destructor calls) — a theme m02 develops [[GB-MEM pt.1]](https://www.gingerbill.org/series/memory-allocation-strategies/).

### Slices and strings

A slice is a fat pointer — `{data, len}` — with no ownership semantics, and indexing is bounds-checked [[ODIN §Slices]](https://odin-lang.org/docs/overview/#slices). Closest C++ relative: `std::span`, except slices are *the* pervasive vocabulary type (strings are immutable byte slices). Who owns the memory a slice views is a question the type system deliberately does not answer — the allocator story (next) is the answer.

### The implicit `context`

Every procedure implicitly carries a `context` holding, among other things, the current allocator, a temporary allocator, and the logger [[ODIN]](https://odin-lang.org/docs/overview/). Calling code can swap the allocator for everything a callee allocates — without threading a parameter through forty signatures. In C++ this niche is served by global `new`, singletons, or TLS; in Odin it's scoped, explicit at the *override* site, and invisible everywhere else. This is the single most engine-relevant language feature you'll learn this module — all of m02 builds on it.

### Errors without exceptions

Procedures return multiple values; the error is just the last return value, and `or_return` propagates it early [[ODIN §`or_return` operator]](https://odin-lang.org/docs/overview/#or_return-operator). It's `std::expected` ergonomics with language support, and it's the whole story — there is no hidden unwind path through your frame loop.

### Parapoly, not templates

Parametric polymorphism uses explicit `$T` type parameters [[ODIN]](https://odin-lang.org/docs/overview/). Coming from C++ templates: no SFINAE, no overload-resolution metaprogramming, no header-only contagion — and correspondingly less compile-time wizardry. Generic code in Odin looks like the code it generates.

### Built for data layout

Three small features signal the language's data-oriented stance: `distinct` makes a named copy of a type that won't implicitly convert (`Texture_Handle :: distinct u32` — the foundation of m03's handle discipline) [[ODIN §Distinct types]](https://odin-lang.org/docs/overview/#distinct-types); `bit_set` is a typed bitmask over an enum [[ODIN §Bit sets]](https://odin-lang.org/docs/overview/#bit-sets); and `#soa` transparently turns an array-of-structs into a struct-of-arrays while keeping AoS-style syntax [[ODIN §SOA Data Types]](https://odin-lang.org/docs/overview/#soa-data-types).

> **C++ habit vs DOD approach:** in C++, SoA layouts mean hand-maintaining parallel vectors and the "object" disappears from the code. `#soa` keeps the object *view* while changing the *layout* — reach for it when iteration touches a few hot fields of many items (particles, transforms), not out of habit for every struct.

## In the industry

Shipping game studios already program in the discipline Odin enforces: Gregory's overview of engine support systems treats custom allocators and memory layout control as baseline engine infrastructure, not an optimization [[GEA §6.2]](https://www.gameenginebook.com/), and large studios commonly restrict C++ severely (exception-free, container replacements) for predictability [[GEA ch.3]](https://www.gameenginebook.com/). Odin is also not a toy in this domain: JangaFX's EmberGen, GeoGen, and LiquiGen are written fully in Odin, and through EmberGen it runs in production at studios including Bethesda, CAPCOM, Codemasters, THQ Nordic, Warner Bros, and Weta Digital [[ODIN]](https://odin-lang.org/).

## Performance notes

Language-level cost model to carry forward: zero-initialization is real work (memset) — usually negligible, measurable on hot paths; slice indexing is bounds-checked by default (removable per-block or per-build — we will measure that trade in the m02/m03 katas, not assume it); value semantics mean assignments copy, and big implicit copies are the classic newcomer cost [[ODIN]](https://odin-lang.org/docs/overview/). The deeper performance stance — allocation patterns dominate, so control them — is the next module's whole topic [[GB-MEM pt.1]](https://www.gingerbill.org/series/memory-allocation-strategies/).

**Measurement task (record the numbers in the journal):**
1. Install Odin; record `odin version` and the platform.
2. Write a hello-world; compile with `-o:none` and `-o:speed`. Record both compile times (`Measure-Command` in PowerShell) and both binary sizes.
3. Run `odin run` once and note time-to-first-output. These are your toolchain baseline numbers — m01 builds the real project skeleton on top of them.

## Exercise

Concept lesson — recall questions, answered in your own words (in chat; the tutor reviews against the sources). Expect follow-up probes.

1. What replaces RAII for cleanup in Odin, and name one thing you lose and one thing you gain relative to destructors.
2. What does ZII mean for how you *design* a struct? Give a concrete C++ constructor habit it replaces.
3. What travels in the implicit `context`, and which C++ patterns does it displace? Why is it scoped rather than global?
4. How does a slice differ from `std::span` in role, and what question does a slice deliberately not answer?
5. How does error propagation work without exceptions? What does `or_return` do mechanically?
6. Name two ways parapoly differs from C++ templates in practice.
7. What does `distinct` do, and why will it matter for handle-based package boundaries in this engine?
8. What does `#soa` change about memory layout, and for what kind of workload is that the right call?

### Definition of done

- Recall questions answered well (tutor-reviewed) · follow-up probes answered
- Measurement task numbers recorded in `curriculum/JOURNAL.md`
- Journal entry written (reflections in your own words)

## Reading list

- **Required:** [the Odin overview [ODIN]](https://odin-lang.org/docs/overview/), end to end; linger on [Zero values](https://odin-lang.org/docs/overview/#zero-values), [`defer`](https://odin-lang.org/docs/overview/#defer-statement), [Slices](https://odin-lang.org/docs/overview/#slices), [`or_return`](https://odin-lang.org/docs/overview/#or_return-operator), [Distinct types](https://odin-lang.org/docs/overview/#distinct-types), [Bit sets](https://odin-lang.org/docs/overview/#bit-sets), [SOA Data Types](https://odin-lang.org/docs/overview/#soa-data-types).
- **Recommended:** [Thinking About Memory and Allocation [GB-MEM pt.1]](https://www.gingerbill.org/series/memory-allocation-strategies/) — primes module m02.
- **Deeper:** [GEA ch.3](https://www.gameenginebook.com/) — software engineering fundamentals for games; [GEA §6.2](https://www.gameenginebook.com/) — the memory-management world you're heading into.
