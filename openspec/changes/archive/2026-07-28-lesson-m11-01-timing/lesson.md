# Lesson: m11-01/timing — High-resolution timing

> **Type:** kata · **Module:** m11 Timing & main loop · **Interface:** learner-designed (the constraints below fix the *physics* — monotonic source, integer nanoseconds, no accumulated drift, deterministic tests; the type vocabulary, API shape, and policies are yours to design in `design.md`)

## Goals

- Build a **frame clock** in `katas/timing/`: a monotonic time source in, a per-frame delta and a total elapsed out — with no drift, no float accumulation, and no dependence on the wall clock.
- Understand the **two clocks** every OS ships (wall vs monotonic) and why frame timing may only ever touch one of them.
- Get **integer time arithmetic** right: the multiply-before-divide overflow trap that eats a naive tick→nanosecond conversion after seconds-to-minutes of uptime, and the precision budget that decides where `f32` is safe.
- Build a fixed-capacity **frame-time history** (avg/min/max) — the data the m23-03 debug overlay will display.
- Build a **wait** primitive and learn the hard way that sleep is a request, not a promise: the testbed's busy-spin (m10-01: ~5.4M idle pumps/sec pegging a core) is one failure mode, and a 16 ms sleep that returns in 31 ms is the other.

## Prerequisites

- **m10-01/m10-02 (window & input)** — there is a real loop now, spinning as fast as the CPU allows. This kata builds the thing that will pace it; m11-02 wires it in.
- **m03-02 (handle pool)** — you have written a fixed-capacity, no-allocation-after-init container before; the frame-time history is a much smaller version of that muscle.
- **m02-01 (allocators)** — the "who allocates, when" question applies again, and the right answer here is "nobody, after init".

## Explanation

### Two clocks, and only one of them is for games

Every OS exposes an **absolute (wall) clock** — "what time is it?" — and a **difference clock** — "how much time has passed?". They are different hardware paths with different guarantees, and mixing them up is a classic bug class.

The wall clock is synchronized to an external reference (NTP), so it **steps**: forward, backward, by seconds, at arbitrary moments, plus whatever the user does in Date & Time settings. The monotonic clock is *"independent of, and isn't synchronized to, any external time reference"* — Microsoft's FAQ answers this outright: *"Is QPC affected by daylight savings time, leap seconds, time zones, or system time changes made by the administrator? No."* and *"Is the performance counter monotonic (non-decreasing)? Yes. QPC does not go backward."* [[MS-QPC]](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps). A frame delta computed from the wall clock is a frame delta that can go negative during an NTP correction — and a negative `dt` fed into physics is a teleport.

