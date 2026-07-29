# Lesson: m11-02/main-loop — The main loop & fixed timestep

> **Type:** build · **Module:** m11 Timing & main loop · **Interface:** learner-designed (the constraints below fix the *physics* — a fixed dt reaching the simulation, bounded catch-up, an exposed interpolation alpha, sim time derived rather than accumulated, the layering law; the placement, the API shape, who owns the `for`, and every policy number are yours to design in `design.md`)

## Goals

- **Graduate `katas/timing/` into `engine/`** — the frame clock, the history, and the waiter stop being a kata and become an engine capability with a spec delta, which forces the question the kata could dodge: which layer does time belong to, and what is the package called.
- Understand why the **real dt must never reach the simulation**, and build the **fixed-timestep accumulator** that stands between them: the renderer produces time, the simulation consumes it in equal steps [GAFFER-TIMESTEP].
- Build the **catch-up bound** that keeps a 2-second hitch from becoming a hang, and know the two shapes the industry ships it in — clamp the incoming dt [UNITY-TIME maximumDeltaTime] or cap the steps per frame [UE-SUBSTEP], [DEWITTERS].
- Expose the **interpolation alpha** so rendering can draw *between* two simulation states instead of snapping to the last one, and understand what that costs you (a frame of latency) and buys you (no microstutter when the sim rate and the display rate disagree).
- Settle the seam this lesson cannot avoid: **input edges across a variable number of steps.** A frame that runs two steps sees one keypress twice; a frame that runs zero steps never sees it at all. m10-02 built the edge detector; m11-02 decides who consumes the edges.
- Replace the testbed's **busy-spin** with a real paced loop, and find out what Windows does to your 1 ms sleep when nobody has called `timeBeginPeriod` [MS-TIMEPERIOD].

## Prerequisites

- **m11-01 (timing)** — you have `Frame_Clock` (dt, raw_dt, elapsed, frame_index, clamp policy), `Frame_History` (avg/min/max), `frame_deadline`, and `wait_until`. This lesson is what they were for. Re-read your own `design.md`: you deferred pause/scale and half-deferred spike policy to "the main loop". The main loop is here.
- **m10-01/m10-02 (window & input)** — `platform.poll_events`, `should_close`, and the frame-coherent input snapshot whose edges (`key_pressed`/`key_released`) are retired once per pump.
- **m01-01 (skeleton)** — the layering law, `core → platform → render → game`. It is about to bite: a loop that lives in `core` and calls `platform.poll_events` is an upward import.

## Explanation

### The loop is where the architecture becomes visible

Everything the engine does, it does because the loop called it. Nystrom states the pattern's purpose as *"Decouple the progression of game time from user input and processor speed"*, and gives it two jobs: *"it processes user input, but doesn't wait for it"* and *"it runs the game at a consistent speed despite differences in the underlying hardware"* [GPP-LOOP]. The second job is the whole lesson — "consistent speed" is not something you get by measuring dt and multiplying.

Before any of that, though, a structural question: **who owns the `for`?** Two answers ship in production:

1. **The app owns it.** `main` runs a `for` loop and calls down into the engine. This is what your testbed does today, and what Handmade Hero does [HMH day 18].
2. **The platform owns it and calls you back.** SDL3 offers exactly this: with `SDL_MAIN_USE_CALLBACKS`, `SDL_AppIterate` is *"called repeatedly by SDL after SDL_AppInit returns SDL_APP_CONTINUE"* and it *"should not go into an infinite mainloop; it should do one iteration of whatever the program does and return"* [SDL SDL_AppIterate]. sokol_app is built the same way [SOKOL sokol_app.h]. There is a real reason for this shape: on some platforms (iOS, and the browser, where the OS or the JS event loop owns the frame pump) an app-owned `while(true)` is not allowed to exist.

Note what the second answer does to the layering law. An engine-owned `run()` that calls `game.update()` is an **upward** dependency — `core` (or `platform`) reaching into `game` — and the layering law forbids it. There are only two ways out: keep the `for` at the top layer, where calling downward is legal; or invert the dependency and pass the callbacks *in* as proc pointers, so the lower layer calls a value it was handed rather than a package it imports. Both are legitimate; they are not the same architecture, and the choice is yours to make and defend in `design.md`.

> **C++ delta — the `Engine` base class.** The C++ instinct here is `class Engine { void Run(); virtual void OnUpdate(float dt); }` and a `Game : public Engine` that overrides. That is inversion-of-control by inheritance, and it hides the frame's shape inside a base class: "what happens per frame, in what order" is answerable only by reading `Engine::Run` plus every override plus the vtable. Odin has no inheritance to reach for, which is a feature here — the two shapes left are a flat `for` at the top (read it top to bottom, it *is* the frame) or an explicit struct of proc pointers (the callbacks are data you can print, swap, or fill with test doubles). If you want the callback shape, you write down the struct, and that is honest.

