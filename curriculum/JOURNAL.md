# Learning journal

One entry per completed lesson, newest first. The learner writes the reflections —
in their own words; that's part of the learning. Measured numbers come from the
lesson's measurement task.

## Entry format

```
## YYYY-MM-DD — <lesson id>: <title>
- **Built:** <what now exists>
- **Measured:** <numbers from the measurement task>
- **Takeaways:** <review findings + probe answers worth keeping>
- **Reflections:** <learner's own words: what was hard, what clicked, open questions>
```

---

## 2026-07-19 — lesson-m03-01: handles (concept)

- **Built:** No engine code (concept lesson). Lesson covers the referencing discipline
  module m03 builds on: why stored cross-system pointers rot (object death / storage
  relocation / slot reuse), the generational handle (index bits + generation bits,
  per-slot counter bumped on free, stale = generation mismatch at resolve), Bitsquid's
  storage designs (map baseline · array-with-holes + intrusive freelist · packed array +
  index table with swap-with-last), the borrowing rule (resolve → use locally → drop,
  store only the handle), and `distinct` + ZII (zero handle = invalid) for type-safe,
  null-safe handles. Registered cite-keys FLOOOH, BITSQUID, ZYL-HANDLES; GEA bibliography
  entry switched to the learner's 3rd edition (object references = §16.5 in 3e, was
  mis-cited as 4e §17.5). Sets up m03-02 (generational handle pool kata) and m03-03
  (graduate into `engine:core`). Bench harness: `katas/handles_bench/main.odin`.
- **Measured:** (tutor-run · `odin run -o:speed` · odin dev-2026-07-nightly:819fdc7 ·
  N=100,000 × 32 B entities, 50 passes, sums-equal check on all paths · avg of 3)
  - **(a) dense iteration ≈ 0.23 ns/visit** — the owning system's private hot loop.
  - **(b) handle resolve, storage order ≈ 0.41 ns/visit (~1.9× a)** — slot load + generation
    compare + double indirection adds only **~0.2 ns** when access is sequential: the
    liveness check is essentially free.
  - **(c) handle resolve, shuffled ≈ 1.61 ns/visit (~7× a)** — same resolve, random visit
    order → ~4× case (b). **Locality, not the generation check, is the real cost.**
  - **(d) pointer chase, shuffled ≈ 0.85–1.70 ns/visit (noisiest; ~4–7× a)** — ≈ (c):
    under identical access patterns, handle indirection costs nothing measurable over raw
    pointers. Caveat: a fresh heap placed 100k same-size allocs compactly; a churned,
    long-lived heap scatters them — and these visits are independent loads the CPU can
    overlap, where a real object *graph* chains dependent hops.
  - **(e) map lookup, shuffled ≈ 6.11 ns/visit (~24–30× a, ~4× the array designs)** —
    Bitsquid's "STL method is the slow one" verdict reproduced 15 years later against
    Odin's modern open-addressing map.
  - Working set ~8 MB total (L2/L3-resident); absolute ns are flattered by cache residency
    and memory-level parallelism — carry the **ratios**, not the ns.
- **Takeaways:** <!-- [you] review findings + probe answers worth keeping -->
  The Handle system was super foreign a couple years ago, now understanding it and it makes perfect sense.
  The packed-array system is perfect for hot-loops and array-with-holes is great for resource management.
- **Reflections:** <!-- [you] your own words: what was hard, what clicked, open questions -->
  Still hard to visualize what I need when I need them - will take some time to get used to these
  concepts.

## 2026-07-18 — lesson-m02-04: core-memory (graduate)

