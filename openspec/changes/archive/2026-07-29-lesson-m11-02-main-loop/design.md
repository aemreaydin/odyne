# Interface design

> **Interface:** learner-designed — rationale: the *physics* is fixed (a fixed dt reaching the simulation, bounded catch-up, alpha published every frame, sim time derived not accumulated, the layering law) because those are not opinions. Everything above it is: where the graduated clock lives and what the package is called, who owns the `for`, what the once-per-frame call returns, which catch-up bound you use and what happens to refused time, who consumes input edges when a frame runs zero or two steps, and whether the game timeline arrives now. These are the decisions the renderer (m20–m23) and Breakout (m33) will be built on top of, so make them deliberately.

## Learner sketch

<!-- [you] Your proposed design. Rough is fine — this starts the conversation. Signatures plus
     short ownership/lifetime notes. Address at least:

       - PLACEMENT & NAMES: where does the graduated timing code go (path + package name —
         `package time` collides with `core:time` wherever both are imported, so decide
         deliberately), and where does the LOOP live? Give the layering argument
         (core → platform → render → game, downward only), not just the path.

       - WHO OWNS THE `for`: app-owned loop calling down, or an engine driver taking
         callbacks as proc pointers [SDL SDL_AppIterate], [SOKOL sokol_app.h]? If a driver
         below `game` runs the loop, how does it pump platform events and call game code
         without importing upward?

       - PACER STATE & API: does it own a Frame_Clock or take one? What does the
         once-per-frame call return — a step count to loop over, a "next step?" query, or a
         struct with steps + alpha? What type is alpha, and where is it computed?

       - SIM RATE: which rate, in what representation? 60 Hz is 16,666,666.67 ns (inexact);
         50/64/100/125 Hz are exact in ns. Compile-time constant or configurable at init?
         What is sim_time and how is it derived (not accumulated)?

       - CATCH-UP BOUND: m11-01's dt clamp (max_dt/clamp_dt), a step cap, or both — and say
         what each protects against that the other doesn't [UNITY-TIME maximumDeltaTime],
         [GAFFER-TIMESTEP], [UE-SUBSTEP]. What happens to the leftover accumulator when the
         bound trips, and what does that do to simulated time?

       - INPUT SEAM: what happens to a keypress that arrives during a 0-step frame, and to
         one that arrives on a frame that runs two steps? Whose code changes — platform, the
         loop, or the app? (m10-02 retires edges once per PUMP; steps are 0..N per pump.)

       - LIMITER POLICY: target rate configurable / off by default? Does the loop own
         frame_deadline and the tick wait_until returns, or does the app? Spin margin on
         WINDOWS specifically, and is timeBeginPeriod the engine's business, the platform
         layer's, or nobody's [MS-TIMEPERIOD], [SDL SDL_HINT_TIMER_RESOLUTION]?

       - PAUSE / SCALE: m11-01 deferred the game timeline to here [GEA §8.4]. Now, or
         deferred again with a reason and a forecast of who needs it first? If now: does
         pause zero the dt or stop feeding the accumulator (they differ on release)?

       - INTERPOLATION: does the engine offer any help, or is publishing alpha the whole
         contract? Who owns previous-vs-current state?

       - DEMO: what the testbed shows that proves this works.

     See lesson.md §Exercise for the full brief and the fixed constraints. -->

The package should be core/time - we can reference packages with different names anyways(https://odin-lang.org/docs/overview/#packages)

WHO OWNS - can we "hide away" the main from the user - and give them callbacks to run? this is just an idea from an article I've read - just want to talk about it
With an app-owned loop, you give a lot of responsility to the user to use the API correctly - I would rather control the loop in engine - and give the user the callbacks
to fill

- PACER STATE & API - I'm thinking it should take a Frame_clock and should return a struct. Alpha should be f32

- SIM RATE: I think this should be able to be set (like physics 50, AI 2) etc. Let's talk about htis

- CATCH-UP BOUND: We already have a similar implementation to Unity maximumDeltaTime - we will implement that

- INPUT SEAM: I'm not sure about this, I feel like this should be done once every frame

- LIMITER POLICY: App should own it - the users shouldn't care about this (what they can set should be a configurable "step" maybe like the SIM RATE)

- PAUSE/SCALE: stop feeding the acc

- INTERPOLATION: This depends on where we put the for - so I'm not sure about this


## Tutor critique

Good sketch — and unusually, two of your positions are decided by the compiler rather than by
taste, so I probed both before answering. One of them says your first line can't compile. The
rest is a genuinely coherent design, and finding 6 is you being *more* right than your
one-liner argued.

**1 — `core/time` cannot be a package name in this program. Compiler-verified.**

Your citation is correct about import aliasing [ODIN Packages] — and it doesn't reach this
problem, because Odin enforces two *separate* rules and aliasing only touches the second.

*Rule 1 — package names are unique program-wide.* Probed on `dev-2026-07-nightly:819fdc7`:
a directory containing `package time`, in a program that also reaches `core:time`, fails
before anything else:

```
core/time/iso8601.odin(1:1) Error: Duplicate declaration of 'package time'
    A package name must be unique
    There is no relation between a package name and the directory that contains it …
```

No alias helps: the alias renames the *import identifier*, not the package's declared name.
And our timing code imports `core:time` itself, so the collision is unconditional.

*Rule 2 — the import identifier comes from the last path segment, not the package name.* Same
probe, second variant: directory `time/` declaring `package timing` compiles the package fine,
but `import "./time"` binds the identifier **`time`**, so a file importing both gets
`Error: Redeclaration of 'time' in this scope` and `Undeclared name: timing`. So even the
compromise (`core/time/` on disk, `package timing` inside) forces an alias at every dual-import
site *and* makes the qualifier disagree with the path.

Third variant — directory `timing/`, `package timing`, both imported in one file — builds clean
under `-vet -strict-style` and prints `5ms 1ms`. Zero friction.

**Recommendation: `engine/core/timing/`, `package timing`.** Three reasons beyond the probe:
the precedent is already in the tree (`engine/core/memory` next to `core:mem` — it works because
the name differs), the kata is *already* `package timing` so graduation is a move rather than a
rename, and `timing` is the more honest name anyway — the domain is frame timing, not calendars
and time zones, which is what `core:time` mostly is.

**2 — Engine-owned loop with callbacks: yes. Here is where it has to live, and what it costs.**

Your reasoning is the same as SDL's and sokol's, and it holds: *"should not go into an infinite
mainloop; it should do one iteration … and return"* [SDL SDL_AppIterate], [SOKOL sokol_app.h].
On iOS and in the browser it isn't even a preference — an app-owned `while(true)` cannot exist
there. Accept the goal. Now the layering law prices it.

The driver must pump `platform`, call `render`, and invoke game code. Where can it live?

- **In `core`** — illegal as written; `core` may not import `platform`. Rescuable only by
  inverting the dependency (the driver calls proc pointers it was handed), which buys you type
  erasure through `rawptr` and nil-proc crashes instead of compile errors. Don't pay that.
- **In `game`** — legal today, no tricks: `game` already imports core + platform + render, and
  `examples/testbed` sits above it. Downward-only, all the way.
- **In a new `engine/app`** above `game` — also legal, but it amends the layering law
  (`core → platform → render → game → app`) for one file's worth of code.

**Recommendation: driver in `game` (`game.run`), and split it from the pacer.** The split is the
important half: **the pacer is pure arithmetic and lives in `core/timing`; the driver is I/O and
lives in `game`.** Reasons: the pacer's tests must not need a window (m11-01 already proved what
parameter injection buys — 100,000 frames in ~0.5 ms), the driver's callback signatures *will*
change at m20-03 when `render` needs swapchain acquire/present, and a pacer that doesn't know
about callbacks survives that change untouched.