### A real dt is a bug generator

Your `Frame_Clock` hands you the measured delta. The temptation is to feed it straight to gameplay: `position += velocity * dt`. Fiedler's article exists because that does not work: *"The problem is that the behavior of your physics simulation depends on the delta time you pass in"*, and *"it's utterly unrealistic to expect your simulation to correctly handle any delta time passed into it"* [GAFFER-TIMESTEP]. Concretely, with a variable dt:

- **Integration error varies with frame rate.** Explicit Euler under gravity lands your jump at a different height at 144 fps than at 60 — same code, same input, different game.
- **Stiff systems explode.** A spring or a constraint solver has a stability limit in dt; exceed it once during a hitch and the simulation does not "run slowly", it detonates.
- **Collisions tunnel.** A big dt moves a fast object through a thin wall in one step, because the swept interval was never tested.
- **Nothing reproduces.** Nystrom's objection is the sharper one: *"we've made the game non-deterministic and unstable"* — float rounding differs per machine and per frame-rate history, so a replay does not replay and a lockstep netcode peer diverges [GPP-LOOP].

The fix is not "make the simulation robust to any dt" — it is to **stop giving the simulation a variable dt at all**. Fiedler's viewpoint flip: *"the renderer **produces time** and the simulation **consumes it** in discrete dt sized steps"* [GAFFER-TIMESTEP]. The loop measures real time (m11-01's job), banks it, and spends it in fixed-size units. Both required readings give this in code — read them; the shape is short, and the design decisions around it are what you will actually spend this lesson on.

### The leftovers are the interesting part

Real frames never divide evenly into fixed steps, so after spending what you can, a remainder is left in the bank. Two consequences fall out of that one fact.

**First, the step count per frame varies** — 0, 1, 2, sometimes more. Unity describes exactly this from the user's side: *"a fixed update always needs a frame to run in and the duration of a frame and the length of the fixed time step are not in perfect sync"*, so at high frame rates *"each frame has one fixed update or none at all"*, and at low ones *"each frame has one or more fixed updates"* [UNITY-TIME fixed-updates]. **Zero-step frames are normal, not an error.** Any per-frame logic that assumes "at least one step happened" is wrong.

**Second, the remainder is a phase, and it is exactly what rendering needs.** Fiedler: *"We can use this remainder value to get a blending factor between the previous and current physics state simply by dividing by dt"* [GAFFER-TIMESTEP]; Nystrom hands it to the renderer as `render(lag / MS_PER_UPDATE)` [GPP-LOOP]. Without it, you render the last completed step, which means the displayed motion quantizes to the sim rate and beats against the display rate — visible as microstutter whenever the two are not locked. With it, the renderer draws a state that is a blend of two real states.

The cost is honest and worth stating: interpolation renders **up to one fixed step in the past** (you can only blend between states you have), so a 60 Hz sim adds up to 16.7 ms of visual latency. Extrapolating forward instead removes the latency and introduces prediction error — and prediction error means the visual can show a collision that the simulation then un-does. Fiedler chooses interpolation; deWiTTERS extrapolates (`view_position = position + (speed * interpolation)`) [DEWITTERS]. Either is defensible.

Note what interpolation demands of the *game*, not the engine: two copies of the interpolatable state, previous and current. The loop's contribution is only to publish alpha, honestly, every frame. Whether the engine offers any interpolation helper at all is your design call.

### The spiral of death, and the two ways everyone bounds it

If a step costs more than a step's worth of real time, catch-up makes things worse: *"It's called the spiral of death because being behind causes your update to simulate more steps to catch up, which causes you to fall further behind, which causes you to simulate more steps…"* [GAFFER-TIMESTEP]. Nystrom's version of the same trap: *"If step two takes longer than step one, the game slows down"* [GPP-LOOP]. This is not a rare pathology — a debugger breakpoint, a shader compile, a window drag, or an OS hiccup produces a multi-second dt on a normal development day, and an unbounded accumulator turns that into thousands of queued steps and an app that appears hung.

Two bounds ship, and they are not equivalent:

