# game-loop Specification

## Purpose
The engine-owned frame loop. It owns platform initialization, one window, the frame clock,
the pacer, the frame limiter and teardown, and drives the application through ordered callbacks.
Lives at the top engine layer (`game`), so pumping the platform and calling application code are
both downward calls and the layering law is untouched.
## Requirements
### Requirement: Engine-owned frame loop

The engine SHALL provide a single entry point that owns the application's frame loop: it initializes the platform, creates one window from the supplied configuration, drives frames until the window reports a close request, and tears the window and platform down before returning — including on every error path. The application SHALL supply its per-frame work as callbacks rather than as a loop of its own. Every callback SHALL be optional.

#### Scenario: The loop runs and exits on a close request

- **WHEN** the application runs the loop and the window is asked to close
- **THEN** the loop stops driving frames, the shutdown callback runs, the window and platform are torn down, and success is reported

#### Scenario: A zero-value callback set is safe

- **WHEN** the loop is run with no callbacks supplied at all
- **THEN** frames are still driven and the loop exits cleanly without dereferencing a missing callback

#### Scenario: A failing application initialization aborts the loop

- **WHEN** the application's initialization callback reports failure
- **THEN** no frames are driven, the failure is reported distinctly from a platform or window failure, and the platform and window are still torn down

### Requirement: Invariant frame phase ordering

Within every frame the engine SHALL invoke the application in a fixed order: exactly one per-frame callback, then zero or more simulation-step callbacks, then exactly one render callback. The per-frame callback SHALL run after the platform event pump and before any simulation step of that frame. The render callback SHALL run after all of that frame's simulation steps. The engine SHALL read the clock once per frame.

#### Scenario: Ordering holds across frames with differing step counts

- **WHEN** several frames are driven, some taking no simulation steps and some taking several
- **THEN** each frame shows exactly one per-frame callback before its first step, all of that frame's steps before its render callback, and exactly one render callback

#### Scenario: Input edges are readable exactly once per frame

- **WHEN** a key is pressed and the frame in which the press is observed takes no simulation steps
- **THEN** the per-frame callback still observes the press, so the application can retain it as intent for a later step rather than losing it

### Requirement: Simulation advances only by the fixed step

Every simulation-step callback SHALL receive the configured fixed step as its delta. The measured real frame delta SHALL NOT be passed to simulation code in any form. Simulated time SHALL be reported to the application as a derived quantity.

#### Scenario: Steps carry the fixed delta regardless of frame time

- **WHEN** frames of widely varying real duration are driven
- **THEN** every simulation-step callback receives the same fixed delta, and the number of calls per frame varies instead

#### Scenario: A frame may take no steps

- **WHEN** a frame is shorter than the fixed step
- **THEN** no simulation-step callback runs that frame, and the render callback still runs with the frame's interpolation phase

### Requirement: Bounded hitch absorption

A frame whose measured duration greatly exceeds the fixed step SHALL advance the simulation by at most the configured clamp, SHALL NOT queue unbounded catch-up work, and SHALL leave the loop running. The configured clamp threshold SHALL be at least as large as the fixed step.

#### Scenario: A multi-second stall does not fast-forward the simulation

- **WHEN** a frame stalls for two seconds
- **THEN** that frame advances the simulation by at most the clamp, the application keeps receiving frames, and no backlog of steps is carried into subsequent frames

#### Scenario: A clamp smaller than the fixed step is rejected

- **WHEN** the loop is configured with a clamp threshold below the fixed step
- **THEN** the configuration is rejected rather than silently producing permanent slow motion

### Requirement: Frame pacing

The engine SHALL pace frames to a configurable target rate by waiting until a deadline derived from the start of the current frame. A frame SHALL NOT end before its deadline. Pacing SHALL be disableable and re-enableable at runtime, and the target rate SHALL be changeable at runtime; in every case pacing SHALL resume at the requested rate within a small multiple of one target period, and SHALL NOT stall for the accumulated difference between real time and any earlier schedule.

*(The deadline is deliberately NOT derived from a fixed origin. An origin-anchored grid corrects overshoot — a late frame is absorbed by the next — but it is only meaningful while every frame has been paced to it: unpaced frames advance the frame counter without spending wall time, leaving the grid ahead of reality, and the first paced frame afterwards waits for the whole difference. The cost of the frame-anchored deadline is that overshoot is never corrected, so the achieved rate settles marginally below the target.)*

#### Scenario: Frames are not faster than the target

- **WHEN** the loop is paced to a target rate and the frame's work finishes early
- **THEN** the frame does not end before its deadline, and the elapsed time for a run of frames is at least the target period times the frame count

#### Scenario: Pacing can be turned off

- **WHEN** the application disables pacing
- **THEN** the loop stops waiting between frames

#### Scenario: Pacing resumes without a stall after being re-enabled

- **WHEN** the application runs a burst of unpaced frames and then re-enables pacing
- **THEN** the next frames are paced at the target period, with no frame waiting for the time the unpaced burst would have occupied at that rate

### Requirement: Zero-value configuration applies defaults

A zero-value loop configuration SHALL produce a working, paced loop with a default window, a default fixed simulation step whose period is exactly representable in integer nanoseconds, a clamp derived from the fixed step, a default target frame rate, and a default wait margin.

#### Scenario: Defaults come from a zero-value configuration

- **WHEN** the loop is run with a zero-value configuration
- **THEN** a visible default window is created, the simulation advances at the default fixed rate, and pacing is active

### Requirement: Pause suspends simulated time only

While the application marks the loop paused, the engine SHALL feed no time to the simulation: simulated time and the interpolation phase SHALL be unchanged, while frames, real elapsed time, event pumping and rendering SHALL continue. Resuming SHALL NOT fast-forward the simulation through the paused interval.

#### Scenario: Real time advances while simulated time is frozen

- **WHEN** the application pauses the loop for several frames
- **THEN** the frame index and real elapsed time advance, no simulation step runs, and simulated time and the interpolation phase are unchanged

#### Scenario: Resuming does not replay the pause

- **WHEN** the application unpauses after a long pause
- **THEN** the first frame after resuming advances the simulation by no more than one step's worth of time

### Requirement: The engine-owned loop is a convenience, not the only path
The timing components the loop is built from — the frame clock, the pacer, the frame-time
history, and the deadline waiter — SHALL remain fully usable without the engine-owned loop,
depending on nothing in the `game` layer. A tool, an asset cooker, or a test harness SHALL be
able to write its own iteration over them.

The engine-owned loop exists because inverting control is the only shape available on
platforms where an application-owned infinite loop is not permitted to exist, and it is the
shape the platform layer's own backend offers [SDL SDL_AppIterate], [SOKOL]. It is not a
constraint on callers who can own their loop.

#### Scenario: Timing components driven without the loop
- **WHEN** a caller drives the frame clock and pacer directly, never entering the engine-owned loop
- **THEN** both function fully, and neither requires any facility from the `game` layer

#### Scenario: Loop placement keeps dependencies downward
- **WHEN** the frame loop's imports are inspected
- **THEN** every dependency points downward along `core → platform → render → game`, with no upward call into application code routed through a lower layer