Odin makes this a **type distinction** rather than a discipline you have to remember: `Time` (wall, UNIX epoch, from `now()`) and `Tick` (*"monotonic time, useful for measuring durations"*, from `tick_now()`) are separate types, and the duration procs only accept `Tick`s [[ODIN-TIME]](https://pkg.odin-lang.org/core/time/). Underneath, `tick_now` is `clock_gettime(CLOCK_MONOTONIC_RAW)` on darwin and `QueryPerformanceCounter` on Windows [ODIN-TIME tick_now]. You get the platform delta for free — which is the first thing to notice about where this code can live in the layering law.

> **C++ delta — `std::chrono`, minus the type algebra.** `steady_clock` vs `system_clock` is exactly the monotonic/wall split, and C++ encodes units in the *type*: `duration<Rep, Period>` with compile-time `ratio` conversion, `time_point`, `duration_cast`. Odin does not have that machinery and does not want it: `Duration :: distinct i64` is **one canonical unit — nanoseconds** — with named constants (`time.Millisecond`) and explicit conversion procs (`duration_seconds`) [ODIN-TIME]. The C++ habit is to reach for a unit-typed template so the compiler catches ms-vs-s mistakes; the Odin move is to make *one* unit true everywhere inside the boundary and convert exactly once, at the edge. If you want more safety than that, a `distinct` wrapper is a design decision to argue for in your sketch — not a given.

### A tick is not a nanosecond, and the naive conversion overflows

`QueryPerformanceCounter` returns *ticks*, whose meaning comes from `QueryPerformanceFrequency`. That frequency *"is fixed at system boot and is consistent across all processors so you only need to query the frequency … as the application initializes, and then cache the result"* — and you must not assume it tracks any hardware clock: under a v1.0 hypervisor (or always, on some newer Windows) *"the performance counter frequency is fixed to 10 MHz"* [[MS-QPC]](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps). The counter itself is time since boot, and rolls over *"not less than 100 years from the most recent system boot."*

So converting ticks to nanoseconds is `ticks * 1e9 / freq`, and Microsoft's own sample tells you the ordering matters: *"To guard against loss-of-precision, we convert to microseconds **before** dividing by ticks-per-second"* [MS-QPC]. Multiply first — but now do the arithmetic on the multiply:

```
i64 max            = 9,223,372,036,854,775,807
÷ 1e9              = 9,223,372,036 ticks before ticks * 1e9 overflows
at 10 MHz          ≈ 922 seconds  ≈ 15 minutes of uptime
at 1 GHz (Arm)     ≈ 9.2 seconds of uptime
```

That last line is real: on Armv8.6+ the Generic Timer system counter *"is defined as exactly 1 GHz"* [MS-QPC]. A naive multiply-then-divide converter is correct on the developer's machine for the length of a debugging session and silently wrong on a machine that has been up for an hour. The two fixes, both worth knowing:

1. **Subtract the origin first.** Convert *relative* ticks (`now - origin`), never absolute ones. Small numerator, no overflow — and it's what you want anyway, since a boot-relative absolute time is meaningless to a game.
2. **Split the division.** Odin's Windows backend does this in the stdlib: `q := val/den; r := val%den; return q*num + r*num/den` — full precision, no overflow, one extra divide [ODIN-TIME tick_now].

Odin hands you normalized nanoseconds, so you will not write the conversion this kata — you will write the thing *above* it. The point of knowing it: **the same trap reappears every time you convert integer time**, and you now recognize the shape.

### The precision budget: where floats are allowed

`f32` has a 24-bit mantissa. That is plenty for a *delta* (16.7 ms carries a ULP of ~2 ns) and hopeless for an *absolute* time:

| absolute time held in `f32` | ULP (smallest representable change) |
| --- | --- |
| 1 s | ~120 ns |
| 1,000 s (~17 min) | ~61 µs |
| 10,000 s (~2.8 h) | ~980 µs |

At the bottom row, adding one 16.7 ms frame to the accumulator rounds; a long-running session's clock quietly stops being able to represent milliseconds. Two rules follow, and both are constraints on this kata:

- **Absolute time is integer nanoseconds.** `i64` nanoseconds covers ±292 years — the overflow question simply does not arise. Convert to float at the API edge, per use.
- **Elapsed is derived by subtraction, never accumulated.** `elapsed = now - origin` is exact forever. `elapsed += dt` accumulates every rounding error you have ever made, and if `dt` was clamped or scaled (see below) it is not even measuring the same quantity anymore. This is the single most common frame-clock bug and the measurement task will price it.

### Sleep is a request, not a promise

The testbed today spins: m10-01 measured ~5.4M idle pump iterations per second, one core at 100%, to render nothing. The fix is to give time back to the OS — and the OS will not give it back precisely when asked. SDL states the contract plainly: `SDL_DelayNS` *"waits at least the specified time, but possibly longer due to OS scheduling"* [[SDL SDL_DelayNS]](https://wiki.libsdl.org/SDL3/SDL_DelayNS). Odin's `time.sleep` on Windows is `Sleep(d / Millisecond)` — integer-truncating, so `sleep(500 * time.Microsecond)` becomes `Sleep(0)` [ODIN-TIME].

Both ecosystems ship the same workaround, which tells you it is *the* answer rather than *an* answer: sleep for the bulk, busy-wait the tail. SDL calls it `SDL_DelayPrecise` — *"will attempt to wait as close to the requested time as possible, busy waiting if necessary, but could return later due to OS scheduling"* [[SDL SDL_DelayPrecise]](https://wiki.libsdl.org/SDL3/SDL_DelayPrecise). Odin calls it `accurate_sleep`, and its implementation is worth reading before you design yours: it repeatedly `sleep`s **1 ms** while the remaining time exceeds `mean + stddev` of the *observed* overshoot — maintained by a Welford online-variance update — then spins on `_yield()` for the remainder [ODIN-TIME accurate_sleep]. Note what that design admits: the overshoot is not a constant you can look up, it is a property of *this machine right now*, so the code measures it. (Its initial estimate is seeded at 5 ms, which tells you what the author expected to find.) Your kata's wait primitive can be simpler — but "how much margin, and spin with what" is a real decision, and the measurement task will show you what your machine actually does.

### Making a clock testable

Here is the design problem that makes this kata more interesting than it looks: a test that sleeps is slow, flaky, and proves almost nothing. But *almost all* of a frame clock is arithmetic — origin subtraction, delta computation, clamping, the history window's min/avg/max — and arithmetic on `i64` is deterministic. Exactly one thing in the whole design is nondeterministic: the syscall that reads the counter.

So: **separate the reading from the reckoning.** How you do it is yours to design (the state machine takes `now_ns` as a parameter; or the clock stores a source proc you can swap; or something else you can defend), but the constraint is fixed: the tests must be able to drive the entire state machine with fabricated timestamps, and they will. Only the wait primitive is allowed to touch real time, and only in the measurement.

> **C++ habit vs DOD approach.** The C++ reflex is a `Timer` class — a `Clock` template parameter, a `Timer` per system, each calling `now()` when it feels like it, `virtual void update(float dt)` down the hierarchy. The consequences are a scattering of clock reads (each a syscall-ish cost, each seeing a *slightly different* "now", so two systems in the same frame disagree about when the frame was) and a clock read that hides inside every subsystem. The DOD shape: **read the clock once, at the top of the frame; the frame's timestamp is data that flows down** as a plain value. Everything that "has a timer" — cooldowns, animation phases, spawn delays — is then *not* an object with a clock but a **deadline stored as an integer**, compared against the frame's `now`. One read, one truth, and per-entity timing becomes an `i64` compare instead of an OS call.

### What "done" looks like structurally

A **kata** under `katas/timing/`, unit-tested in isolation with `odin test katas/timing`, leak-clean, vet-clean. Nothing enters `engine/` yet: **m11-02 ("The main loop & fixed timestep")** graduates this into the engine, wires it into the testbed loop, and lands the spec delta — so `openspec/specs/` stays honest about what the engine provably does. That graduation is also when the layering question gets settled for real, which is why your source choice needs a *reason* now: `core:time` is portable and core-layer-legal; SDL's `SDL_GetTicksNS` (*"nanoseconds since the SDL library initialized"* [[SDL SDL_GetTicksNS]](https://wiki.libsdl.org/SDL3/SDL_GetTicksNS)) would tie timing to the platform layer and to SDL's init as the origin.

## In the industry

Gregory devotes a section to exactly this problem — §8.5 "Measuring and Dealing with Time" — and it sits immediately after §8.4 "Abstract Timelines", which is the conceptual reason a game clock is more than `now()`: real time, game time, and local (e.g. animation) timelines are *different* timelines, and pausing or slow-mo means the game timeline stops tracking the real one while the engine keeps running [[GEA §8.4–8.5]](https://www.gameenginebook.com/). Whether your kata's clock supports a scaled/pausable timeline is your call — but if it does, that is where the vocabulary comes from, and if it doesn't, m11-02 will ask again.

Muratori builds the same thing on camera in Handmade Hero day 10, "QueryPerformanceCounter and RDTSC", and the split he draws — **wall clock time** (QPC: how long did the frame take?) vs **processor time** (RDTSC: how many cycles did it burn?) — is worth keeping, because they answer different questions and only the first one paces a frame. His inline conversion, `elapsedMs = (1000*(counter - last_counter)) / freq`, is the multiply-before-divide rule and the subtract-the-origin-first rule in one line [[HMH day 10]](https://guide.handmadehero.org/code/day010/). He also notes that post-Sandy-Bridge RDTSC reports *nominal* rather than actual clocks — which is the same invariant-TSC story Microsoft tells from the other side, along with the standing advice: *"We strongly discourage using the RDTSC or RDTSCP processor instruction to directly query the TSC"* — use the OS abstraction [[MS-QPC]](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps).

And the convergence is the strongest signal available: SDL3 ships `SDL_GetTicksNS` + `SDL_DelayPrecise`, Odin's stdlib ships `tick_now` + `accurate_sleep`, .NET ships `Stopwatch` over QPC [MS-QPC] — three unrelated ecosystems, all landing on *monotonic nanosecond source + sleep-then-spin waiter*. That is what you are building, from scratch, so that you know why the shape is the shape.

## Performance notes

**Cost model.** A monotonic clock read is cheap but not free, and *how* cheap depends on hardware you don't control: when the TSC backs QPC, *"user-mode queries often bypass system calls"* and access is around 30 ns; when it can't, Windows falls back to a motherboard timer (HPET/PM) whose per-call cost is *"frequently in the vicinity of 0.8 – 1.0 microseconds"* — a 30× swing, invisible in the API [MS-QPC]. Also from the same source, the formula that explains why a higher-resolution timer isn't automatically a better one: `Precision = MAX[Resolution, AccessTime]`, and separately, the ±1-tick quantization error that makes two timestamps taken on *different threads* ambiguous when they differ by one tick.

Budget arithmetic: at 60 fps a frame is 16.67 ms. One 30 ns clock read is 0.0002% of it — free. Ten thousand of them (one per entity, the C++-habit shape) is 300 µs, or **1.8% of the frame budget** burned on asking what time it is; on the platform-timer fallback that same pattern is 8–10 ms and you have lost half the frame. This is why "read once, pass the value down" is a performance decision and not just tidiness.

**Measurement task (tutor-run; numbers recorded in `curriculum/JOURNAL.md`).** Once your kata is green, the tutor benchmarks it in `katas/timing_bench/`:

- **(a) Clock read cost** — ns/call for `time.tick_now()` and for your clock's own read path, 10M iterations, `-o:speed`. Establishes which side of the 30 ns / 1 µs divide this machine (macOS, `CLOCK_MONOTONIC_RAW`) sits on, and whether your wrapper adds anything measurable.
- **(b) Sleep overshoot** — requested vs actual for 1 ms / 5 ms / 16.7 ms across `time.sleep`, `time.accurate_sleep`, and your wait primitive: mean, max, and worst-case overshoot over many trials, plus the CPU cost of the spin tail. This is the number that decides whether a frame limiter can hit 60 fps without busy-waiting.
- **(c) Drift** — 100,000 simulated frames: `elapsed` by `f32` accumulation vs `f64` accumulation vs `i64` subtraction from origin, compared against the exact value. Prices the "never accumulate" rule in microseconds.
- **(d) The overflow demonstration** — deterministic arithmetic, not a benchmark: the exact tick count at which `ticks * 1e9 / freq` goes wrong at 10 MHz and at 1 GHz, and the same conversion done the stdlib's quotient/remainder way. Proves the trap is arithmetic, not folklore.
- **(e) Per-frame overhead** — your `tick` + history update, ns/frame, expressed as a percentage of a 16.67 ms budget.

Tutor records **Built + Measured** and walks you through it; you write **Takeaways + Reflections**.

## Exercise

Build the timing kata in a new package, `katas/timing/`, and drive it to green with `odin test katas/timing`.

**The interface is learner-designed — that's your first task.** Sketch it in `design.md` (§Learner sketch); the tutor critiques against the sources, the agreed interface is recorded, and only then do stubs and failing tests exist. Decisions that are yours:

- **The time source, and the layering argument for it.** `core:time.tick_now()` (portable, `core`-legal) or SDL3 (`platform`-only, SDL-init-relative origin)? Name the choice and the consequence for m11-02's graduation.
- **The type vocabulary.** What is a timestamp, what is a duration, and do you reuse `time.Tick`/`time.Duration` or mint `distinct` types of your own? Which unit crosses your API — `i64` nanoseconds, `f32` seconds, both (and where does each belong)?
- **The frame clock's shape.** What one `tick`/`update` call returns (delta? elapsed? frame index?), how elapsed is derived, what `dt` is on the very first frame, and whether the clock is one struct or several small ones.
- **Spike policy.** A breakpoint, a stall, or a moved window produces a 3-second `dt`. Do you clamp it, drop it, report it — and *does that belong to the clock or to the main loop* (m11-02)? Either answer is defensible; the tests will bind to yours, so decide deliberately.
- **Pause/scale.** Does the clock support a game timeline distinct from the real one [GEA §8.4]? If yes, define precisely what pausing does to `elapsed` and to `dt`. If no, say why not now.
- **Frame-time history.** Fixed capacity (how much, and why that number), what avg/min/max mean before the window has filled, and whether `min`/`max` are computed on read or maintained on write.
- **The wait primitive.** Pure sleep, pure spin, or sleep-then-spin; where the margin comes from (constant? measured, like `accurate_sleep`?); what the caller passes (a duration to wait, or a deadline to wait *until* — these are not the same API and one of them composes better with a frame loop).
- **Injection.** How the tests drive time without sleeping — your call, but it has to work.

**Fixed constraints (not yours to change):**

- **Monotonic source only** — the wall clock (`time.now`, `Time`) never enters frame timing.
- **Absolute time is integer nanoseconds internally**; floats appear only at the API edge or as a `dt`.
- **Elapsed is derived by subtraction from a stored origin**, never accumulated from deltas.
- **One clock read per frame** in the frame-clock path — no hidden reads inside queries.
- **No allocation after init**: the history is fixed-capacity, caller-visible.
- **Deterministic tests**: the entire state machine drivable with fabricated timestamps; only the wait primitive touches real time.
- Tests run under `core:testing`, leak check clean, `-vet -strict-style` clean.

### Definition of done

- `odin test katas/timing` green · per-test leak check 0 leaks · `-vet -strict-style` clean
- Monotonic-only sourcing, origin-subtraction elapsed, first-frame semantics, spike policy, history statistics (including the not-yet-full window), and the wait primitive's contract all covered by the tutor's tests and passing
- Review passed (per review-rubric.md), including ≥2 comprehension probes answered
- Measurement task run by the tutor; **Built + Measured** recorded in `curriculum/JOURNAL.md`
- **Takeaways + Reflections** written by you, in your own words

## Reading list

- **Required:** [GEA §8.4–8.5](https://www.gameenginebook.com/) — abstract timelines, then measuring and dealing with time; [MS-QPC — "Guidance for acquiring time stamps" and the two FAQ sections](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps) — read the conversion FAQ before you sketch.
- **Recommended:** the [`core:time` package docs [ODIN-TIME]](https://pkg.odin-lang.org/core/time/) — `Tick` vs `Time`, `Duration`, `Stopwatch`; then read `accurate_sleep` in `$(odin root)/core/time/time.odin` — it is 20 lines and it is the design conversation about sleeping, settled; [HMH day 10](https://guide.handmadehero.org/code/day010/) — wall clock vs processor time, built live.
- **Deeper:** [MS-QPC — "Low-level hardware clock characteristics"](https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps) — resolution vs precision vs accuracy vs stability, and the ppm frequency-offset table (±10 ppm ⇒ ±36 ms per hour: your clock is *also* wrong, just slowly); [SDL_DelayPrecise](https://wiki.libsdl.org/SDL3/SDL_DelayPrecise) next to Odin's `accurate_sleep` — same idea, two houses.