Cost of the driver you should accept knowingly: "what happens per frame, in what order" stops
being answerable by reading `main` and becomes driver-plus-callback-table; and any future
non-game loop — an asset cooker, a headless test harness, an editor with two windows — either
goes through the driver or bypasses it entirely. Callback loops are famously awkward for tools.
Mitigation, and it's cheap: keep the pacer public and usable on its own, so a tool can write its
own three-line `for`.

**3 — The pacer should take a `Duration`, not a `^Frame_Clock`.**

You proposed it takes a `Frame_Clock`. Two arguments against, one for.

Against: (a) it drags the clock into every pacer test, and the clock is already tested — the
pacer's whole contract is "given a dt, how many steps do I owe and what's the phase", which is
`i64` arithmetic; (b) it creates two candidates for "who calls `frame_start`", and the answer
must be exactly one (the driver), because "one clock read per frame" is a fixed constraint.
For: one call per frame instead of two. Not worth it — the driver is the one place that reads
the clock, and it can pass the dt down in the same statement.

If it takes `^Frame_Clock` anyway, take it *by pointer* — m11-01's review already caught an
888 B struct being copied to read 8 bytes of it.

**4 — Returning a struct: agreed, and it's the frame's timing report, not just a count.**

`f32` alpha is right for the reason m11-01 settled: gameplay and `core:math/linalg` are `f32`,
and alpha ∈ [0,1) has mantissa to spare.

The footgun in a `count`-returning API: `advance` has already drained the accumulator, so a
caller who ignores `count` silently deletes simulation time. The alternative that makes the
drain unforgeable is an iterator (`for pacer_next_step(&p) { … }` — one step consumed per
`true`). I'm recommending the struct anyway, and your driver decision is exactly why: **the
`for` over steps lives in the engine, written once, tested.** The footgun is the engine's, not
the user's. That's finding 2 paying for itself.

**5 — Multi-rate ("physics 50, AI 2"): the mechanism is free, the policy is not.**

The mechanism is a `Pacer` value you can have N of — two `i64`s and a counter, ~24 bytes,
one accumulator each. Nothing to design. What you'd be signing up for is the policy:

- **Interleaving order.** Independent accumulators give you "all AI steps, then all physics
  steps" within a frame, which is *not* the same timeline as properly interleaved steps. For
  reproducibility the order has to be defined and stable, and rates want to be integer
  multiples of each other (50 and 2 are 25:1 — fine; 50 and 3 beat against each other forever).
- **Worst-case work stops being one number.** With one pacer, the dt clamp bounds steps per
  frame (finding 6). With N, the bound is the *sum* over pacers, and each rate scales its own
  contribution differently.
- **Who owns the rate table** — that's a system-scheduling question, and it belongs with
  entities and systems (m31/m42), not with a lesson whose job is one accumulator done right.

**Recommendation: build one `Pacer` *type* that is instantiable per rate; instantiate exactly
one this lesson; build no registry, no scheduler, no rate table.** Then "AI at 2 Hz" is a
second `Pacer` field in m31 and costs nothing.

On the rate itself: making `fixed_dt` a **field** (not a compile-time constant) is right — it's
what lets tests bind to behavior instead of magic numbers, same as m11-01's `max_dt`/`clamp_dt`.
Pick the default deliberately, and notice that `time.Second/60` in Odin *is* the truncation the
lesson warned about: 16,666,666 ns, 0.67 ns/step short, ≈144 µs per hour of simulation. Harmless
— *provided* sim time is `steps × fixed_dt` — but `time.Second/50` (20,000,000 ns) and
`time.Second/64` (15,625,000 ns) are exact, and 64 Hz is the one nobody thinks of.

**6 — Catch-up bound: your answer is right, and for a better reason than you gave.**

"We already have Unity's `maximumDeltaTime`" is *nearly* true (m11-01 substitutes `clamp_dt`
when `raw_dt > max_dt`, where Unity caps at the maximum — different values out, same job), and
reusing it is the right call. The strong argument, which is worth having in your head because it
answers three of the lesson's constraints at once: **the refusal happens *before* the
accumulator.** Consequences:

- **`alpha ∈ [0,1)` holds structurally.** No cap on steps means the accumulator is fully drained
  every frame, so the remainder is always < `fixed_dt`. Add a *step cap* that keeps its leftovers
  and alpha can exceed 1 — the lesson's "alpha < 1" constraint and "keep the refused time" are
  arithmetically incompatible. Your choice sidesteps that entirely.
- **There is no refused-time policy to write.** The clock refused the time; the pacer never saw
  it. `raw_dt` keeps the hitch observable [m11-01], and sum-of-dt ≠ elapsed stays correct-by-design.