- **Clamp the incoming dt.** Unity's `maximumDeltaTime` is *"The maximum value of Time.deltaTime in any given frame"*, and the doc spells out the consequence: it *"bounds the maximum number of times Unity executes MonoBehaviour.FixedUpdate in a frame to maximumDeltaTime / fixedDeltaTime"*, with the invariant that it *"is always at least as large as Time.fixedDeltaTime"* [UNITY-TIME maximumDeltaTime]. **You already built this** — it is m11-01's `max_dt`/`clamp_dt`.
- **Cap the steps.** Fiedler: *"Alternatively you can clamp at a maximum # of steps per-frame and the simulation will appear to slow down under heavy load"* [GAFFER-TIMESTEP]. deWiTTERS calls it `MAX_FRAMESKIP` [DEWITTERS]; Unreal calls it Max Substeps, *"the maximum number of sub-steps a full step is permitted to be broken into"*, alongside Max Substep Delta Time, *"the maximum time, in seconds a sub-step is allowed to take"* [UE-SUBSTEP].

Whichever you pick, one question decides whether you actually escaped the spiral: **what happens to the time you refused to simulate?** Drop it and simulated time falls permanently behind real time — the game visibly slows under load, which is the intended behaviour ("appear to slow down under heavy load"). Keep it in the accumulator and you have not bounded anything; you have deferred the same steps to the next frame, and the spiral proceeds on schedule.

You now hold two clamps. Deciding whether the dt clamp, the step cap, or both is right — and being able to say what each one protects against that the other doesn't — is a design task, not a formality. (Hint at the shape of the answer: they fail differently when a *single step* is what's slow, versus when the *frame* was long.)

### Exactness, one level up

m11-01's rule was: absolute time is integer nanoseconds, and elapsed is derived by subtraction, never accumulated. That rule now applies to a second timeline — the simulation's.

Start with an unpleasant arithmetic fact: **60 Hz is not a whole number of nanoseconds.** 1/60 s = 16,666,666.67 ns. Whatever integer you choose, a 60 Hz fixed step is wrong by a fraction of a nanosecond per step, so sim time and real time diverge slowly and forever. The magnitude is negligible (~0.67 ns/step ≈ 40 ns per real second); the *shape* is the lesson, and it has two clean escapes. Choose a rate whose period is exact in nanoseconds — 50 Hz (20,000,000 ns), 64 Hz (15,625,000 ns), 100 Hz, 125 Hz — or accept the residue and make sure it cannot compound.

It cannot compound if you **derive** sim time instead of accumulating it: `sim_time = steps_taken * fixed_dt` is exact by construction, in the same way `elapsed = now - origin` was.

Be precise about *why*, because two separate rules live here and merging them produces a bad argument. In **integer nanoseconds**, `sim_time += fixed_dt` once per step is also exact — it equals `steps_taken * fixed_dt` to the nanosecond, forever, through any number of pauses and hitches. So exactness is not what deriving buys. What it buys is that no second variable exists to disagree with the step count: a sum can fall out of step for reasons that are not arithmetic — a step loop that returns early, a future "skip this step" or rollback path, a new branch that forgets to update it — while the count has to exist anyway, because the loop is written in terms of it. One source of truth, not one fewer rounding error.

The `f32` measurement argues for the **unit**, not for the derivation: m11-01's **1,989.9 ms of drift over 100,000 frames** is what happens when absolute time lives in `f32` seconds, and it would ruin a derived value converted too early just as thoroughly. The accumulator is the one place where addition is unavoidable — it is a bank balance, not a clock — which is exactly why *it* must hold integer nanoseconds, where every add and subtract is exact.

> **C++ habit vs DOD approach — dt does not belong in a global.** The C++ reflex is `Time::DeltaTime()` (or `GetEngine()->GetTime()->Delta()`), reachable from anywhere, so any function can ask what time it is. Odin's version of that temptation is `context` — you *could* stash the frame's dt in `context.user_ptr` and read it anywhere without threading a parameter. Don't. The frame's timing is **data produced at the top of the frame and passed down**: the fixed dt is a constant the systems already know, the alpha is a parameter the render call takes, and a system that needs to know "how long is a step" is told, not asked. The tell that you got it right: a system's update proc can be called twice in a row with the same arguments and behave identically both times, which is also precisely what makes it testable.

### The seam nobody warns you about: input across 0, 1, or 2 steps

This one is subtle, it is not in the required reading, and it is where your two previous lessons collide.

m10-02's input is a **frame-coherent snapshot**: `poll_events` drains the OS queue, records half-transitions, and retires the edges, so `key_pressed(h, .Space)` is true for exactly one *frame* after the press. m11-02 introduces a per-frame step count of 0, 1, or 2+. Compose them naively and:

