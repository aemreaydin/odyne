# Interface design

> **Interface:** learner-designed — rationale: the lesson fixes the *physics* of a frame clock (monotonic source, integer nanoseconds, elapsed by subtraction, one read per frame, deterministic tests) because those are not opinions. Everything above the physics is opinion — the type vocabulary, what `tick` returns, whether the clock owns spike policy or the main loop does, whether a pausable game timeline exists yet, and what a "wait" call even takes as an argument. Those are the decisions m11-02 will have to live with, so you make them here and defend them.

## Learner sketch

<!-- [you] Your proposed API for katas/timing/. Rough is fine — this starts the design
     conversation. Address at least:

       - TIME SOURCE: core:time.tick_now() or SDL3 SDL_GetTicksNS()? State the layering
         consequence (core-legal vs platform-only) for m11-02's graduation.

       - TYPE VOCABULARY: what is a timestamp, what is a duration. Reuse time.Tick /
         time.Duration, or mint your own distinct types? Which unit crosses your API
         (i64 ns, f32 seconds, f64 seconds) and where does each belong?

       - FRAME CLOCK: the struct's fields, and the signature of the one call per frame —
         what does it return (dt? elapsed? frame index? all three, or does the caller
         query separately)? What is dt on frame 0? How is elapsed derived?

       - SPIKE POLICY: a 3-second dt from a breakpoint or a stall — clamp, drop, or
         report? And does this belong to the clock or to m11-02's main loop? Decide.

       - PAUSE / SCALE: is there a game timeline distinct from the real one [GEA §8.4]?
         If yes: exactly what pause does to elapsed and to dt. If no: why not yet.

       - FRAME-TIME HISTORY: capacity (and why that number), avg/min/max semantics
         before the window fills, computed-on-read or maintained-on-write.

       - WAIT PRIMITIVE: sleep / spin / sleep-then-spin; where the margin comes from
         (constant or measured like accurate_sleep); and does the caller pass a
         DURATION to wait or a DEADLINE to wait until? (They compose differently.)

       - INJECTION: how tests drive the whole state machine without sleeping —
         now_ns as a parameter, a swappable source proc, or something else.

     Signatures + short ownership/lifetime notes. See lesson.md §Exercise for the full
     brief and the fixed constraints. -->

- We will use core:time instead of SDL - we will use as little SDL as possible in general
- Tick is i64 (nanoseconds), Duration is i64, however the conversion to micro, milliseconds sketch
will be to f64 for increased precision, I'm not sure if the user every needs the nanoseconds, I think for games usually micro/milliseconds is enough and that will be f64
- FrameClock {
  need frame_index for swapchains
  dt: Duration
  elapsed: Duration
}

get_deltatime(^FrameClock) ->f64
frame_start() // sets elapsed and delta_time at the start of each frame

