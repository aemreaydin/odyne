# Lesson: m00-02/odin-kata — Odin warm-up katas

> **Type:** kata · **Module:** m00 Odin for C++ programmers · **Interface:** provided (rationale below)

## Goals

- Write your first real Odin: get the syntax for procedures, slices, and the `for` loop into your fingers.
- Use the idioms m00-01 only described — multiple return values, parapoly (`$T`), error enums + `or_return`, slices-as-views — to make failing tests pass.
- Feel, concretely, three C++ habits that don't carry over: the `(value, ok)` return instead of sentinels-or-exceptions, the slice as a borrowed view you mutate through, and the generic procedure that is just a procedure.
- Establish the kata workflow (`katas/<topic>/`, `odin test`, leak-checked tests) you'll reuse for every allocator and container kata in phase 0.

## Prerequisites

- m00-01 (the Odin tour) — this kata exercises exactly the deltas that lesson named.
- A working Odin toolchain (you installed it for m00-01's measurement task).

## Why the interface is provided

The constitution's default is that *you* design the interface and I critique it. This lesson is the one deliberate exception in the module: it is your first time writing Odin, and the learning budget belongs to **mechanics**, not API shape. So I hand you four signatures and you make them work. Interface *design* is a real skill, and you'll own it where it matters — the sprite-batch API in m23 and the RHI seam in m50 are learner-designed from a blank page. Here, the signatures are the scaffolding that lets you concentrate on how Odin actually feels to write. The exact signatures live in `design.md` under "Agreed interface"; this section explains what each one is teaching.

## Explanation

Four small procedures, one package, no allocators (memory is m02's whole topic — here every procedure works on memory the caller already owns). Each one is chosen to drill one idiom you read about but haven't yet typed.

### `find` — parapoly and the `(value, ok)` return

`find :: proc(xs: []$T, target: T) -> (index: int, found: bool)` searches a slice and reports whether it hit. Two deltas land at once.

First, **parapoly**. The `$T` makes this one procedure work for `[]int`, `[]u8`, `[]Foo` — the compiler stamps out a version per concrete `T` it's called with [[ODIN]](https://odin-lang.org/docs/overview/). Coming from C++ templates, the mental model is similar (monomorphization) but the surface is plain: no `template<typename T>` header, no separate declaration, no SFINAE — the generic procedure reads like the code it generates. The constraint that `target` is also `T` is expressed just by naming the type; the compiler checks the call sites.

Second, the **`(value, ok)` pair**. In C++ you'd reach for `std::find` returning an iterator you compare against `end()`, or a sentinel like `-1`, or `std::optional`. Odin's pervasive idiom is a second return value that *gates* the first [[ODIN §Multiple results]](https://odin-lang.org/docs/overview/#multiple-results). `index` is only meaningful when `found` is `true`. This matters because of the next point:

> **C++ habit vs DOD approach:** the sentinel reflex — "return -1 for not-found" — is a trap in this engine. Zero and negative indices are *valid* in plenty of contexts (and m03's handles make `0` a real, common value). A separate `ok` bool can't be silently used as an offset by mistake; a sentinel can. When you write the stub, resist returning a magic index — let `found` carry the answer.

### `reverse` — the slice is a view, and you mutate through it

`reverse :: proc(xs: []$T)` reverses in place and returns nothing; the caller sees the change. A slice is a fat pointer `{data, len}` with no ownership [[ODIN §Slices]](https://odin-lang.org/docs/overview/#slices) — passing it by value copies the *handle*, not the elements, so writes through `xs[i]` reach the caller's backing array. The closest C++ analogue is taking a `std::span<T>` (not a `const` one) by value: same "borrow that can write back."

Indexing is **bounds-checked by default**, at compile time for constant indices and at runtime otherwise [[ODIN §Fixed Arrays]](https://odin-lang.org/docs/overview/#fixed-arrays). For a warm-up that's a safety net; in m02/m03 we'll measure what turning it off per-block actually buys. The `for` loop is your iteration tool here — Odin's `for i in 0..<len(xs)` half-open range is the idiom [[ODIN §For Statement]](https://odin-lang.org/docs/overview/#for-statement).

> **C++ habit vs DOD approach:** don't reach for an allocation. The C++ instinct might be "build a reversed copy and return it." In place, with two indices walking inward, is the data-oriented default — it touches the memory the caller already has and allocates nothing. Allocation-free unless proven necessary is the posture for the whole engine [[GB-MEM pt.1]](https://www.gingerbill.org/series/memory-allocation-strategies/).

### `parse_u32` — errors are values, not control flow

`parse_u32 :: proc(s: string) -> (value: u32, err: Parse_Error)` parses a base-10 unsigned integer (no sign, no whitespace, no `0x` prefix) and returns an explicit error enum. There is no exception path: the error is just the last return value [[ODIN §Multiple results]](https://odin-lang.org/docs/overview/#multiple-results). A `string` in Odin is an immutable byte slice [[ODIN §Slices]](https://odin-lang.org/docs/overview/#slices), so you iterate its bytes (`s[i]` is a `u8`) and decide per byte. The `Parse_Error` enum distinguishes the failure modes — empty input, a non-digit byte, and arithmetic overflow — so the caller learns *why*, not just *that*, it failed.

Overflow is the interesting case and the reason this isn't trivial: accumulating `value = value*10 + digit` in a `u32` can wrap silently. Detecting it before it happens is part of the exercise — think about what bound a `u32` can hold before the next multiply-add escapes it.

### `sum_all` — `or_return` is the propagation, not a `try/catch`

`sum_all :: proc(parts: []string) -> (total: u64, err: Parse_Error)` parses each string in `parts` and sums them, **stopping at the first parse failure** and returning that error. This is what `or_return` is for: `v := parse_u32(p) or_return` evaluates the call, and if its last (error) value is non-zero, `sum_all` returns immediately, propagating that error up [[ODIN §or_return Operator]](https://odin-lang.org/docs/overview/#or_return-operator). It's the ergonomics of `std::expected` with `and_then` chains, but as a language operator with no hidden unwinding — the early return is visible right where it happens. Note the widening to `u64` for the running total: summing many `u32`s overflows a `u32`, and choosing the accumulator width is a deliberate call, not an accident.

> **C++ habit vs DOD approach:** there is no stack unwind, no destructor chain firing on the way out. `or_return` is a plain early `return` the compiler writes for you. In the frame loop you'll build later, that predictability — no hidden control flow threading through your hot path — is exactly why the engine avoids exceptions [[GEA ch.3]](https://www.gameenginebook.com/).

## In the industry

Exception-free, allocation-conscious C++ is the house style at large studios: shipping engines commonly compile with exceptions disabled and replace the parts of the standard library whose costs they can't see, precisely so control flow and memory stay predictable [[GEA ch.3]](https://www.gameenginebook.com/). The `(value, ok)` and error-as-value patterns you're drilling here are the Odin-native expression of that same discipline — the language gives you as a default what C++ shops bolt on by convention and code review. Small, focused, unit-testable procedures over caller-owned memory is also how engine utility code is structured before it's allowed near the frame loop; you're learning the unit of work, not just the syntax.

## Performance notes

The cost model to carry forward from these four:

- **Bounds checks** are real branches on every dynamic index [[ODIN §Fixed Arrays]](https://odin-lang.org/docs/overview/#fixed-arrays). Usually free (predicted, off the hot path); measurable in tight loops. We don't disable them here — we *measure* the baseline so later katas have something to compare against.
- **Parapoly is monomorphization**: each concrete `T` you instantiate `find`/`reverse` with is a separate generated procedure — codegen size, not runtime dispatch. No vtable, no indirection, unlike a C++ virtual call or `std::function`.
- **No allocations**: all four work on caller memory. Allocation count per call should be zero, and the leak-checked test runner will hold you to it.

**Measurement task (record the numbers in `curriculum/JOURNAL.md`):**
1. After the tests are green, run `odin test katas/odin_warmup` and record the wall-clock time and the leak-check summary line (allocations / frees / leaks).
2. Write a tiny benchmark loop (in a throwaway `main`, or a non-`@(test)` proc) that calls `find` ~1,000,000 times on a small `[]int`. Time it once compiled `-o:none` and once `-o:speed` (`Measure-Command` in PowerShell). Record both. This is your first "debug vs optimized" delta on real code — note the ratio.

## Exercise

- **Package:** `katas/odin_warmup/` (create it; this is the first kata, so the `katas/` tree starts here).
- **Stubs:** I provide `warmup.odin` with the four signatures from `design.md`, each body `unimplemented()`.
- **Tests:** I provide `warmup_test.odin` using `core:testing` (`@(test)` procs) — they will compile and **fail** before you implement.
- **Your job:** implement the four procedure bodies until `odin test katas/odin_warmup` is green and the leak check is clean. No allocations; no changing the signatures.

### Definition of done

- `odin test katas/odin_warmup` green · leak check clean (0 leaks)
- Measurement task numbers recorded in `curriculum/JOURNAL.md`
- Review passed (idiomatic-Odin + correctness rubric) · ≥2 comprehension probes answered
- Journal entry written (your own words)

## Reading list

- **Required:** the Odin overview sections you'll lean on directly — [Slices](https://odin-lang.org/docs/overview/#slices), [Multiple results](https://odin-lang.org/docs/overview/#multiple-results), [`or_return` Operator](https://odin-lang.org/docs/overview/#or_return-operator), [For Statement](https://odin-lang.org/docs/overview/#for-statement), and the parametric-polymorphism material in [the overview [ODIN]](https://odin-lang.org/docs/overview/).
- **Recommended:** skim [`core:testing`] usage by reading the `warmup_test.odin` I provide — that's your template for every later kata.
- **Deeper:** [GEA ch.3](https://www.gameenginebook.com/) — why engines disable exceptions and constrain C++; [GB-MEM pt.1](https://www.gingerbill.org/series/memory-allocation-strategies/) — the allocation-conscious mindset m02 makes concrete.