- **Built:** `engine/core/memory/` (`package memory`) — the arena (m02-02) and pool (m02-03)
  graduated out of `katas/` into the engine's core layer, prefixed for coexistence
  (`memory.arena_init`, `memory.pool_init`, …), bodies unchanged. Package named `memory`, not
  `mem`, to dodge a hard Odin constraint (a `package mem` can't import `core:mem` —
  `Duplicate declaration of 'package mem'`; alias doesn't fix it). Folded in a bonus
  `Logging_Allocator` — a wrapping `Allocator_Proc` that forwards to any backing allocator and
  prints each op (mode/size/align/caller/result), aligned via the `tprintf → %-Ns` idiom
  (Odin zero-pads integer widths; only strings space-pad). First lesson to merge an engine
  spec delta: `openspec/specs/core-memory` (arena, pool, logging, allocator conformance,
  layering). Demo: testbed allocates through a core arena + pool and runs correctly. 10
  `core:testing` conformance tests, green · leak-clean · `-vet -strict-style` clean.
- **Measured:** (tutor-run)
  - `odin test engine/core/memory`: 10 tests, ~4–9 ms · leak-clean · vet/style clean.
  - Testbed clean build (`-o:speed`): ~1.8–2.4 s · binary **464,384 B** vs m01-01's empty-engine
    baseline **417,792 B** → **+~46 KB (~11%)** — the first real code (allocators + `core:mem` +
    `core:fmt` for logging) landing in `core`. m01-01's "zero point" starts to move.
  - No perf regression: the arena/pool bodies are byte-for-byte the kata code, so m02-02's
    ~15 ns/alloc and m02-03's ~11.5/4.5 ns alloc/free hold unchanged in-engine.
- **Takeaways:** <!-- [you] review findings + probe answers worth keeping -->
  The package creation - library abstraction logic is different than C++ - more similar to C.\
  One package that stores the memory code is the way I decided to go. I think in the future - or for 
  bigger packages - this might be hard to maintain.
- **Reflections:** <!-- [you] your own words: what was hard, what clicked, open questions -->
  Not a complex milestone - just moved code around. Logging allocator was a nice addition
## 2026-07-17 — lesson-m02-03: pool

- **Built:** `katas/pool/` — the pool (fixed-size block) allocator implementing Odin's
  `Allocator_Proc`. `Pool{data (borrowed backing), block_size (effective stride), alignment,
  head: ^Free_Node, free_count}`. Free blocks are tracked by an **intrusive singly-linked
  free list** — the `next` link is overlaid on each free block's own bytes (no side metadata).
  Public: `init`, `allocator`, `allocator_proc`, `free_all`; public helpers `alloc`/`free_block`.
  init aligns the backing base once (re-slice off the padding), bumps block size to
  `align_forward_int(max(requested, size_of(rawptr)), alignment)`, and threads the list;
  alloc pops the head (returns exactly `size` bytes, zeroes on `.Alloc`), free pushes back —
  both O(1). Two distinct errors: `size > block_size` → `.Invalid_Argument`, empty pool →
  `.Out_Of_Memory`; over-alignment rejected; `.Resize` → `.Mode_Not_Implemented`;
  `.Query_Features` includes `.Free`. Range + block-alignment asserts on free. 19
  `core:testing` tests, all green · leak-clean · `-vet -strict-style` clean.
- **Measured:** (tutor-run · `odin run -o:speed` · N=100,000 × 32 B blocks, align 8 · avg of 3)
  - **pool alloc ≈ 11.5 ns/op**, **pool free ≈ 4.5 ns/op** (free is cheaper — just a push +
    counter; alloc also zeroes 32 B and runs the size/alignment checks).
  - **pool alloc+free churn ≈ 15 ns/cycle** vs **heap new/free ≈ 38 ns/cycle → ~2.5× faster**.
  - The headline vs the arena: the pool posts a **free** number at all (~4.5 ns, O(1) per
    object) and sustains alloc/free churn at constant memory — the arena had no individual
    free, only O(1) bulk reset. Pool trades the arena's variable-size freedom for individual
    recycling of one fixed size.
  - Like the arena, the ~2.5× alloc-side gap is modest: Windows' heap is decent for small
    fixed churn, and the pool's per-op cost is mostly interface indirection + mode switch +
    zeroing, not the pointer pop/push itself.
  - Bench harness: `katas/pool_bench/main.odin`.
- **Takeaways:** <!-- [you] review findings + probe answers worth keeping -->
  Pool allocator is fixed-sized allocators usually used for same sized elemetns in game programming

- **Reflections:** <!-- [you] your own words: what was hard, what clicked, open questions -->
  I find it hard to wrap my head around the alignment logic usually, in time it will be easier hopefully
  Understanding memory management conceptually is nice, makes me confident as a developer to learn
  more about low level subjects.

## 2026-07-15 — lesson-m02-02: arena

- **Built:** `katas/arena/` — the arena (bump) allocator implementing Odin's
  `Allocator_Proc`. `Arena{data (borrowed backing), offset, prev_offset, peak_used}`.
  Public surface: `init`, `allocator`, `allocator_proc`, `free_all`; file-private
  helpers `alloc`/`resize`/`align_forward`/`safe_add`. Aligns the **absolute address**
  (`raw_data(data)+offset`), so a misaligned backing still returns aligned pointers;
  `Resize` fast-paths the most-recent allocation via `prev_offset` (grow/shrink in
  place, zeroing only the grown tail), else alloc-new + copy; `Free` →
  `.Mode_Not_Implemented`; `Query_Features` reports the supported mode set. 19
  `core:testing` tests (alloc/zeroing/alignment-on-misaligned-backing/OOM/free/
  free-all-reuse/resize-general/resize-in-place/grow-preserves-old/query/context),
  all green · leak-clean · `-vet -strict-style` clean.
- **Measured:** (tutor-run · `odin run -o:speed` · N=100,000 × 32 B, align 8 · avg of 3)
  - **Alloc:** arena ≈ **15 ns/alloc** vs default heap ≈ **50 ns/alloc** → **~3.3× faster**.
  - With `-disable-assert`: arena ≈ **12.6 ns/alloc** — the per-call power-of-two/size
    `assert`s cost ~2–3 ns/alloc (~17%); speedup rises to ~3.9×.
  - The arena's ~15 ns is dominated by the **allocator-interface path** (indirect call
    through `Allocator.procedure` + 8-way mode `switch` + hot-path asserts), not the
    bump — the raw bump is a couple ns.
  - **Reclaim:** arena `free_all` ≈ **0–300 ns TOTAL** for all 100k objects (one pointer
    reset, O(1), below timer granularity) vs heap freeing each block ≈ **24–27 ns/obj**,
    **~2.5 ms total**. Bulk reset vs per-object free ≈ **thousands×** on total reclaim.
  - Bench harness: `katas/arena_bench/main.odin`.