- spike policy: delta_time will probably be set to 0 dfor the duration of the pause
or we can set an upper_bound for a frame limit like a second and if that is passed, we 
can set the frame to 1/30s delta time etc.
- frame-time history: 100 data poitns seems like a good number for me(i've chosen it arbitrarily) as it seems a good size/speed balance. it should be maintained on write

- wait primitive: we will start with the duration and use accurate_sleep

- I have no idea

## Tutor critique

Three calls here are better than they look. **`core:time` over SDL** is right and for the right
reason: it keeps timing `core`-legal, so at m11-02 the clock can sit *below* platform and both
platform and render may use it — the SDL route would have made timing a platform export and tied
the origin to `SDL_Init` [[SDL SDL_GetTicksNS]](https://wiki.libsdl.org/SDL3/SDL_GetTicksNS).
**Integer nanoseconds inside, float only at the conversion** is the constraint stated correctly.
And **`frame_index` for swapchains** is genuine forward thinking — frames-in-flight indexing
needs a monotonically increasing frame counter, and the clock is the honest place for it (the
renderer derives its slot as `frame_index % frames_in_flight`; don't store that here).

Findings, worst-first:

**1 — The struct can't compute either of its own outputs (the crux).** `dt` and `elapsed` are
*results*; the sketch stores the results and not the *inputs*. There is no field holding the
init timestamp and none holding the previous frame's timestamp — so `elapsed` has only one
possible implementation, `elapsed += dt`, which is exactly the accumulation the lesson forbids
and measurement (c) is built to price. **Q:** which two timestamps must live in the struct for
`elapsed = now - origin` and `dt = now - prev` to be computable, and which of the two *never*
changes after init?

**2 — "I have no idea" (injection) is answered by the shape of `frame_start`, not by a
mechanism.** Your `frame_start()` takes no parameters, which is what makes it untestable. Two
shapes:

- **A — the caller reads the clock:** `frame_start(clock: ^Frame_Clock, now: time.Tick)`. The
  state machine becomes pure arithmetic; tests hand it fabricated `Tick`s and can simulate a
  10-hour session in microseconds. The main loop writes `frame_start(&clock, time.tick_now())`.
- **B — the clock reads for itself:** store `source: proc "contextless" () -> time.Tick` and let
  tests swap in a fake. Costs a field, an indirect call, and a ZII hazard (a zeroed clock has a
  nil source and traps).

Recommend **A**, and note the bonus: it makes "exactly one clock read per frame" *structural* —
the clock literally cannot read twice, because it cannot read at all.

> **C++ delta.** In C++ this is a design pattern: `template<class Clock>` (chrono's own answer)
> or an `IClock` interface with a virtual `now()`. In Odin the cheapest injection is not to
> inject — pass the value. "Testable clock" is a parameter, not an abstraction.

**3 — A float named `deltatime` with no unit is a bug factory.** `get_deltatime -> f64`:
seconds or milliseconds? Every caller has to guess, and one of them will guess wrong (this is
the classic). Put the unit in the name, and pick the unit per *use*:

- **`dt` → `f32` seconds.** Gameplay math and `core:math/linalg` are `f32`; an `f64` dt gets
  truncated at every call site anyway. At 16.7 ms an `f32` carries a ULP of ~2 ns — nothing.
- **absolute elapsed → `f64` seconds** (or stay in `Duration`). This is the one place `f32`
  actually fails: ~1 ms ULP after 2.8 hours of uptime (lesson.md's table).
- **"does the user ever need nanoseconds?"** Not for display — but for *storage* they do (which
  you got right), and a frame-time overlay showing `16.7 ms` is reading a sub-ms number. Convert
  at the edge with what already exists: `time.duration_milliseconds` is there, so don't write a
  wrapper for it. Wrapping every stdlib conversion is the C++ habit here.

Repo style, while we're at naming: `FrameClock` → **`Frame_Clock`** (`Window_Desc`,
`Handle_Pool`, `Mouse_Button`), and no `get_` prefix — the codebase says `client_size`,
`mouse_position`, `should_close`. So `dt_seconds(clock)`, `elapsed_seconds(clock)`.

**4 — Pause and clamp are two different mechanisms, and you've merged them into one field.**

- *The clamp* (spike → substitute a sane dt) is a **real-timeline** hazard control. Keep it. But
  `1 s` is very generous, and the reason is m11-02: with a fixed-timestep accumulator a 1-second
  dt becomes ~60 simulation steps *inside one frame*, which makes that frame longer, which makes
  the next dt bigger — a runaway. A tighter default (~100 ms) leaves normal jitter untouched and
  caps the catch-up work. Make both the threshold and the substituted value **fields**, so the
  tests bind to the behavior instead of to magic numbers.
- *Pause* is not a dt value, it's a **second timeline**. `dt = 0` during pause looks harmless
  until something divides by it: `fps = 1/dt` → `+Inf`, `velocity = distance/dt` → `+Inf`. And a
  paused game still needs *real* elapsed time for UI animation and the frame-time overlay — one
  clock cannot report both. The shipping shape is real timeline + game timeline, the second
  advancing by a scaled delta [[GEA §8.4]](https://www.gameenginebook.com/). **Recommendation:
  no game timeline in this kata** — real timeline only; when it arrives (m11-02 or Breakout) it
  is a *separate* clock fed the real dt, not a flag inside this one.
- Consequence to write down deliberately: once dt is clamped, **sum-of-dt ≠ elapsed**, and that
  is *correct*, not a bug — `elapsed` is real time and never clamped. Keep the pre-clamp value in
  a `raw_dt` field too: it costs 8 bytes, makes the clamp testable through public state, and the
  hitch is exactly what a debug overlay wants to show.

**5 — "min/max maintained on write" is not implementable for a sliding window.** A running
scalar max works for a *growing* set. Yours evicts: when the sample that *was* the max scrolls
out of the 100-frame window, a maintained `max` field has no way to discover the new maximum —
the information was thrown away (the real data structure for this is a monotonic deque, which is
far more machinery than a debug overlay is worth). **Q:** trace it — `max` is 40 ms from frame 7,
frame 107 evicts it, all remaining samples are ~16 ms; what does your maintained field say?

The split that works, and it's cheap:

- **`sum` on write** — add the new sample, subtract the evicted one. In integer nanoseconds this
  is **exact forever**, which is the ns rule paying off directly: the same trick on `f32` samples
  would drift, so `avg` would need re-scanning anyway.
- **`min`/`max` by scan on read** — 100 `i64`s is under 100 ns, once per frame, for a number a
  human reads. Cheap enough that being correct is free.

Also define the not-yet-full window (the tests will check it): `avg` divides by `count`, not by
capacity; `min`/`max` range over `count`; all three return `0` when `count == 0`. And your
capacity reasoning is better than "arbitrary" — 100 frames ≈ 1.7 s at 60 fps, a good smoothing
window for an overlay, and `[100]time.Duration` is 800 B inline: no allocation, ever.

**6 — Duration-based waiting drifts; deadline-based waiting self-corrects.** This is finding 1's
principle again, now applied to pacing. `wait(target - elapsed_so_far)` re-bases the target on
*now* every frame, so every sleep's overshoot is permanently absorbed into the cadence: 60 fps
becomes 58 and nothing ever pulls it back. A deadline derived from a fixed origin
(`origin + (frame_index+1)*period`) cannot drift — a long frame just means the next deadline is
already past and the limiter doesn't sleep. **Q:** two consecutive frames overshoot their sleep
by 2 ms each — in each of the two designs, where has that 4 ms gone by frame 10?

On `accurate_sleep`: calling it is defensible, but both the learning and measurement (b) live in
the margin decision, so build the sleep-then-spin yourself with an explicit `spin_margin` — then
the bench compares your fixed margin against the stdlib's *adaptive* one (Welford-estimated
`mean + stddev` of observed overshoot) [ODIN-TIME accurate_sleep]. Edges the tests will bind:
deadline already past → return immediately without sleeping; `spin_margin == 0` → pure sleep;
`spin_margin ≥ remaining` → pure spin. Have it **return the timestamp it stopped at** — the
limiter's last clock read is precisely the next frame's `now`, so the loop still makes one read
per frame with a limiter in it.

**7 — Polish.**

- `dt`, `elapsed`, `frame_index` stay **plain fields**, read directly (precedent: m03-02's
  `count`). Procs earn their place by *converting* or by *advancing state*, never by echoing a
  field.
- Reuse `time.Tick` / `time.Duration` instead of minting your own: you get the wall-vs-monotonic
  separation enforced by the type system for free (a `Time` cannot be passed where a `Tick`
  belongs), plus `tick_diff`/`tick_add` and the `Millisecond`/`Second` constants
  [[ODIN-TIME]](https://pkg.odin-lang.org/core/time/). Distinct types of your own buy nothing at
  kata scope and cost the interop.
- Do the arithmetic with `time.tick_diff` / `time.tick_add`, never by reaching into `Tick._nsec`.
  **C++ delta:** the leading underscore is a *convention* meaning "not yours", not `private:` —
  the compiler will happily let you touch it.
- Say out loud that this struct is legitimately **not ZII-friendly**: `origin` must be a real
  timestamp, so `clock_init` is mandatory and there is no "zero clock just works" story. Worth
  noting because odyne's other types went the other way (`Window_Desc` defaults).
- **`clock_init` *is* the start of frame 0** (`origin = prev = now`). That disposes of the
  awkward "what is dt on the first frame?" special case without a `started` flag: dt is `0`
  during frame 0, every later frame has a measured dt, and every `frame_start` pushes exactly one
  history sample. Document `dt == 0` as legal — never divide by dt without a guard — which is
  also the honest answer to the pause question above.

### Proposed interface — confirm or adjust (tests bind to this)

```odin
package timing

import "core:time"

HISTORY_CAPACITY :: 100 // ≈1.7 s at 60 fps; [100]Duration = 800 B, no allocation ever

// Frame_History — fixed-capacity ring of real (pre-clamp) frame durations.
// `sum` is maintained on write and is EXACT: integer ns add/subtract never drifts.
// min/max are scanned on read — a sliding window cannot maintain them in a scalar.
Frame_History :: struct {
	samples: [HISTORY_CAPACITY]time.Duration,
	next:    int, // write cursor
	count:   int, // valid samples, saturating at HISTORY_CAPACITY
	sum:     i64, // Σ samples[0:count] in ns
}

// Frame_Clock — the real timeline. NOT ZII-friendly: clock_init is mandatory.
// Invariant: elapsed is ALWAYS now - origin, never a sum of deltas.
Frame_Clock :: struct {
	origin:      time.Tick,     // set once by clock_init; never written again
	prev:        time.Tick,     // timestamp of the current frame's start
	dt:          time.Duration, // delta of the frame just ended, AFTER clamp policy
	raw_dt:      time.Duration, // delta before clamping — the hitch, observable
	elapsed:     time.Duration, // prev - origin: real time since init
	frame_index: u64,           // 0 for the frame clock_init started; +1 per frame_start
	max_dt:      time.Duration, // clamp threshold; 0 disables clamping
	clamp_dt:    time.Duration, // value substituted when raw_dt > max_dt
	history:     Frame_History,
}

// clock_init — starts frame 0. `now` is the caller's clock read (see injection, finding 2).
clock_init :: proc(
	clock:    ^Frame_Clock,
	now:      time.Tick,
	max_dt:   time.Duration = 100 * time.Millisecond,
	clamp_dt: time.Duration = time.Second / 30,
)

// frame_start — ends the current frame and begins the next. ONE call per frame.
frame_start :: proc(clock: ^Frame_Clock, now: time.Tick) -> (dt: time.Duration)

dt_seconds      :: proc(clock: Frame_Clock) -> f32 // gameplay unit (linalg is f32)
elapsed_seconds :: proc(clock: Frame_Clock) -> f64 // absolute time needs the mantissa

// frame_deadline — when the CURRENT frame should end, for a target period.
// Derived from origin, so pacing cannot drift (finding 6).
frame_deadline :: proc(clock: Frame_Clock, period: time.Duration) -> time.Tick

// history_* — driven by frame_start, public so tests can exercise them directly.
history_push    :: proc(h: ^Frame_History, d: time.Duration)
history_average :: proc(h: Frame_History) -> time.Duration // 0 when count == 0
history_min     :: proc(h: Frame_History) -> time.Duration // 0 when count == 0
history_max     :: proc(h: Frame_History) -> time.Duration // 0 when count == 0

// wait_until — the ONLY proc that touches the real clock. Sleeps while more than
// spin_margin remains, then busy-waits. Returns the tick it stopped at, which the
// caller reuses as the next frame's `now`.
wait_until :: proc(deadline: time.Tick, spin_margin: time.Duration = 1 * time.Millisecond) -> (now: time.Tick)
```

**Per-operation contract** (what the tests enforce):

| Operation | Behavior | Edge |
|---|---|---|
| `clock_init` | `origin = prev = now`; `dt = raw_dt = elapsed = 0`; `frame_index = 0`; history empty; store clamp fields | starts frame 0 — no `started` flag |
| `frame_start` | `raw_dt = tick_diff(prev, now)`; `dt = raw_dt > max_dt && max_dt > 0 ? clamp_dt : raw_dt`; `elapsed = tick_diff(origin, now)`; `frame_index += 1`; `prev = now`; `history_push(raw_dt)`; return `dt` | `now == prev` ⇒ `dt = 0`, sample of 0 pushed; `now < prev` never happens (monotonic source) |
| `elapsed` invariant | always `prev - origin` — exact over an arbitrarily long session, never `+= dt` | clamped frames make `Σdt ≠ elapsed`: correct by design |
| `dt_seconds` / `elapsed_seconds` | convert the stored ns; no clock read | `dt == 0` is legal (frame 0) — callers must guard division |
| `frame_deadline` | `tick_add(origin, Duration((frame_index+1) * i64(period)))` | overrun ⇒ deadline already past ⇒ `wait_until` returns at once |
| `history_push` | write at `next`, subtract the evicted sample from `sum` when full, add the new one; advance cursor mod capacity; `count` saturates | exact in integer ns; no float accumulator anywhere |
| `history_average` | `Duration(sum / i64(count))` | `count == 0` ⇒ `0` |
| `history_min` / `history_max` | scan `samples[0:count]` | `count == 0` ⇒ `0`; partial window scans `count`, not capacity |
| `wait_until` | while `remaining > spin_margin`: sleep; then spin until `tick_now() >= deadline`; return that tick | past deadline ⇒ immediate, no sleep; `spin_margin == 0` ⇒ pure sleep; `spin_margin ≥ remaining` ⇒ pure spin; never returns before `deadline` |

Everything except `wait_until` is drivable with fabricated `Tick`s — which is the whole point of
finding 2, and how the test suite simulates a 10-hour session without waiting 10 hours.

### Learner answers → resolutions

**A1 (the two timestamps): correct.** `prev` (last frame's start) and `origin` (set at init,
never written again). Findings 1 and 2 resolved as proposed.

**A3 (`delta_time`) — two corrections.**

- **There is no `freq`.** `(now - last_frame) / freq` is the QPC-level operation, and
  `core:time` already did it *below* you: darwin's `clock_gettime` returns nanoseconds outright,
  and the Windows backend divides QPC by `QueryPerformanceFrequency` through its overflow-safe
  `mul_div_u64` before you ever see a `Tick` [ODIN-TIME tick_now]. `tick_diff` hands you
  nanoseconds. Reaching for a frequency here means re-implementing the backend one layer too
  high — the conversion you owe is ns → seconds (`/1e9`), and `time.duration_seconds` already
  does that too.
- **Do not return the rolling average as `dt`.** They are two different quantities with two
  different consumers: the *smoothed* number is for the **human** (a jittering readout is
  unreadable), the *measured* number is for the **simulation**. Feed a smoothed dt into the sim
  and sim time stops tracking real time — permanently and unboundedly, because the error is
  re-applied every frame rather than corrected. It gets worse at m11-02: dt there feeds the
  fixed-timestep accumulator, i.e. "how many simulation steps do I owe?", and a smoothed dt makes
  that count wrong in a way the accumulator cannot detect. This is the same shape as the
  pause/clamp merge in finding 4 — two jobs, one field. **Resolved:** `dt_seconds` returns the
  measured (clamped) dt; `history_average` is the display path.
- **Unit: seconds for `dt`, milliseconds for display.** Your ms preference is right where it
  belongs — the overlay — and gets it via `time.duration_milliseconds(history_average(h))` (f64),
  no wrapper of ours. But gameplay dt stays `f32` **seconds**, because velocities and
  accelerations are expressed per second (`pos += vel * dt`) and `core:math/linalg` is `f32`; a
  ms-based dt puts a `/1000` in every gameplay expression, which is where the unit bugs come from.

**A4 (keep the clamp) + "revert to 16 ms": read as `clamp_dt = time.Second/60`** — the value
*substituted* for a spike, i.e. "pretend that hitch was one 60 Hz frame". Recorded as the default.
⚠️ If you meant the **threshold** (`max_dt`) instead, that is a bug: at 60 fps every real frame
measures ~16.7 ms, so a 16 ms threshold clamps *every frame*, and any machine running below 60 fps
would be permanently in slow motion with no way to notice. The threshold has to sit several frames
above normal — `100 * time.Millisecond` (~6 frames) recorded. Both are fields, and every test sets
them explicitly, so changing a default later touches one line and no tests.

**Q2 (max eviction) and Q3 (the 4 ms) went unanswered** — proposal stands as written (`sum`
maintained on write, min/max scanned on read; deadline-based waiting). Both come back as review
probes at task 5.1, so they are deferred, not dropped.

## Agreed interface

Locked. The proposed interface above, **verbatim**, with these amendments from the design Q&A:

1. `clamp_dt` default is `time.Second / 60` (learner's call), `max_dt` default `100 * time.Millisecond`.
2. `dt_seconds` returns the **measured, clamped** dt — never a smoothed value. Smoothing is
   display-only, through `history_average`.
3. No frequency, and no conversion wrappers that duplicate `core:time`
   (`duration_seconds`/`duration_milliseconds` are used directly by callers).

Tests bind to the signatures and the per-operation contract table above.
Stubs: `katas/timing/timing.odin` · tests: `katas/timing/timing_test.odin`.

**Amended 2026-07-27 (review finding 3):** the read-only queries take a **pointer**, not a value
— `dt_seconds`, `elapsed_seconds`, `frame_deadline` take `^Frame_Clock`; `history_average`,
`history_min`, `history_max` take `^Frame_History`. `Frame_Clock` is ~888 B (824 B of it the
history), so by-value queries copied the whole window to read one number. Tests updated to match.
The contract table is otherwise unchanged — in particular a zero-length frame (`now == prev`)
remains **legal**: `dt = 0`, one 0-sample pushed.