- **It is spiral-proof by construction.** Time entering the accumulator per frame is bounded by
  `max(max_dt, clamp_dt)` = 100 ms with your defaults *regardless of how long the frame actually
  took*. A frame that takes 5 seconds injects 16.7 ms. Under sustained overload the sim simply
  runs behind real time — *"the simulation will appear to slow down under heavy load"*
  [GAFFER-TIMESTEP], which is the documented, intended behaviour.

Two caveats to write down, both created by making the rate configurable:

- **Unity's invariant has an analogue here.** *"maximumDeltaTime is always at least as large as
  Time.fixedDeltaTime"* [UNITY-TIME maximumDeltaTime]. Your substituted value is
  `clamp_dt = time.Second/60` = 16.67 ms. At a 50 Hz sim (`fixed_dt` = 20 ms) a hitch frame
  therefore injects *less than one step* — the frame runs 0 steps and the remainder carries.
  Not a bug, but "pretend that hitch was one frame" stops being true the moment the rate isn't 60.
- **Your implied step cap is `max_dt / fixed_dt`** — the formula is Unity's, verbatim: it
  *"bounds the maximum number of times Unity executes MonoBehaviour.FixedUpdate in a frame to
  maximumDeltaTime / fixedDeltaTime"* [UNITY-TIME maximumDeltaTime]. With `max_dt` = 100 ms that
  is **6 steps at 60 Hz, 12 at 120 Hz**. So worst-case frame ≈ 6 × step cost + render, and it
  *doubles silently* if someone changes the rate. A step cap is the only bound that holds work
  constant under rate changes [UE-SUBSTEP Max Substeps], [DEWITTERS MAX_FRAMESKIP] — file it as
  a known extension, don't build it now.

**7 — Input seam: "once per frame" is the right instinct, but it is not yet a rule.**

`poll_events` already retires edges once per pump, so "once per frame" describes what m10-02
does — it doesn't say what the *steps* see, and that's the whole question:

- frame runs **2 steps** → both read `key_pressed(.Space) == true` → one press, two jumps;
- frame runs **0 steps** → the pump retired the press, no step ever observed it → one press, no
  jump. And 0-step frames are the *normal* case whenever the frame rate exceeds the sim rate:
  *"each frame has one fixed update or none at all"* [UNITY-TIME fixed-updates].

Your driver decision hands you the clean fix, and it's why Unity has two callbacks rather than
one: **a `frame` callback that runs exactly once per frame, where edges are live, plus `step`
callbacks that see level state only.** Edges get latched into intent by `frame`; steps consume
intent. A press during a 0-step frame stays latched into the next frame instead of vanishing; a
2-step frame consumes the latch once. `platform` doesn't change at all — the snapshot stays a
pure snapshot, which is m10-02 staying correct rather than being patched.

What I need from you is the *stated rule*, in one sentence per case, because the test will quote
it: what a press arriving during a 0-step frame does, and what the second step of a 2-step frame
sees.

**8 — "App owns the limiter" contradicts "engine owns the loop".**

If the driver owns the `for`, there is nowhere in the app to put a `wait_until` — everything
between two frames is inside `run`. What you actually want (and said, in the second half of the
same line) is **driver owns the mechanism, app owns the number**: `target_fps` in the config
struct, `0` ⇒ unlimited, spin margin a field with a default. Same rule as `fixed_dt`: fields, so
6.1's measurements can change a default without touching a test.

`timeBeginPeriod`: if anyone in odyne owns it, it's **`platform`** — `core` must stay portable,
and OS-specific code with a `#+build windows` gate is exactly what the platform layer is for.
The wrinkle worth naming in the design: the knob is Windows-specific (platform) but its
beneficiary is `core/timing`, one layer *below*. That's tolerable because process timer
resolution is **ambient process state**, not a dependency — nothing in `core/timing` references
it. Decide the owner now, decide whether to *call* it after 6.1(a) measures whether SDL already
did it for you [SDL SDL_HINT_TIMER_RESOLUTION], [MS-TIMEPERIOD].

**9 — Pause: "stop feeding the accumulator" is right. Now say what the resume frame does.**

Not feeding it is correct and has a nice property: the partial remainder is preserved, alpha
freezes, and on resume the sim continues from the same phase — no discontinuity to special-case.

But the real clock never stopped (m11-01: `elapsed = now - origin`, derived, never accumulated),
so **the first dt after resume is the entire pause.** A 30-second pause hands the accumulator a
30-second frame, and your clamp turns it into one 16.7 ms step — i.e. unpausing looks exactly
like a hitch, forever, by construction. So pause is *two* rules, not one: don't feed while
paused, **and** don't feed the resume frame's dt either (drop it, or re-base). One frame of lost
real time, invisible.

Scale (slow-mo) belongs in the same place: scale the dt **going into** the accumulator, never
the step — the step is fixed, that's the entire point. Unity states the equivalence from the
other side: *"A fixedDeltaTime of 1 second in a game with a Time.timeScale of 0.5 means fixed
updates occur every 2 seconds of real time"* [UNITY-TIME fixedDeltaTime].

And the payoff, which is why m11-01 made you derive things: `sim_time = steps × fixed_dt` is the
**game timeline** [GEA §8.4], and it stays exact through pause, resume, scale, and every hitch,
because it was never a sum of dts in the first place.

**10 — Interpolation doesn't depend on where the `for` lives.**

Publishing alpha is layer-independent; what depends on the driver is only whether there's a
`render(alpha)` callback signature — and there is. Beyond that: the *game* owns previous-and-
current state, and the engine offers no interpolation helper this lesson, because there is
nothing to interpolate yet (no transforms until m23/m43). Publishing alpha honestly, every
frame, including 0-step frames, is the whole contract. Finding 6 is what makes it safe to
promise `[0,1)`.

**11 — Demo: unanswered.** Name what the testbed shows. It's part of the definition of done for
a `build` lesson, and it's the only check that the pacing actually works on real hardware — the
tests can't see a pegged core.

### Proposed interface (pending Q1–Q7)