- **A 2-step frame double-counts every edge.** Both steps see `key_pressed(.Space) == true`. One press, two jumps.
- **A 0-step frame drops every edge.** The pump retired the press; no step ever ran to observe it. One press, no jump — and this is the *common* case when the sim rate is below the frame rate, which is the normal configuration.

Neither package is buggy. The bug lives in the seam, and this lesson has to name an owner. The plausible answers (there are more):

- Sample input into a per-frame **command/intent** value before stepping, and let steps consume *that* — edges become "pressed at some point during this frame", latched until a step consumes them.
- Give the first step of a frame the edges and subsequent steps only the level state (`key_down`), which is what "one press, one jump, held keys keep working" means operationally.
- Move edge retirement to a **step** boundary rather than a pump boundary — which then requires that a 0-step frame not retire anything, i.e. the latch again, in a different package.
- Accept 2+ step frames dropping duplicates by design (jump-on-press is idempotent per frame) and document it.

Pick one, write down what happens to a press that arrives during a 0-step frame, and make the test say it. This is the kind of decision that is invisible until a player says "sometimes my jump doesn't register" six months later.

### Pacing the frame, and what Windows thinks of your 1 ms sleep

There is no renderer yet, so there is no vsync: **your limiter is the only thing standing between the loop and a pegged core.** m10-01 measured the testbed's idle spin at ~5.4 M pump iterations/second; m11-01 built the fix (`frame_deadline` + `wait_until`) and measured it on **darwin**: mean overshoot +0.1–0.2 µs with a 1 ms spin margin and 1 ms sleep chunks.

You are now on **Windows**, where those numbers are not transferable, because both halves of `wait_until` change underneath you:

- `time.sleep` on Windows is `Sleep(d / Millisecond)` — whole-millisecond truncation, so a sub-millisecond request sleeps zero [ODIN-TIME].
- `Sleep`'s granularity is a *system* setting, and the default is coarse — historically ~15.6 ms. It is lowered by `timeBeginPeriod`, which *"requests a minimum resolution for periodic timers"* [MS-TIMEPERIOD]. So the same 1 ms sleep chunk that overshot by ~0.25 ms on darwin can overshoot by an entire frame here.
- Who calls it matters, and the rules changed: *"Prior to Windows 10, version 2004, this function affects a global Windows setting. For all processes Windows uses the lowest value (that is, highest resolution) requested by any process. Starting with Windows 10, version 2004, this function no longer affects global timer resolution. For processes which have not called this function, Windows does not guarantee a higher resolution than the default system resolution"* [MS-TIMEPERIOD]. On Windows 11 there is a further twist: an occluded or minimized window-owning process loses the guarantee again.
- It is not free: *"it can also reduce overall system performance, because the thread scheduler switches tasks more often. High resolutions can also prevent the CPU power management system from entering power-saving modes"* [MS-TIMEPERIOD]. And the line that keeps the two clocks straight: *"Setting a higher resolution does not improve the accuracy of the high-resolution performance counter"* — your QPC-backed `tick_now` is unaffected either way [MS-TIMEPERIOD], [MS-QPC].

Here is the part that makes this a *layering* story rather than a Windows story: SDL ships a hint for precisely this — `SDL_HINT_TIMER_RESOLUTION`, *"A variable that controls the timer resolution, in milliseconds"*, whose *"default value is '1'"*, where *"If this variable is set to '0', the system timer resolution is not set"* [SDL SDL_HINT_TIMER_RESOLUTION]. Your platform layer calls `sdl.Init({.VIDEO})`. So a Windows-specific timer-resolution decision may already have been made for your process, by a dependency, three layers below the loop — or may not have been, since you did not initialize SDL's timer subsystem. **Which of those is true on this machine is measurable, and it is part of this lesson's measurement task.** Casey hits the same wall on camera in day 18: *"Setting the Windows scheduler granularity with timeBeginPeriod()"*, right after *"Looping to ensure we are within the targetSecondsPerFrame"* [HMH day 18].

### Ordering the frame

The body has a canonical order, and each edge in it is a decision you should be able to defend:

**pump input → step the simulation N times → render(alpha) → present → pace to the deadline.**

- **Pump first**, so the steps see the freshest input and input latency is one frame, not two.
- **Pace last**, because everything before it is what you are pacing; and note m11-01's gift — `wait_until` *returns the tick it reached*, which is exactly the next frame's `frame_start` timestamp. The limiter and the clock share one clock read, so the "one read per frame" rule survives the loop.
- **Present, then pace** — once a swapchain exists (m20-03), vsync becomes a *second* pacing mechanism inside `present`, and two limiters fighting is a real bug. Leave a note in your design for the you of m20-03.
- The **temp allocator reset** belongs here too: your testbed already does `free_all(context.temp_allocator)` per iteration, and that is a per-frame lifetime contract worth naming in the loop rather than leaving as a habit.