- **Takeaways:** <!-- [you] review findings + probe answers worth keeping -->
  Arena allocation will be very useful going forward - this is just a start - there are
  tons of improvements that can be made, and modifications.
- **Reflections:** <!-- [you] your own words: what was hard, what clicked, open questions -->
  First time implementing an arena allocator - took longer than expected even though it's a relatively
  simple allocator. Getting used to how odin does things is the main challenge.
  
## 2026-06-17 — lesson-m02-01: allocators (concept)

- **Built:** No engine code (concept lesson). Lesson covers Odin's allocator model:
  allocation-as-runtime-policy, the `runtime.Allocator{procedure, data}` value-type
  interface, the 8-mode `Allocator_Proc` (Alloc/Free/Free*All/Resize/Query*\*/…\_Non_Zeroed),
  `context.allocator` vs per-thread `context.temp_allocator`, scope-override propagation
  through callees, and the ownership discipline slices don't encode. Registered cite-key
  `ODIN-MEM` (base:runtime + core:mem package docs). Sets up the m02-02 arena / m02-03 pool katas.
- **Measured:** (tutor-run throwaway bench, `-o:speed`, N=1,000,000 × 64-byte objects, best of 3)
  - (a) heap `context.allocator` (`new`/`free`) : **46.2 ns/alloc**
  - (b) arena `temp_allocator`, zeroed (`new` path): **5.36 ns/alloc**
  - (c) arena `temp_allocator`, non-zeroed : **4.80 ns/alloc**
  - **heap / arena ≈ 8.6×** — the general-purpose heap costs ~9× an arena bump for small allocs.
  - **zeroing a 64-byte object ≈ 0.56 ns** (~10% of the arena alloc; the `Alloc` vs
    `Alloc_Non_Zeroed` gap). Cache-resident memset is cheap; the win from `Non_Zeroed` is
    real but small, and only safe when you fully overwrite the buffer anyway.
  - Note: a first attempt at a "direct bump floor" was discarded — `-o:speed` folded the
    pure-arithmetic loop to a closed form (0.000 ns). Lesson for benchmarking: route through
    an opaque call (or read back data-dependent results) or the optimizer deletes your loop.