```odin
// ── engine/core/timing (package timing) ────────────────────────────────────────
// Graduated from katas/timing/ as-is: Frame_Clock, Frame_History, clock_init, frame_start,
// dt_seconds, elapsed_seconds, frame_deadline, history_push/average/min/max, wait_until,
// HISTORY_CAPACITY, SLEEP_CHUNK.

// Pacer — the fixed-timestep accumulator. Pure arithmetic: no clock read, no syscall, no
// allocation. One instance per fixed rate; this lesson uses exactly one.
Pacer :: struct {
	fixed_dt:    time.Duration, // the step; set at init, never written again
	accumulator: time.Duration, // unspent real time; < fixed_dt after every advance
	steps_taken: u64,           // total steps since init — the game timeline's only source
}

// Frame_Steps — one frame's timing report.
Frame_Steps :: struct {
	count: int, // steps owed this frame; 0 is legal and normal
	alpha: f32, // [0,1) — phase between the last completed step and the next
}

pacer_init    :: proc(p: ^Pacer, fixed_dt: time.Duration)
pacer_advance :: proc(p: ^Pacer, dt: time.Duration) -> Frame_Steps
pacer_alpha   :: proc(p: ^Pacer) -> f32           // the value advance last reported
sim_time      :: proc(p: ^Pacer) -> time.Duration // steps_taken * fixed_dt — derived, exact
step_seconds  :: proc(p: ^Pacer) -> f32           // fixed_dt as f32 seconds, for gameplay math

// ── engine/game (package game) — the driver ────────────────────────────────────
App_Config :: struct {
	window:      platform.Window_Desc,
	fixed_dt:    time.Duration, // 0 ⇒ default
	max_dt:      time.Duration, // clock clamp threshold; 0 ⇒ default
	clamp_dt:    time.Duration, // dt substituted on a hitch; 0 ⇒ default
	target_fps:  int,           // 0 ⇒ unlimited (limiter off)
	spin_margin: time.Duration, // 0 ⇒ default
}

// App — the read-only per-frame view handed to every callback. Handle-based: no SDL, no
// internal pointers.
App :: struct {
	window:      platform.Window_Handle,
	frame_index: u64,
	dt:          time.Duration, // clamped real delta of the frame that just ended
	steps:       Frame_Steps,   // this frame's step count + alpha
	// history stats reachable for the readout
}

App_Callbacks :: struct {
	user:     rawptr,
	init:     proc(app: ^App, user: rawptr) -> bool,
	frame:    proc(app: ^App, user: rawptr),           // ONCE per frame — input edges live here
	step:     proc(app: ^App, user: rawptr, dt: f32),  // 0..N per frame — fixed dt, level state
	render:   proc(app: ^App, user: rawptr, alpha: f32),
	shutdown: proc(app: ^App, user: rawptr),
}

run :: proc(cfg: App_Config, cb: App_Callbacks) -> Window_Error
```

Frame body inside `run`: `frame_start(clock, now)` → `poll_events` → `cb.frame` →
`advance(dt)` → `cb.step × count` → `cb.render(alpha)` → temp-allocator reset →
`wait_until(frame_deadline(...))`, whose returned tick is the next frame's `now`.

### Questions

- **Q1 — driver home and surface.** `game.run` (recommended) or a new `engine/app` layer? And
  does the driver create and own the window from `App_Config`, or does the app create it and
  hand over a handle?
- **Q2 — pacer input.** `dt: time.Duration` (recommended) or `^Frame_Clock`?
- **Q3 — rate.** Default `fixed_dt`, and which side of the exactness trade (`Second/60` with the
  144 µs/hour residue, or an exact `Second/50` / `Second/64`)? Confirm: one pacer instance this
  lesson, no rate table.
- **Q4 — the bound, in numbers.** What worst-case steps-per-frame are you buying with
  `max_dt`/`clamp_dt`, and what relation do you want between `clamp_dt` and `fixed_dt` now that
  the rate is a field?
- **Q5 — the input rule, both cases.** One sentence each: a press arriving during a 0-step
  frame; the second step of a 2-step frame.
- **Q6 — pause/scale this lesson, or deferred again?** If now: the resume rule.
- **Q7 — demo.** What the testbed shows, including how a deliberate ~2 s hitch is made visible.

## Design Q&A — round 2