## In the industry

The convergence is the argument. Fiedler in 2004, Witters in 2009, Nystrom in 2014, plus two of the three biggest commercial engines shipping today — all independently landing on *bank real time, spend it in fixed steps, bound the catch-up, hand the remainder to the renderer as a blend factor*:

- **Unity** runs the accumulator engine-wide: fixed updates are the physics/gameplay clock, a *"backlog of fixed updates accumulates during some frames"* and Unity *"executes all of them in the next frame to catch up"*, bounded by *"a maximum timestep period beyond which Unity will not attempt to catch up"* [UNITY-TIME fixed-updates]. Its bound is a dt clamp expressed in user-facing units, and the docs give you the arithmetic to convert it into a step cap yourself [UNITY-TIME maximumDeltaTime].
- **Unreal** takes the other split: the engine tick stays variable for scalability, and the accumulator is given to physics alone, because *"the physics engine works best with small fixed time steps"* — Max Substep Delta Time and Max Substeps [UE-SUBSTEP]. This is the pragmatic middle: fixed where determinism and stability are load-bearing, variable where they aren't.
- **Handmade Hero** builds the limiter side live and hits every wall you are about to: the frame computation/display timeline, variable-refresh monitors, giving time back with sleep, and the Windows scheduler granularity [HMH day 18].
- **Gregory** puts this in context that the blog posts don't: §8.4 "Abstract Timelines" — real time, game time, and local timelines are *different* timelines, and the game's is not obliged to track the real one (pause, slow-mo, replays); §8.5 "Measuring and Dealing with Time" — the measurement machinery you built in m11-01 [GEA §8.4–8.5]. The fixed step is what makes the game timeline a *countable* thing: `steps × fixed_dt`, not "however much wall time went by".

### Pacing is a separate industry story from the fixed step

Everything above is about the *simulation* clock. How a shipping engine decides when a frame may **end** is a different question with different answers, and the through-line is worth knowing before you build a limiter: **nobody trusts a long-lived deadline anchor.**

**Mostly, the display owns the clock.** Notice that Fiedler's article contains no limiter at all — the renderer produces time, so the present path's rate *is* the input [GAFFER-TIMESTEP]. Unity states the preference outright: `targetFrameRate` is *"a software-based timing method"*, *"If `vSyncCount != 0`, then `targetFrameRate` is ignored"*, and *"Setting `vSyncCount = 0` and using `targetFrameRate` will not produce a completely stutter-free output"* — it is *"subject to microstuttering"* [UNITY-TIME targetFrameRate]. A vsync-paced loop cannot drift because the hardware re-anchors it on every scanout. You are building a software limiter for one reason: there is no swapchain yet. From m20-03, Vulkan's present modes are the primary mechanism [VKSPEC] and this becomes the uncapped-presentation fallback.

**Where the display can be *told* when to show a frame, engines stop sleeping altogether.** Google's Frame Pacing library defines the problem better than anyone — *"Frame pacing is the synchronization of a game's logic and rendering loop with an OS's display subsystem and the underlying display hardware"* — and diagnoses the symptom with numbers: a 30 fps loop on 60 fps hardware *"doesn't realize that a repeated frame remains on the screen for an extra 16 milliseconds"*, yielding frame times like *"49 milliseconds, 16 milliseconds, 33 milliseconds"*, because *"short frames followed by long frames are perceived by the player as stuttering"* [ANDROID-PACING]. The mechanism is presentation timestamps (*"so that frames are not presented early"*) plus *"sync fences ... to inject waits into the application that allow the display pipeline to catch up, rather than allowing back pressure to build up"* — a deadline handed *to* the presentation engine rather than waited on by the CPU. Unreal integrates that library rather than rolling its own [UE-PACING].

**Among engines that do sleep, the anchor is either one frame old or explicitly bounded.** Handmade Hero recomputes the target from each frame's own start — *"Looping to ensure we are within the targetSecondsPerFrame"*, with `timeBeginPeriod` to make the sleep granular enough to matter [HMH day 18], [MS-TIMEPERIOD]. deWiTTERS keeps a running `next_game_tick += SKIP_TICKS` grid and pairs it with `MAX_FRAMESKIP` [DEWITTERS] — and the fact that a beginner's tutorial ships that bound tells you how old the failure is: an incrementally-maintained grid falls arbitrarily far behind reality, and something has to cap the catch-up.