- **Takeaways:**
  temp_allocator allocated objects live until a free_all is called. However, as it is not long-lived
  it is important to be careful of what allocation we're passing.
  Calling a thread will not implicitly use the current context - it has to be passed explicitly.
  Alloc_Non_Zeroed is useful when you know you're going to overwrite the buffer immediately.
- **Reflections:**
  It's going to take a while to get used to the odin allocations coming from cpp, however,
  user having the freedom to easily define memory concepts is definitely very useful.

## 2026-06-16 — lesson-m01-01: skeleton

- **Built:** `engine/` as four layered packages — `core` (`VERSION` + `version()`, the
  unit-tested seam), `platform`/`render` (`info()` identity stubs, import `core` only),
  `game` (`boot()` assembles the four-layer banner via `fmt.tprintf`; imports core+platform+
  render) — plus `examples/testbed` (`main` prints `game.boot()`) and `build.ps1`. Imports
  point downward only; `engine` collection wired. Banner:
  `odyne 0.1.0 | platform: platform | render: render | game: stub`.
- **Measured:** (tutor-run, median of 3)
  - Clean build of `examples/testbed`: `-o:none` 216.6 ms / 581,120 B · `-o:speed` 940.6 ms /
    417,792 B → optimized build ~4.3× slower to compile, binary ~28% smaller.
  - Incremental (no-op touch of `engine/core/core.odin`, rebuild `-o:none`): 198.6 ms ≈ clean
    216.6 ms → **no incremental savings.** Odin recompiles the whole program every build
    (whole-program compiler, no object cache). The number to watch grow in phase 2.
  - `odin test engine/core`: 245.4 ms · 2 tests green · leak-clean · `-vet -strict-style` clean.
  - Packages compiled: 5 engine packages (core, platform, render, game, testbed) + `core:fmt`/runtime.
  - The ~580 KB `-o:none` binary is an essentially-empty engine — fixed runtime+`fmt` overhead, the "zero point."
- **Takeaways:**
  The package system makes organization easier compared to C++. We don't need to deal with header files - #pragma onces etc.\
  String concatenation with '+' can only be done using constant strings
  -collection=engine:engine exposes the packages as "engine:..."
- **Reflections:**
  A very straightforward section, nothing particularly challenging.

## 2026-06-15 — lesson-m00-02: odin-kata

- **Built:** `katas/odin_warmup/` — first kata package. Four procedures over caller-owned
  memory (no allocators): `find` (parapoly + (index, found)), `reverse` (in-place slice
  view), `parse_u32` (error enum + overflow via `intrinsics.overflow_*`), `sum_all`
  (`or_return` propagation, u64 accumulator). 21 `core:testing` tests, all green.
- **Measured:** (tutor-run)
  - Test suite: 21 tests in ~5.0 ms · 0 leaks (memory tracking on, no issue reported).
  - `-vet -strict-style`: clean.
  - `find` micro-bench, 10,000,000 iterations over an `[]int` of 11 (loop timed internally;
    result accumulated so the loop can't be elided — `acc=30909090` identical across all runs):
    - `-o:none` : ~63 ms (~6.4 ns/op)
    - `-o:speed` : ~6.5 ms (~0.65 ns/op) **debug→optimized ≈ 9.7× faster**
  - Binary sizes: `none.exe` 571,904 B · `speed.exe` 415,744 B.
- **Takeaways:** or_return is really useful for error handling - makes code so much cleaner.
- **Reflections:** This was a reasonably simple section. Learning more of Odin is nice.

## 2026-06-12 - lesson-m00-01 : odin-tour

- Built: hello.odin - now have speed.exe and none.exe
- Measured:
  - odin version: dev-2025-12-nightly:ac61f08, windows-amd64 (Windows 11)
  - none build takes 362.2257 milliseconds and generates a 537 KB file
  - speed built takes 855.19 milliseconds and generates a 395 KB file
  - time-to-first-output: none.exe 13.4227 ms, speed.exe 12.6057 ms
- Takeaways:
  Odin is quite different when it comes to ZII, template programming and RAII logic. The context helps when using third part libraries or when a specific part of the program needs a different context.
- Reflections:
  Understanding Odin might take a while as I'm used to C++ but in general it seems like a very promising and looks like its built for game engine development.