Learner answers: `timing` ✔ · driver in `game` ✔ · pacer takes a `Duration` ✔ · struct return ✔ ·
one `Pacer` type, one instance ✔ · limiter (driver owns mechanism, app owns number) ✔ · pause
rules ✔ · alpha-only, no interpolation helper ✔. Open: **the finding-6 caveats** (learner: "let's
talk and decide") and **the input seam** (learner: "I still don't understand this"). Tutor
decides the three leftovers (window ownership, pause scope, demo).

### The input seam, from the top

The thing to hold onto: **today, "once per frame" and "once per step" are the same sentence.**
The testbed's loop is one iteration = one update, so there is no distinction to get wrong.
m11-02 breaks that identity — a frame now runs 0, 1, or 2+ steps — and every input assumption
built on the old identity silently changes meaning. That's all this is.

**Case A — the 0-step frame (input vanishes).** Sim at 60 Hz (`fixed_dt` = 16,666,666 ns),
display at 144 Hz (frame period 6,944,444 ns). Trace the accumulator through ten frames:

| frame | acc after deposit | steps | acc left |
|---|---|---|---|
| 1 | 6.94 ms | **0** | 6.94 ms |
| 2 | 13.89 ms | **0** | 13.89 ms |
| 3 | 20.83 ms | 1 | 4.17 ms |
| 4 | 11.11 ms | **0** | 11.11 ms |
| 5 | 18.06 ms | 1 | 1.39 ms |
| 6 | 8.33 ms | **0** | 8.33 ms |
| 7 | 15.28 ms | **0** | 15.28 ms |
| 8 | 22.22 ms | 1 | 5.56 ms |
| 9 | 12.50 ms | **0** | 12.50 ms |
| 10 | 19.44 ms | 1 | 2.78 ms |

Four steps in ten frames (60/144 = 0.417 — correct), and **six of the ten frames ran zero
steps.** Now put a keypress on frame 4. `poll_events` records it; `key_pressed(.Space)` is true
during frame 4 and *only* frame 4, because frame 5's pump calls `retire_input`. Frame 4 ran no
steps. So if the jump lives in `step`, **no step ever executed while the edge was visible** —
the press is gone. Not "delayed": gone. At these rates that's a 60% chance per press, which is
the shape of the bug report "sometimes my jump doesn't register."

**Case B — the 2-step frame (input duplicates).** Same sim, display at 30 Hz (frame period
33,333,333 ns). Deposit 33,333,333 into an empty accumulator: step (16,666,667 left), step
(1 left) — **every frame runs exactly two steps.** `key_pressed` is true for the whole frame, so
both steps see it. A jump impulse applied in `step` is applied twice. The player jumps twice as
high, and only on slow machines.

Neither package is wrong. `platform` promised "true for one frame after the press" and delivered
it; the pacer promised "0..N steps" and delivered that. The bug is that *"one frame"* and
*"one step"* stopped being the same unit, and nobody was told.

**The rule that fixes both, and why it's the only one that can.** An edge must be read exactly
once per *frame*, and consumed exactly once by a *step*. Those are two different moments, so
something has to hold the value between them — a latch:

1. `frame` runs **once per frame, before any step**, and is the only place that reads
   `key_pressed`/`key_released`. It converts edges into **intent** (`intent.jump = true`).
2. `step` never reads edges. It reads level state (`key_down`) and intent.
3. The first step that acts on an intent **clears it**.

Replay the cases. Frame 4 (0 steps): `frame` latches `intent.jump = true`; no step runs; the
latch is still set on frame 5, whose step consumes it. Press honoured, late by <1 step (≤16.7 ms),
which is below the interpolation latency you already accepted. 30 Hz frame (2 steps): step 1
consumes and clears, step 2 sees `false`. One press, one jump.

Now the instructive part — the *other* candidate fix, "give the edges to the first step only,"
is the same idea implemented one layer down, and **it cannot handle case A**: a 0-step frame has
no first step to give them to. That asymmetry is why the latch has to live above the step loop,
i.e. in the once-per-frame callback. This is exactly why Unity ships both `Update` and
`FixedUpdate` rather than one callback [UNITY-TIME fixed-updates] — the split isn't ceremony,
it's the only place the latch can go.

**Where the latch lives: the game, not the engine.** "Jump" is a game concept; the engine has no
idea what intents exist. The engine's entire contribution to this seam is an *ordering
guarantee* — `frame` runs exactly once per frame, before any `step`; `step` runs 0..N times with
a fixed dt — which costs the engine nothing and is testable. That guarantee is what goes in the
spec delta. The latch itself is testbed code you write in `frame`.

One honest limitation to note while we're here: `Button_State` keeps a `half_transitions` count,
but the public query is a **bool** (`key_pressed` = `half_transitions >= 2 || (== 1 && ended_down)`),
so "the player tapped twice inside one frame" is not representable through today's API — both
taps collapse to one `true`. The information exists in the struct; exposing a count is a
platform-layer decision for a later lesson, not this one.

### Finding 6 — the caveats, decided with numbers

**Caveat A: `clamp_dt` vs `fixed_dt`. Resolution: the driver derives `clamp_dt = fixed_dt` by
default.** Today they are already the same number — `time.Second/60` is 16,666,666 ns and so is
a 60 Hz step — so nothing changes now; the derivation is what keeps it true when the rate moves.
The driver is the one place that knows both the clock and the pacer, so it is the right place for
the coupling, and it stays a config field the app can override. Semantics stay m11-01's:
*"pretend that hitch was one simulation step."*

Also enforced at init, borrowed verbatim from Unity: **`max_dt ≥ fixed_dt`** [UNITY-TIME
maximumDeltaTime]. It catches the degenerate config where the sim rate is so high that the clamp
threshold sits below one step.

**Caveat B: the implied step cap. Resolution: `max_dt` stays an absolute 100 ms, and the cap is
documented rather than enforced.** The arithmetic, so it's on the record:

- Worst-case catch-up = `floor(max_dt / fixed_dt)` = **6 steps at 60 Hz**, 12 at 120 Hz,
  3 at 30 Hz. With today's empty simulation, 6 steps cost ~0.
- Curiosity worth keeping, and it's a point in your inherited design's favour: because m11-01
  *substitutes* instead of capping, the worst catch-up comes from a **medium** hitch (just under
  100 ms → 6 steps), not a huge one (2 s → dt becomes one step → **1 step**). Unity's cap
  semantics would hand you 6 steps for *every* big hitch. Substitution is strictly gentler.

I considered the tidier-looking alternative — derive `max_dt = N × fixed_dt`, which holds
worst-case *work* constant under rate changes — and rejected it, because it inverts which hazard
you're protected from. The two hazards are not equally dangerous:

- **Too-low `max_dt` clamps normal frames** → the game runs in permanent slow motion and nothing
  reports it. m11-01 already flagged this exact trap ("a 16 ms threshold clamps every frame").
  A derived `max_dt` at a 240 Hz sim rate with N=4 is 16.7 ms — below normal 60 fps jitter. Silent.
- **Too-high `max_dt/fixed_dt` makes a hitch frame long** → visible, measurable, and self-limiting
  (the next frame's dt gets clamped).

So: absolute bound guards the invisible failure; the **step cap is the tool for the visible one**,
and it is a deferred extension whose trigger condition is worth writing down — reach for it when
`worst_case_steps × step_cost` starts approaching the frame budget, i.e. as soon as the
simulation does real work. Not now. Refused time stays refused *upstream of the accumulator*,
which is what keeps `alpha ∈ [0,1)` structural.

### Tutor decisions on the three leftovers

- **Q1, window ownership: the driver creates and owns one window** from `App_Config.window` and
  publishes the handle on `App`. `run` has to call `poll_events`/`should_close` anyway, so it
  needs the handle regardless, and "the user shouldn't care" was your stated goal. Nothing is
  hidden: `platform.create_window` stays public, so an app wanting a second window still can.
- **Q6, pause scope: in, this lesson, and it costs one field.** The pacer needs *nothing* — pause
  is "the driver doesn't feed it", which is the absence of a call. So: `App.paused: bool`, set by
  the game from `frame`; while paused the driver feeds nothing; **the resume frame's dt is
  dropped** (rule two, without which unpausing is a 30-second hitch). Time *scale* stays out —
  no consumer yet, and it's one multiply when one arrives. What gets tested is the pacer-level
  truth: `advance(0)` → 0 steps, alpha unchanged, `sim_time` unchanged.
- **Q7, demo readout:** one line, refreshed every frame (title bar, `tprintf` + per-frame
  `free_all(context.temp_allocator)` as today):

  ```
  f 12345 | 16.7ms (avg 16.6 min 16.1 max 31.2) | 60.1 fps | steps 1 | a 0.43 | sim 205.3s real 205.4s
  ```

  Plus three keys, each proving one claim the tests cannot:
  - **Esc** — closes, same path as ✕ (unchanged from m10-02).
  - **P** — toggles pause. `f` and `real` keep advancing, `sim` freezes, `steps` reads 0, and
    unpausing does **not** fast-forward. That's the two-timelines idea [GEA §8.4] on screen.
  - **H** — hold to inject a real hitch (`time.sleep(2 * time.Second)` inside `frame`). Proves
    the clamp absorbs it: `steps` stays ≤ 1, `sim` advances by one step, the app neither freezes
    nor fast-forwards, and `max` in the history shows the 2 s spike while `avg` recovers.
  - **L** — toggles `target_fps` between 60 and 0 (unlimited), so the fps readout and Task
    Manager's CPU column tell the pacing story live. m10-01's ~5.4 M idle pumps/second is the
    baseline being killed here, and CPU occupancy is the one observation no test can make.

### Confirm to unblock

Two yeses and I record the agreed interface, then write the spec delta, stubs and red tests:

1. **Finding 6 as resolved above** — `clamp_dt = fixed_dt` derived, `max_dt` absolute at 100 ms
   with `max_dt ≥ fixed_dt` asserted, worst-case 6 steps at 60 Hz documented, step cap deferred.
2. **The input rule** — `frame` (once, edges → intent) + `step` (0..N, level state + intent,
   first step clears), latch owned by the game, engine guarantees only the ordering.

Also still needed from you, one line: **the default sim rate.** `Second/60` (16,666,666 ns,
144 µs/hour behind an exact 60 Hz) or an exact-in-ns rate (`Second/50` = 20 ms, `Second/64` =
15,625,000 ns). Every other number is a field with a default, so this one is just the default.

## Agreed interface

Locked 2026-07-28. The proposed interface above, with the round-2 resolutions folded in and
one decision from the learner: **`DEFAULT_FIXED_DT = time.Second/50` — 20,000,000 ns, exact in
nanoseconds**, so the 60 Hz residue does not exist in this engine at all.

Consequences of 50 Hz worth having on the record before the tests bind to them:

- `clamp_dt` defaults to `fixed_dt` = **20 ms** (derived, caveat A), so a hitch is "one
  simulation step" at whatever rate is configured.
- Worst-case catch-up = `floor(max_dt / fixed_dt)` = `floor(100/20)` = **5 steps**.
- At a 60 fps display, 20 ms > 16.67 ms, so **~17% of frames run zero steps** and ~83% run one.
  0-step frames are not an exotic case here; they are one frame in six on the developer's own
  machine. The input latch is load-bearing from day one.

```odin
// ══ engine/core/timing (package timing) ═════════════════════════════════════════
// Graduated from katas/timing/ with signatures UNCHANGED: Frame_Clock, Frame_History,
// clock_init, frame_start, dt_seconds, elapsed_seconds, frame_deadline, history_push,
// history_average, history_min, history_max, wait_until, HISTORY_CAPACITY, SLEEP_CHUNK.
// Directory `engine/core/timing/`, package `timing` — NOT `time` (compiler probe, finding 1).

DEFAULT_FIXED_DT :: time.Second / 50 // 20,000,000 ns — exact in ns; 60 Hz is not

// Pacer — the fixed-timestep accumulator. Pure arithmetic: no clock read, no syscall, no
// allocation, no platform. One instance per fixed rate.
Pacer :: struct {
	fixed_dt:    time.Duration, // the step; set by pacer_init, never written again
	accumulator: time.Duration, // unspent real time; always < fixed_dt after an advance
	steps_taken: u64,           // total steps since init — the game timeline's ONLY source
}

// Frame_Steps — one frame's timing report.
Frame_Steps :: struct {
	count: int, // steps owed this frame; 0 is legal and normal
	alpha: f32, // [0,1) — phase between the last completed step and the next
}

pacer_init    :: proc(p: ^Pacer, fixed_dt: time.Duration = DEFAULT_FIXED_DT)
pacer_advance :: proc(p: ^Pacer, dt: time.Duration) -> Frame_Steps
pacer_alpha   :: proc(p: ^Pacer) -> f32           // == the value the last advance reported
sim_time      :: proc(p: ^Pacer) -> time.Duration // steps_taken * fixed_dt — derived, exact
step_seconds  :: proc(p: ^Pacer) -> f32           // fixed_dt as f32 seconds, for gameplay math
```

**Pacer contract** (what the tests bind to):

| call | contract |
| --- | --- |
| `pacer_init(p, fixed_dt)` | `fixed_dt > 0` (assert). Zeroes `accumulator` and `steps_taken`. |
| `pacer_advance(p, dt)` | Requires `dt >= 0`. Deposits `dt`, then consumes whole steps while `accumulator >= fixed_dt`, counting them. Returns the count and the resulting alpha. |
| — conservation | `sum(all dt fed) == steps_taken * fixed_dt + accumulator`, **exactly**, forever. |
| — `alpha` | `accumulator / fixed_dt` as `f32`, always in `[0,1)`; `1.0` is unreachable because a full step would have been consumed. |
| — `dt == 0` | 0 steps, alpha unchanged, `sim_time` unchanged. This is what pause is. |
| `sim_time(p)` | `steps_taken * fixed_dt`. Derived, never accumulated — exact through pause, hitches and clamps. |

```odin
// ══ engine/game (package game) — the driver ══════════════════════════════════════
DEFAULT_MAX_DT      :: 100 * time.Millisecond // m11-01's clamp threshold
DEFAULT_TARGET_FPS  :: 60
DEFAULT_SPIN_MARGIN :: 1 * time.Millisecond   // revisit after 6.1(a) measures Windows

App_Config :: struct {
	initial_window: platform.Window_Desc, // as REQUESTED at creation; client_size(h) is the truth after
	fixed_dt:       time.Duration, // 0 ⇒ timing.DEFAULT_FIXED_DT
	max_dt:         time.Duration, // 0 ⇒ DEFAULT_MAX_DT
	clamp_dt:       time.Duration, // 0 ⇒ fixed_dt  (derived — round 2, caveat A)
	target_fps:     int,           // 0 ⇒ DEFAULT_TARGET_FPS
	unlimited:      bool,          // true ⇒ limiter off, target_fps ignored
	spin_margin:    time.Duration, // 0 ⇒ DEFAULT_SPIN_MARGIN
}

// App — the loop's state AND the view handed to every callback (see amendment 1).
App :: struct {
	cfg:    App_Config,         // resolved: no zeroes-mean-default left; live knobs read from here
	window: platform.Window_Handle,
	clock:  timing.Frame_Clock, // the real timeline
	pacer:  timing.Pacer,       // the game timeline
	steps:  timing.Frame_Steps, // THIS frame's report; the pacer does not keep it
	paused: bool,               // while set: nothing is fed to the pacer; the resume frame's dt is dropped
}

App_Callbacks :: struct {
	user:     rawptr,
	init:     proc(app: ^App, user: rawptr) -> bool, // false ⇒ run returns .Init_Callback_Failed
	frame:    proc(app: ^App, user: rawptr),         // EXACTLY once per frame, before any step
	step:     proc(app: ^App, user: rawptr, dt: f32), // 0..N per frame; dt is always fixed_dt
	render:   proc(app: ^App, user: rawptr, alpha: f32), // exactly once per frame, after the steps
	shutdown: proc(app: ^App, user: rawptr),
}

App_Error :: enum {
	None,
	Init_Failed,           // platform.init failed
	Window_Failed,         // window creation failed
	Init_Callback_Failed,  // the game's init returned false
}

run :: proc(cfg: App_Config, cb: App_Callbacks) -> App_Error
```

**Driver contract:**

1. `run` owns platform init, one window from `cfg.window`, the `Frame_Clock`, the `Pacer`, the
   limiter, and shutdown. Every callback is optional — a zero-value `App_Callbacks` runs and
   exits cleanly.
2. **Ordering, per frame, invariant:** `frame_start` → `poll_events` → `frame` (once) →
   `advance` → `step` × `count` → `render` (once, with `alpha`) → temp-allocator reset →
   `wait_until(frame_deadline)`, whose returned tick is the next frame's `now`. **One clock
   read per frame.**
3. **The input rule** the ordering exists to serve: `frame` is the only place edges
   (`key_pressed`/`key_released`) may be read; it latches them into game-owned intent. `step`
   reads level state and intent, and the first step to act on an intent clears it. The engine
   guarantees the ordering; the latch is game code.
4. `max_dt >= fixed_dt` asserted at init (Unity's invariant [UNITY-TIME maximumDeltaTime]).
5. Loop exits when the window reports close-requested; `shutdown` then runs; the window and
   platform are torn down even on an error path.
6. Limiter: `unlimited` ⇒ no wait at all. Otherwise the frame never ends before its deadline.

### Amendment 1 — `App` holds the owners, not copies of them (learner-raised, 2026-07-28)

The tutor's first `App` flattened eleven fields out of `Frame_Clock` and `Pacer`
(`dt`, `raw_dt`, `elapsed`, `frame_index`, `frame_avg/min/max`, `sim_time`, `fixed_dt`) into a
per-frame value view, to keep engine state unreachable from game code. The learner called the
duplication: those fields already have owners. Sustained, and the amendment above is the result.

What the copies were costing:

- **Two sources of truth**, reconciled by a publish step that has to be edited every time
  `Frame_Clock` grows a field — the C++ view-model/DTO habit, which Odin does not reward.
- **The loop paying for the overlay.** `history_min`/`history_max` are O(capacity) scans (12.5 ns
  each, measured in m11-01), so publishing them every frame spends ~25 ns/frame on numbers only a
  debug readout reads. Computed on demand they cost nothing when nobody asks.
- The encapsulation was not even complete: `steps: timing.Frame_Steps` already put a `timing` type
  in the callback signature, so the game imports `timing` either way.

What the amendment gives up, stated plainly rather than glossed: Odin has no `const` and
`@(private)` is per-declaration, not per-field, so a game **can** write `app.clock.origin` and
corrupt real time. The doc comment on `App` is the only guard. That trade — *enforced but
duplicated* vs *single truth but writable* — goes to single truth here because `Frame_Clock` was
designed as a plain struct its caller owns (which is exactly how a hand-rolled loop would use it),
whereas `platform` hides `Window_State` for a different reason: shared state with handle
validation, where a stale handle must be caught rather than trusted.

Two consequences folded in: keeping the **resolved** config on `App` removes the separate
`unlimited` field (both live knobs now sit in `cfg`, which is what the demo's `L` key wants), and
`App_Config.window` became **`initial_window`** because a retained desc stops being true the
moment the user resizes.

Tutor updated the stub and the 7 tier-2 cases; the pacer is untouched by this.

### Amendment 2 — the driver's file is `app.odin`, and its error is `App_Error` (learner-raised, 2026-07-28)

The learner accepted the callback names but flagged the placement: `App_Callbacks` sat in
`loop.odin`, which implies `init` and `shutdown` are loop-scoped when their cadence is once per
`run`. Sustained. `run` owns platform init, the window, the loop *and* teardown — "loop" names one
phase of that — and the repo already names files after their type family (`window.odin` →
`Window_*`, `input.odin` → `Key`/`Input_State`). So: `engine/game/app.odin`, holding `App_Config`,
`App`, `App_Callbacks`, `App_Error` and `run`.

`Loop_Error` → **`App_Error`** for the same reason, volunteered: none of its members
(platform-init failure, window failure, init-callback failure) is a *loop* error — they are all
startup errors, and the name now matches `platform.Window_Error`'s pattern.

If the per-frame body later grows enough to want its own file (m20-03's swapchain acquire/present,
m23-03's overlay), splitting a `loop.odin` back out is cheap and the name will be honest then,
because it will hold only per-frame code.

### Amendment 3 — the limiter uses a one-frame-old anchor (2026-07-29)

**Found by test, not by reading.** `loop/limiter_can_be_re_enabled_mid_run` measured a **353 ms stall**
at a 16.67 ms target after only 20 unpaced frames. Cause: `timing.frame_deadline` answers
`origin + (frame_index + 1) * period`, an absolute grid that is only meaningful while *every* frame
has been paced to it. Unpaced frames advance `frame_index` without spending wall time, so 20 of
them consumed 20 × 16.67 ms = 333 ms of grid while spending ~1 ms of reality; the first paced frame
then waited for the difference. In the testbed, holding the limiter off for a few seconds at
~1000 fps put ~50 s on the deadline, which Windows painted as a hung application.

The same root cause breaks a **live `target_fps` change** — raising the rate respaces every past
frame retroactively, putting the deadline far in the past and silently suspending pacing until real
time catches up. That corrects a claim the tutor made earlier ("computing `period` per frame keeps
`target_fps` a safe live knob"): it does not, on an origin-anchored grid.

**Decision: anchor the deadline on the current frame's start** — `clock.prev + period`, where
`clock.prev` is set by `frame_start`. Nothing older than this frame is remembered, so there is no
state that can go stale: toggling the limiter, changing the rate, or suspending the machine all
resolve within one period. This is Handmade Hero's `targetSecondsPerFrame` shape [HMH day 18].

**What it costs, stated rather than glossed:** overshoot is no longer corrected. On an
origin-anchored grid a late frame is absorbed by the next one; here each frame is
`period + overshoot`, so the achieved rate settles marginally *below* target and cumulative
slippage against an ideal schedule grows without bound. That is the property m11-01 built the grid
for, and it is being given up knowingly, for three reasons: nothing in odyne consumes an absolute
frame schedule; a rate 0.1% under target is invisible where a multi-second stall is not; and from
m20-03 the swapchain's present mode owns pacing anyway [VKSPEC], at which point this limiter is the
uncapped-presentation fallback. Task 6.1(b) now measures the slippage instead of assuming it.

**Rejected alternatives**, both viable and both more machinery than this needs today:

- *Re-anchoring grid* — keep the absolute grid but store the limiter's own anchor tick and anchor
  frame index, re-anchoring whenever pacing is enabled or the period changes, plus a plausibility
  guard for the causes nobody enumerates (suspend/resume). Keeps drift correction *within* an
  uninterrupted run. This is `MAX_FRAMESKIP` generalised [DEWITTERS]. Reach for it if an absolute
  schedule ever acquires a consumer — replay determinism against wall time, or audio-clock sync.
- *Presentation timestamps* — hand the target time to the presentation engine instead of waiting on
  the CPU, as Swappy does with `VK_GOOGLE_display_timing` and sync fences [ANDROID-PACING],
  [UE-PACING]. Not available without a swapchain; revisit at m20-03.

`timing.frame_deadline` is left in place and unchanged: its contract is correct as written, it is
still the right tool under uninterrupted pacing, and it stays covered by its own m11-01 tests. Worth
a one-line note in its doc comment recording that the loop deliberately does not use it, and why.

**⚠️ Constitution note — the tutor wrote this implementation.** The learner reached rung 3 (the
three options, in prose, with trade-offs), then explicitly requested and granted permission for the
solution, which is rung 4 of the hint ladder. Two lines of `run` and the doc comment above them are
tutor-authored; everything else in the loop is the learner's. Recorded here and in the review's
tutor self-check. What was given up: writing the fix that a test had already localised — the
cheapest possible debugging rep. The compensating exercise, if wanted, is to implement the
re-anchoring grid alternative and make both pass the same test.

### Amendment 4 - review findings, and who fixed them (2026-07-29)

Review 5.1 raised seven findings. The learner asked the tutor to fix all of them; the tutor flagged
that two carried the lesson's remaining learning content and handed those back; the learner
reaffirmed the request, and the tutor then implemented everything. Recorded here because the
constitution's first rule is that the tutor does not implement the learner's work, and this is the
second and larger departure from it in this lesson (amendment 3 was the first).

Tutor-authored fixes: the `target_fps > 0` guard; deleting the dead `get_paused`/`set_paused`;
hoisting `step_seconds` out of the step loop; `App.steps` now written on paused frames as
`{count = 0, alpha = pacer_alpha(...)}`; `render` reading `app.steps.alpha` instead of recomputing
it; and `clock_init` moved out of `init` into `run`, after `cb.init`, sharing one clock read with the
first `frame_start`. Tutor-authored tests pinning them: the paused-frame report assertion and
`loop/init_failure_aborts_the_loop`.

Two of those carried content worth having written by hand, and it should be visible what was lost:

- **`App.steps` on a paused frame** turns on a decision, not a mechanic: `count` must be 0 while
  `alpha` must stay exactly where it was, because alpha is what the renderer interpolates with and
  snapping it to zero jerks the picture back a full step at the moment of pausing. Zeroing the
  struct is the intuitive move and it is wrong.
- **Moving `clock_init`** has a second read hiding beside it. Reordering alone leaves a gap between
  two `tick_now()` calls that lands in frame 1's `dt`; the correct fix collapses them into one,
  which makes frame 1's dt exactly 0 - legal by contract, and the reason m11-01 needed no
  first-frame special case.

Learner-authored, for the record: the pacer, `run`'s structure and lifecycle, the pause guard, the
f64 phase division, the period conversion, the testbed and its lerp. Tutor-authored: the two
limiter lines (amendment 3), the readout's fps and state flags, and the six fixes above.

**Deferred, deliberately, with the trigger written down:** a per-frame **step cap** (reach for it
when `worst_case_steps × step_cost` approaches the frame budget — today `step_cost ≈ 0`); **time
scale** (one multiply, when a consumer exists); **multi-rate pacers** (the type already supports
N instances; the rate *table* is m31/m42 work); **`timeBeginPeriod`** (owner named — `platform`
— call decided after 6.1(a) measures whether SDL already did it); **exposing multi-tap counts**
through the platform input API (`half_transitions` exists; the public query is a bool).



<!-- The final signatures tests and the spec delta will be written against.
     Tests MUST NOT exist before this section is filled. -->