**And the goal is consistency, not a number.** Unreal's desktop knob is a *range* — **Smooth Frame Rate**, *"enabled by default"*, which *"can be used to define the min/max acceptable frame rates on a per-application basis"*, each bound being *"Exclusive (excludes value), Inclusive (includes value), or Open (value is not capped)"* — and its pacing exists to *"prioritize consistency and stability in rendering"* [UE-PACING]. That reframes the measurement task: the interesting number is not "did we hit 60", it is the spread around it.

The consequence for your design: an origin-anchored deadline grid is only meaningful while every frame has actually been paced to it. Frames that skip the wait — because the limiter was off, because the rate changed, because the machine suspended — consume grid slots without spending wall time, and the grid silently desynchronises. Every approach above avoids that by construction; a hand-rolled limiter has to do it deliberately.

Two industry-shaped notes on what you are *not* building yet. Fixed-step determinism is the foundation of deterministic-lockstep networking and of replay systems — same inputs, same step count, same result — which is why RTS and fighting games treat the step as sacred. And the flat "call each system in order" loop you are about to write is the thing that later becomes a dependency graph across cores; that transition, and why frame-centric design survives it, is Naughty Dog's fiber talk [ND-FIBERS], parked for m41.

## Performance notes

**Cost model.** The pacer itself is arithmetic — one add, a compare-and-subtract loop, one divide for alpha — call it tens of nanoseconds against a 16,670,000 ns budget. Nothing you do here shows up in a profile. What *does* show up:

- **The spin margin is a CPU tax you pay every frame.** A 1 ms spin tail at 60 fps is 60 ms of busy-waiting per second — **6% of one core, permanently**, to buy sub-microsecond pacing. That is a *choice* about laptops and battery, not a free win, and it is why m11-01's `wait_until` documents keeping the margin small. On Windows the trade shifts again: if the timer resolution is coarse, precision demands a *bigger* margin, so the tax goes up exactly where the OS is least cooperative [MS-TIMEPERIOD].
- **The catch-up cliff is a step-cost question.** If one fixed step costs `S` and the cap allows `N` steps, a hitch frame costs `N × S` before rendering even starts. At 60 Hz sim with a 4-step cap and a 3 ms step, that is a 12 ms frame — inside budget. At a 10 ms step it is 40 ms, which itself produces a long frame, which requests more catch-up: the spiral, arriving through the cap you thought protected you. The cap bounds the *count*, not the *cost*.
- **Step-count jitter is visible, and it is not a bug.** A 60 Hz sim on a 144 Hz render loop takes a step on ~42% of frames; without alpha, that pattern *is* your animation. This is the number that turns "why does it look stuttery when the frame rate is high" into arithmetic.

**Measurement task (tutor-run; numbers recorded in `curriculum/JOURNAL.md`).** Once the loop is green and the demo runs, the tutor benchmarks in `katas/main_loop_bench/` (plus a short instrumented testbed run):

- **(a) The Windows pacing baseline** — re-run m11-01's waiter comparison *on this machine*: `time.sleep`, `time.accurate_sleep`, and your `wait_until` at 1 / 5 / 16.7 ms, mean and max overshoot. Then the layering question, empirically: the same numbers **before** `sdl.Init({.VIDEO})`, **after** it, and after an explicit `timeBeginPeriod(1)` — does SDL's `SDL_HINT_TIMER_RESOLUTION` default of `"1"` actually reach this process with only the video subsystem initialized [SDL SDL_HINT_TIMER_RESOLUTION], [MS-TIMEPERIOD]? Also: the darwin-vs-Windows delta on the identical `wait_until` code, since m11-01's numbers were darwin's.
- **(b) Frame pacing under the limiter** — 1,000 real frames at a 60 Hz target with the testbed loop: mean / min / max / **stddev** of the real frame period. The spread is the figure that matters, not the mean: shipping engines pace for consistency rather than for a number ([ANDROID-PACING], [UE-PACING]), and *"short frames followed by long frames are perceived by the player as stuttering"* [ANDROID-PACING]. Then the price of the frame-anchored deadline (design amendment 3): **cumulative slippage** — real elapsed time after 1,000 frames against 1,000 × the target period — which is the drift an origin-anchored grid would have corrected and this one does not. Against the same loop unlimited. Plus the CPU story: idle iterations/second and rough CPU occupancy, limited vs unlimited, next to m10-01's ~5.4 M/s spin.
- **(c) Step-count histogram** — with a 60 Hz sim, the distribution of steps-per-frame (0 / 1 / 2 / 3+) at render rates of 30, 60, 144, and uncapped, from fabricated dt sequences: how often is a frame a 0-step frame, and what is the longest run of them? This is the empirical case for alpha, and for the input-seam decision.
- **(d) Timeline exactness over a long session** — 100,000 fabricated frames with jittered dt: sim time derived as `steps × fixed_dt` vs accumulated in integer ns vs accumulated in `f32` seconds, each against the exact value; plus the real-vs-sim divergence a 16,666,666 ns step accumulates against an exact 60 Hz, and against an exact-in-ns rate (50 or 64 Hz) for contrast.
- **(e) Spiral demonstration** — inject a 2-second hitch into a fabricated frame sequence and count: steps requested, steps taken, and simulated-time debt, under (i) no bound, (ii) dt clamp only, (iii) step cap only, (iv) both. Then the same with a deliberately expensive step to produce the `N × S` cliff from the cost model. The output is a table of "what each bound actually protects against".
- **(f) Loop overhead** — ns/frame for the pacer bookkeeping alone (accumulate, step loop, alpha, deadline computation) as a percentage of a 16.67 ms budget, and the spin-margin cost as a percentage of one core at the target rate.

