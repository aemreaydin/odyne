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

## 2026-07-28 — lesson-m11-01: timing (kata)

- **Built:** `katas/timing/` — a monotonic **frame clock**, a fixed-capacity **frame-time
  history**, and a **deadline waiter**, on `core:time` (chosen over SDL3 so timing stays
  `core`-legal for m11-02's graduation). `Frame_Clock` holds `origin` (written once) + `prev`,
  and derives `elapsed = now - origin` — never `+= dt`; `raw_dt` keeps the pre-clamp delta so a
  hitch stays observable while `dt` carries the clamp policy (`max_dt` threshold, `clamp_dt`
  substitute, `max_dt <= 0` disables). `clock_init` **is** the start of frame 0, which removes
  the first-frame-dt special case and any `started` flag; `dt == 0` is legal by contract.
  `frame_deadline` = `origin + (frame_index+1)*period` — an absolute grid, so pacing error is
  corrected rather than accumulated. **Injection by parameter:** `frame_start(clock, now)` takes
  the caller's clock read, so the whole state machine is arithmetic the 18 tests drive with
  fabricated timestamps (12 h fake uptime, so nothing can mistake a timestamp for an elapsed
  time) — a 100,000-frame session simulates in ~0.5 ms and only `wait_until` touches real time.
  `Frame_History` keeps `sum` on write (exact in integer ns — addition is invertible) and scans
  for min/max (a sliding window can't un-max). `wait_until(deadline, spin_margin)` is one loop
  with one exit under `remaining <= 0`, chunked sleep + `thread.yield()` tail. 18 tests green ·
  leak-clean · vet/strict-style clean. **Debugging gauntlet worth remembering:** a single
  `thread.yield()` where a *loop* was needed (returned before the deadline, and whether the test
  caught it depended on whether the last sleep happened to overshoot); using `sum` but dropping
  the `count == 0` guard — integer divide-by-zero is UB, and on arm64 it was a hard
  `Unhandled_Trap` in the empty-history test; an `assert(raw_dt > 0)` that outlawed the
  contract's legal zero-length frame. Two of the three were **platform-shaped**: a green suite is
  evidence about this OS and arch, not about the contract. Interface amendment during review: the
  read-only queries take `^Frame_Clock`/`^Frame_History` — an 888 B struct was being copied to
  read 8 bytes of it. No engine spec delta: m11-02 graduates this into the engine.
  Bench: `katas/timing_bench/`.
- **Measured:** (tutor-run · `odin run -o:speed` · macOS arm64, `CLOCK_MONOTONIC_RAW`)
  - **`time.tick_now()` ≈ 16.7 ns/call** (10 M reads) — firmly the TSC-class pole, not the
    0.8–1.0 µs platform-timer pole [MS-QPC]. 0.0001% of a 60 fps frame per read; ~60,000 reads
    per millisecond of spinning. One read per frame is free; ten thousand (a read per entity)
    would be 167 µs ≈ 1% of the frame.
  - **Sleep overshoot is PROPORTIONAL, not a constant** — `time.sleep` on darwin returned
    **+238 µs on a 1 ms request (24%), +1.16 ms on 5 ms (23%), +2.1–4.5 ms on 16.7 ms
    (12–27%)**, and the 16.7 ms figure swung by 2× across runs. This is the number that decides
    limiter design: a *fixed* margin cannot work if the error scales with the request.
  - **Waiter comparison** (mean overshoot, 30 trials, at 1 / 5 / 16.7 ms):
    `time.accurate_sleep` +0.1 / +0.2 / +2.7 µs · **`wait_until` m=1 ms +0.1 / +0.1 / +0.2 µs** ·
    `wait_until` m=0 (sleep-only) +256 / +21 / +103 µs · pure spin +0.1 / +0.1 / +99 µs.
    Sleep-then-spin with a 1 ms margin **matches or beats the stdlib's adaptive estimator** at
    every duration, at a fraction of its complexity — and pure spinning is *not* reliably better
    (one 16.7 ms spin trial got preempted for +2.9 ms: burning a core buys nothing the scheduler
    won't take back).
  - **Chunking is load-bearing, and the tutor got this wrong.** The tutor's refactor replaced N
    margin-sized sleeps with one big sleep — measured **+4.9 ms mean overshoot at a 16.7 ms wait
    (29%)**, a ~25,000× regression, because a 15.7 ms sleep overshoots by ~30% and blows past the
    deadline before the spin phase gets a turn. Restoring chunked sleep (`min(remaining - margin,
    1 ms)`) inside the one-loop structure: back to +0.2 µs. Saving ~15 syscalls at ~1 µs each to
    lose 4.9 ms of precision is a 5,000:1 bad trade. Measure, then optimise.
  - **Drift over 100,000 frames (27.8 min of simulated time):** derived `now - origin`
    **error 0.000 ms (exact)** · accumulated in f64 **+0.054 ms** · accumulated in f32
    **+1,989.9 ms — two full seconds**. f32 absolute time is unusable: at 1666 s the ULP is
    ~122 µs, so every `+= dt` rounds.
  - **The tick→ns overflow point:** `ticks * 1e9` overflows i64 above **9,223,372,036 ticks** —
    **15.4 minutes** of uptime at a 10 MHz counter (the hypervisor-fixed QPC frequency) and
    **9.2 seconds** on an Arm 1 GHz system counter [MS-QPC]. `intrinsics.overflow_mul` confirms
    the wrap; the stdlib's quotient/remainder split returns the right answer at the same input.
  - **Per-frame cost:** `frame_start` (incl. history push) **5.1 ns** · `history_average`
    **0.30 ns** (O(1) via `sum`) · `history_min`/`max` **12.5 ns** each (scanning 100 `i64` =
    800 B in 12.5 ns ≈ 64 GB/s — vectorised and L1-resident). A frame that ticks the clock and
    reads all three stats: **30.5 ns = 0.0002% of a 60 fps budget.** The `sum` fix bought 12 ns;
    the real argument for it was never speed but not maintaining state nobody reads.
  - **`size_of(Frame_Clock)` = 888 B** (824 B of it history). Passing it by value to read one
    field cost 0.91 ns vs 0.92 ns by pointer — i.e. **unmeasurable at this size**, because the
    ABI passes large aggregates by reference anyway and the callee never mutates. The pointer
    change was correct as *intent*, not as an optimisation. (First attempt at this measurement
    read 0.00 ns: `-o:speed` inlined the callee and hoisted a loop-invariant read. Needed
    `#force_no_inline` plus a data-dependent index — the same elision trap as m02-01.)
- **Takeaways:** <!-- [you] review findings + probe answers worth keeping -->
Have always wanted to understand how time works and now I do
- **Reflections:** <!-- [you] your own words: what was hard, what clicked, open questions -->
Good and fun milestone all around

## 2026-07-24 — lesson-m10-02: input (build)

- **Built:** `engine/platform/input.odin` + `input_windows.odin` — keyboard & mouse as a
  frame-coherent snapshot with transition capture (mechanism C: per-slot
  `{half_transitions: u8, ended_down: bool}`; counters and wheel reset at each `poll_events`
  retire, levels and cursor persist — a sub-frame tap stays observable). Learner-designed
  surface: `Key`/`Mouse_Button` enums (L/R-split modifiers, `.Unknown = 0` as ZII error
  handling), `key_down/pressed/released` + `mouse_*`, `mouse_position` (signed client px),
  `mouse_wheel` (f32 detents/frame), plus amendments `has_focus` and `set_window_title`
  (wide `SetWindowTextW`, never the ANSI variant). Read model: snapshot + derived edges,
  queue deferred (m10-01's forecast overturned — no consumer until a text/UI system).
  Policies: autorepeat yields no edge _by construction_ (no level flip — lparam bit 30 never
  read); `WM_KILLFOCUS` silent-clears levels+counters+wheel, releases held capture, cursor
  persists; sys-keys recorded then fall through to `DefWindowProcW` (Alt+F4 lives); VK→Key
  via `[256]Key` table with scancode/extended-bit L/R resolve; chord capture — `SetCapture`
  first down / `ReleaseCapture` last up over a `bit_set` chord, `WM_CAPTURECHANGED` theft
  reconciliation. Debugging gauntlet worth remembering: **sent-message reentrancy** —
  `Release/SetCapture` deliver `WM_CAPTURECHANGED` synchronously _during_ the call, so
  state-before-syscall ordering is what makes `holds_capture` a valid "did I initiate this?"
  discriminator; the inverted handler branches were benign before the reorder and
  edge-destroying after it (caught by a regressing tap test); a one-directional `bit_set`
  (`+=` with no `-=`) made `card()==0` unreachable and capture unreleasable. 27 conformance
  tests (PostMessageW-driven hidden windows), green · leak-clean · vet/strict-style clean;
  test files now self-contained under `#+private file` (new project convention). Demo:
  testbed title-bar readout (position + held-button chord + last key, values persisted /
  strings rebuilt per frame / one temp `free_all` per frame); Esc converges with ✕ through
  `set_should_close`. Spec delta capability: `platform-input`. Bench: `katas/input_pump_bench/`.
- **Measured:** (tutor-run · `odin run -o:speed` · 2 runs, stable)
  - **Empty pump, visible window: 184.3 ns/frame** — statistically identical to m10-01's
    185 ns _with the input retire now inside it_: the snapshot bookkeeping is invisible at
    frame scale.
  - **Retire ≈ 6.7 ns/window** (isolated via the 1→4 hidden-window slope): zeroing ~136 B
    of counters+wheel ≈ 2.5 cache lines of L1 stores. A window's entire input state is one
    ~152 B struct.
  - **Empty pump, hidden window: ≈ 9.2 ns/frame** — 20× cheaper than visible, same code.
    Consistent with `PeekMessageW` skipping the kernel round-trip when the queue's wake
    bits show nothing pending [unverified mechanism; the 9-vs-184 ns split is measured].
    m10-01's "185 ns forever-cost" was a property of _visible-window queue state_, not of
    the pump.
  - **Flooded pump: `WM_MOUSEMOVE` ≈ 745 ns/msg · key down/up ≈ 2,113 ns/msg posted** (key
    path includes `TranslateMessage` plus a synthesized-and-drained `WM_CHAR` per keydown).
    Kernel message delivery dominates; odyne's decode is noise by comparison (see retire).
  - **1000 Hz mouse @60 fps projection: ≈ 12.4 µs/frame = 0.075% of budget** — an upper
    bound: posted floods don't coalesce, real hardware mouse-move messages do.
  - **Queries: `key_down` ≈ 0.44 ns · `mouse_position` ≈ 0.36 ns** (10M iters) — same as
    `should_close` (0.42) and the m03 handle kata (0.41): a pool resolve + a byte read.
    The testbed's all-63-keys readout scan costs ~28 ns/frame.
  - **Build: 1,231 ms median (3 clean builds) · 486,912 B** vs m10-01's 1,320 ms /
    480,256 B → **+6,656 B (+1.4%)**, no compile-time regression, for the entire input
    system.
- **Takeaways:** <!-- [you] review findings + probe answers worth keeping -->
  Great lesson, finally have an idea how input works and not relying on glfw
- **Reflections:** <!-- [you] your own words: what was hard, what clicked, open questions -->
  The half_transition and capture change took a while to understand but all in all a fun lesson

## 2026-07-22 — lesson-m10-01: win32-window (build)

- **Built:** `engine/platform/window.odin` + `window_windows.odin` — odyne's first OS boundary
  and first visible artifact: a raw Win32 window (no middleware) behind a handle-based platform
  API. Portable surface: `Window_Handle :: distinct u64`, ZII-friendly `Window_Desc`
  (defaults "odyne"/1280×720/visible; `hidden` for headless tests), `init`/`shutdown`,
  `create_window`/`destroy_window`, global non-blocking `poll_events` (`PeekMessageW` — Win32
  queues are per-THREAD; windows have thread affinity to their creator), and state queries
  `is_open`/`should_close`/`client_size`. Internals: `Window_State` lives in an m03
  `Handle_Pool(Window_State, Window_Handle)`; **`GWLP_USERDATA` stores the `Window_Handle`,
  never a pointer** — the WndProc (a `proc "system"` with no Odin context; first line
  `context = runtime.default_context()`) resolves it per message, so pool swap-relocation
  can't dangle it (proven by the two-window destroy-independence test). Close is a
  negotiation: `WM_CLOSE` records `close_requested` and returns 0; only `destroy_window`
  destroys. Client-size semantics via `AdjustWindowRectExForDpi`; UTF-16 conversion at the
  border; `UnregisterClassW` at shutdown; black stock-brush background until a renderer owns
  the pixels (to be removed in m20 — swapchain fights the eraser). 8 conformance tests
  (hidden windows, single-threaded runner — `-define:ODIN_TEST_THREADS=1`), green ·
  leak-clean · vet/strict-style clean; `core:sys/windows` confined to platform (grep-verified).
  Demo: visible resizable window, clean ✕ exit. Debugging gauntlet worth remembering:
  missing `WNDCLASSEXW.cbSize` · class re-registration across init cycles ·
  stack-local-pointer-in-USERDATA (the m03 trap, live) · client-vs-outer size · a ZII
  named-return (`ok` never set true) silently discarding every WndProc write.
  Spec delta merged capability: `platform-window`. Bench: `katas/window_pump_bench/main.odin`.
- **Measured:** (tutor-run · `odin run -o:speed` · 2 runs, stable)
  - **Empty pump ≈ 185 ns/frame** (1M iterations): the forever-cost of `poll_events` with an
    idle queue — one `PeekMessageW` kernel round-trip. At 60 fps that's ~0.001% of a 16.7 ms
    frame budget: the pump is never the problem.
  - **`should_close` ≈ 0.44 ns/query** (10M iterations): the loop condition is one pool
    resolve — matching m03-01's measured 0.41 ns. The handle discipline at a real OS boundary
    costs what it cost in the kata: nothing.
  - **`init` ≈ 0.03 ms; `create_window` (visible) ≈ 16–18 ms** one-shot — dominated by the
    OS/DWM actually building the window; irrelevant to steady-state.
  - **Build:** testbed clean `-o:speed` 1.32 s; binary **480,256 B** vs m03-03's 472,576 →
    **+7,680 B (+1.6%)** for user32-linked windowing.
  - The testbed loop currently pumps ~5.4M times/sec doing nothing — a busy-spin pegging one
    core at 100%. Correct today; **m11 (timing & main loop) exists to fix exactly this.**
- **Takeaways:** <!-- [you] review findings + probe answers worth keeping -->
  Win32 not as hard as it looks, actually managed to get it running in a couple hours
- **Reflections:** <!-- [you] your own words: what was hard, what clicked, open questions -->
  There are still a lot of details in win32 windows but this was a fun milestone.

## 2026-07-22 — lesson-m03-03: core-containers (graduate)

- **Built:** `engine/core/containers/handle_pool/` (`package handle_pool`) — the m03-02 kata
  graduated into the engine's core layer, with two learner-driven design amendments beyond a
  straight move. (1) **Caller-typed handles:** `Handle_Pool($T, $HT)` with a compile-time
  `where` contract — HT is 64-bit unsigned (distinct included), T embeds `handle: HT` — so each
  system exposes its own distinct handle type and cross-system mixups are compile errors
  (verified: violating instantiations fail with the condition named). (2) **Embedded handle
  replaces `dense_to_slot`:** the pool went three arrays → two; `add` writes the issued handle
  into the stored copy, `remove` patches the moved item's slot via its embedded handle
  (Bitsquid's actual design, expressible generically via `type_has_field` — refuting m03-02's
  "a generic container can't demand T carry its id"), `clear` sweeps live items' handles.
  Packaging: one sub-package per container under `engine/core/containers/` (stdlib
  `core:container` shape); kata's unprefixed names survive; ready-made `Handle` kept for
  non-boundary pools; `Handle_Error` → `Error`. Second engine spec delta merged capability:
  `core-containers`. 17 conformance tests (incl. add-sets-embedded-handle, ready-made Handle,
  distinct-type coexistence, and clear-bumps-only-live — the review catch), green · leak-clean ·
  vet/strict-style clean. Demo checkpoint: testbed exercises the pool through `engine:core`
  under a heap-backed tracking allocator — stale refusal, loan mutation, self-identifying slice
  walk, no leaks. Review findings, both fixed: F1 `clear` walked the full items array (ZII
  entries over-bumped slot 0's generation ~capacity× per clear — pinned red first); F2 `init`
  swallowed allocation failure (surfaced live as the demo's OOM crash-at-a-distance). `get_ptr`
  now documents the pool-owned `handle` field (scribbling through the loan mispatches remove).
  Bench harness: `katas/handle_pool_bench_engine/main.odin`.
- **Measured:** (tutor-run · `odin run -o:speed` · N=100,000 × 32 B entity — kata's `id` filler
  became the embedded handle, so sizes match · sums-checked · 3 runs)
  - **The distinct-type tax is zero — measured, not asserted:** ready-made `hp.Handle` vs
    `Bench_Handle :: distinct u64` instantiations, clean-run pair: add 2.58 vs 2.55 · remove
    2.46 vs 2.29 · churn 4.29 vs 4.32 · resolve in-order 0.73 vs 0.81 · shuffled 2.91 vs 3.02 ·
    half-stale 3.42 vs 3.54 · iterate 0.23/0.13 vs 0.24/0.13 ns — identical within noise.
    `distinct` changes the type, not the code.
  - **No regression vs the kata — several ops faster:** add ≈ 2.5 vs kata 4.5 ns · remove
    ≈ 2.3 vs 3.0 · churn ≈ 3.7–4.3 vs 3.9 · resolve 0.73–0.95 / 2.9–3.9 vs 1.08 / 3.8 ·
    stale-mix ≈ 3.4–3.6 vs 4.2 · iterate 0.23–0.24 / 0.13 vs 0.30 / 0.24. The add/remove gains
    are directionally real: dropping `dense_to_slot` removed a third array from `add`'s write
    stream, and `remove`'s patch now reads the moved item's cache line (already touched by the
    swap) instead of a separate table. Caveats: cross-day machine state — carry direction, not
    exact deltas; occasional 10–12 ns add spikes on whichever variant runs first are warm-up
    noise (clean runs show parity).
  - **Build cost:** `odin test` command 0.30 s wall (17 tests, 4.3 ms execution; m02-04: 10
    tests, 4–9 ms). Testbed clean `-o:speed` build 1.30 s; binary **472,576 B** vs m02-04's
    464,384 → **+8,192 B (+1.8%)** for the whole containers package (parapoly instantiations
    are per-(T,HT), so this grows with distinct pool types used, not with capacity).
- **Takeaways:** <!-- [you] review findings + probe answers worth keeping -->
  Keeping the handle on the item as well made the algorithm much easier to reason about,
  and cleaner.
- **Reflections:** <!-- [you] your own words: what was hard, what clicked, open questions -->
  Easier than the kata as a simple handle addition to the item made evrything easier.

## 2026-07-21 — lesson-m03-02: handle-pool (kata)

- **Built:** `katas/handle_pool/` — the generational handle pool, a **packed array + index
  table** (Bitsquid's second design). `Handle_Pool($T){items (dense [0:count)), dense_to_slot,
slots, count, free_head/tail, allocator}`; `Slot{gen, dense_idx, next}`; `Handle :: distinct
u64` (low 32 slot index, high 32 generation; gens start at 1 so ZII `Handle(0)` never
  validates). Owned fixed-capacity storage via `init(capacity, allocator)` / `destroy`. `add`
  appends to the dense array and wires both maps; `remove` swap-with-lasts the last item into the
  gap, patches the moved item's slot through `dense_to_slot`, bumps the freed slot's generation
  (retire-on-wrap via `intrinsics.overflow_add`, else FIFO-enqueue); `get`/`get_ptr`/`has` share a
  private `resolve` (range + gen≠0 + gen-match, garbage-safe); `slice` returns `items[:count]`
  (iteration is one dense walk); `clear` bumps every live slot's gen (via `dense_to_slot`) then
  re-threads the whole freelist. First **parapoly struct** in the course. 13 `core:testing` tests
  (incl. swap-with-last patch, FIFO reuse order, retire-at-max, clear-rebuilds-full-freelist),
  green · leak-clean · `-vet -strict-style` clean. Kata only — graduates into `engine:core` at
  m03-03. Bench harness: `katas/handle_pool_bench/main.odin`.
- **Measured:** (tutor-run · `odin run -o:speed` · odin dev-2026-07-nightly:819fdc7 ·
  N=100,000 × 32 B Entity · resolve/iterate 50 passes · sums-checked · avg of 3)
  - **Lifecycle beats the allocator-interface pool — the lesson's hypothesis, confirmed:** hp
    **add ≈ 4.5 ns/op**, **remove ≈ 3.0 ns/op** vs the m02-03 pool's 11.5 / 4.5; **add+remove
    churn ≈ 3.9 ns/cycle** vs pool **≈15** (**~3.7×**) and heap **≈40** (**~10×**). Dropping the
    `Allocator_Proc` indirect call + 8-mode switch + interface dispatch — which _were_ the m02
    numbers — is worth ~4× on a direct-call container. (Churn beats the fill-`add` number because
    1-live-at-a-time stays L1-resident; the fill streams N×(32 B item + 12 B slot).)
  - **Resolve ≈ 2.6× the m03-01 scaffolding — the price of a real, safe API, not a bug:**
    **in-order ≈ 1.08 ns/visit** (scaffolding 0.41), **shuffled ≈ 3.8** (scaffolding 1.61). The
    delta is structural and expected: `resolve` does a range check + zero-gen check + the
    `get_ptr`→`resolve`→`unpack` call boundary the inlined scaffolding skipped, and `Slot` is
    **12 B** — the freelist `next` rides in the resolve-hot cache line — vs the scaffolding's 8 B.
    The ~2.6× shows up in _both_ orders → fixed per-visit overhead (safety + the fat slot), not a
    cache pathology.
  - **Stale-mix ≈ 4.2 ns/visit (~half handles stale, storage order) — branches, not data:** ~4×
    the all-live in-order number despite near-identical memory access. The failed-check path is a
    cheap early return; the cost is **branch misprediction** on the 50/50 live/stale `if`.
    Staleness detection is data-cheap and branch-expensive when validity is unpredictable.
  - **Iteration is dense-array speed and occupancy-independent — the packed payoff:** **high occ
    ≈ 0.30 ns/visit** (100k live), **low occ ≈ 0.24** (10k live) — both ≈ m03-01's 0.23 dense
    baseline. Because `slice` is `items[:count]`, per-live-visit cost doesn't move with occupancy;
    array-with-holes would walk capacity and skip holes, so its per-live cost balloons as the pool
    empties. Exactly the trade the packed layout was chosen for.
  - Working set ~4–8 MB (cache-resident); carry the **ratios**, not the ns.
- **Takeaways:** <!-- [you] review findings + probe answers worth keeping -->
  Handles are lot easier to use and debug and lot harder to make mistakes with
  compared to pointers. Packed array handle also makes it easier to iterate on hot loops
- **Reflections:** <!-- [you] your own words: what was hard, what clicked, open questions -->
  This was the hardest one so far - I'm still having trouble wrapping my head around the structure with dense_to_slot sometimes but I'm glad I was able to implement.

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
    overlap, where a real object _graph_ chains dependent hops.
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