Tutor records **Built + Measured** and walks you through it; you write **Takeaways + Reflections**.

## Exercise

A **build** lesson in three parts, all in `engine/` and `examples/`:

1. **Graduate the timing kata.** Move `katas/timing/` into the engine (leaving the kata in place as m03-03 did). The API may change on the way in — graduation is the moment to fix anything the review flagged.
2. **Build the loop.** The fixed-timestep pacer, its catch-up bound, its alpha, and the frame limiter, wherever your design puts them.
3. **Rewire the testbed.** `examples/testbed/main.odin`'s hand-rolled `for !should_close` becomes the real loop, with a demo readout.

Tests: the pacer is pure arithmetic, so the m11-01 injection pattern applies again — drive the whole state machine with fabricated dts, no sleeping. Run with `odin test <pkg>`; the limiter's own contract is the only thing allowed to touch real time.

**The interface is learner-designed — that's your first task.** Sketch it in `design.md` (§Learner sketch); the tutor critiques, the agreed interface is recorded, and only then do stubs, tests, and the spec delta exist. Decisions that are yours:

- **Placement and package name.** Does the graduated clock go to `engine/core/...` (and under what package name — note that `package time` collides with `core:time` at every import site that needs both, so this is a real naming decision), and does the *loop* live in the same package, a different one, or at the app layer? Give the layering argument, not just the path.
- **Who owns the `for`.** App-owned loop calling down, or an engine-provided driver taking callbacks as proc pointers [SDL SDL_AppIterate], [SOKOL sokol_app.h]? If the latter: how does a `core`-layer driver pump `platform` events without importing upward?
- **The pacer's state and its API shape.** Does it own a `Frame_Clock` or take one? What does the once-per-frame call return — a step count to loop over, an iterator-shaped "next step?" query, or a struct with `steps`/`alpha`? Where does `alpha` come from and what is its type?
- **The simulation rate**, in whatever representation you defend: exact-in-ns (50/64/100 Hz) or 60 Hz with a known residue. Is it a compile-time constant or configurable at init? What is `sim_time`, and how is it derived?
- **The catch-up bound.** Reuse m11-01's `max_dt`/`clamp_dt` clamp, add a step cap, or both — and say what each one protects against. What happens to the leftover accumulator when the bound trips, and what does that do to simulated time?
- **The input seam.** Explicitly: what a keypress that arrives during a 0-step frame does, and what a keypress does when the frame runs two steps. Whose code changes — `platform`, the loop, or the app?
- **The limiter's policy.** Target rate configurable? Off by default? Does the loop own the deadline (m11-01's `frame_deadline`) and the returned tick, or does the app? What is the spin margin *on Windows*, and is `timeBeginPeriod` the engine's business, the platform layer's, or nobody's? (You may defer the last one with a reason — but name it.)
- **Pause and scale.** m11-01 explicitly deferred the game timeline to here [GEA §8.4]. Does it arrive now, and if so, does pause mean "dt is zero" or "the accumulator stops being fed"? (They differ when the pause is released.) Deferring again is allowed — with a reason and a forecast of who will need it first.
- **Interpolation help.** Does the engine offer anything for it, or is publishing alpha the whole contract?
- **What the demo shows.** The observable proof that this works.

**Fixed constraints (not yours to change):**

- **The layering law holds.** `core → platform → render → game`, downward only. If the loop lives below the app, the platform pump reaches it as data, not as an import.
- **The simulation only ever advances by the fixed step.** The measured dt never reaches simulation code, in any form.
- **Sim time is derived, not float-accumulated.** The accumulator holds integer nanoseconds.
- **Catch-up is bounded.** A 2-second hitch must not hang the app, must not spiral, and the loop must still be running afterwards. Refused time is accounted for deliberately, not silently kept.
- **`alpha ∈ [0,1)` is published every frame**, including 0-step frames.
- **One clock read per frame** in the steady state — the limiter's returned tick is the next frame's timestamp.
- **No per-frame allocation** in the loop body (the temp-allocator reset is not an allocation).
- **Deterministic tests:** the pacer's state machine drivable entirely with fabricated dts, including the hitch and the bound; only the limiter's contract test may touch real time.
- **Zero-step frames are legal** and covered by a test that says so.
- Tests under `core:testing`, leak check clean, `-vet -strict-style` clean; the spec delta lands for the graduated capability.

### Definition of done

- `odin test` green for the affected packages · per-test leak check 0 leaks · `-vet -strict-style` clean
- Fixed-step advancement, bounded catch-up, alpha (including 0-step frames), sim-time derivation, and the limiter's contract all covered by the tutor's tests and passing
- **Demo checkpoint confirmed:** the testbed runs the real loop — a readout (title bar or console) showing frame index, frame-time avg/min/max from the history, steps taken this frame, and alpha; Esc still closes; CPU is no longer pegged by the idle loop; and a deliberate hitch (hold a key that sleeps ~2 s, or a breakpoint) is visibly absorbed instead of hanging or fast-forwarding
- Spec delta written for the graduated engine capability; layering law verified by review
- Review passed (per review-rubric.md), including ≥2 comprehension probes answered
- Measurement task run by the tutor; **Built + Measured** recorded in `curriculum/JOURNAL.md`
- **Takeaways + Reflections** written by you, in your own words

## Reading list

- **Required:** [GAFFER-TIMESTEP — "Fix Your Timestep!", all five sections](https://gafferongames.com/post/fix_your_timestep/) — read it in order; each section is the bug in the previous one. Then [GPP-LOOP — "Game Loop"](https://gameprogrammingpatterns.com/game-loop.html) — the same conclusion reached from the pattern side, with the determinism argument stated better. Then [GEA §8.4–8.5](https://www.gameenginebook.com/) — abstract timelines, and where the fixed step sits among them.
- **Recommended:** [UNITY-TIME — the fixed timestep loop](https://docs.unity3d.com/Manual/fixed-updates.html) + [`Time.maximumDeltaTime`](https://docs.unity3d.com/ScriptReference/Time-maximumDeltaTime.html) — a shipping engine's accumulator and its bound, described to users; [MS-TIMEPERIOD](https://learn.microsoft.com/en-us/windows/win32/api/timeapi/nf-timeapi-timebeginperiod) — short, and it is why your Windows limiter behaves differently from your macOS one; [HMH day 18 — "Enforcing a Video Frame Rate"](https://guide.handmadehero.org/code/day018/) — the limiter built live, including the scheduler-granularity call.
- **Deeper:** [UE-SUBSTEP](https://dev.epicgames.com/documentation/en-us/unreal-engine/physics-sub-stepping-in-unreal-engine) — the fixed step scoped to one subsystem instead of the whole game; [DEWITTERS](https://dewitters.com/dewitters-gameloop/) — the four loop shapes in escalating order, and the extrapolation variant of alpha; [SDL SDL_AppIterate](https://wiki.libsdl.org/SDL3/SDL_AppIterate) next to [SOKOL sokol_app.h](https://github.com/floooh/sokol/blob/master/sokol_app.h) — what it looks like when the platform owns your loop, and why some platforms require it.
- **Deeper, on pacing specifically** (added mid-lesson, see "Pacing is a separate industry story"): [ANDROID-PACING](https://developer.android.com/games/sdk/frame-pacing) — read this one even though you are not shipping on Android; it is the clearest statement anywhere of what frame pacing *is* and why sleeping is the wrong tool when the display can be told a presentation time; [UE-PACING](https://dev.epicgames.com/documentation/en-us/unreal-engine/frame-pacing-for-mobile-devices-in-unreal-engine) plus [Smooth Frame Rate](https://dev.epicgames.com/documentation/en-us/unreal-engine/smooth-frame-rate?application_version=4.27) — a shipping engine treating the target as a *range*; [UNITY-TIME targetFrameRate](https://docs.unity3d.com/ScriptReference/Application-targetFrameRate.html) — an engine documenting the limits of its own software limiter.
