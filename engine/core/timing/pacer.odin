package timing

import "core:time"

// The fixed-timestep pacer — the thing that stands between measured real time and the
// simulation, so that simulation code never sees a variable delta [GAFFER-TIMESTEP].
//
// The division of labour, which is also why this file has no clock in it: the FRAME CLOCK
// measures real time (timing.odin), the PACER decides how much simulation that buys. The pacer
// reads no clock, makes no syscall, allocates nothing and knows nothing about the platform —
// it is `i64` arithmetic, so its whole contract is testable with fabricated deltas.
//
// Fiedler's framing is the one to keep in mind: the renderer *produces* time and the simulation
// *consumes it* in discrete, equal steps. What is left over after the whole steps have been
// consumed is not waste — it is the phase between two simulation states, and it is exactly what
// the renderer needs in order to draw between them instead of snapping to the last one.

// DEFAULT_FIXED_DT — 50 Hz. Chosen over 60 Hz because 1/50 s is a whole number of nanoseconds
// (20,000,000) and 1/60 s is not: `time.Second/60` truncates to 16,666,666 ns, which is 0.67 ns
// short of a real 60 Hz step, forever. Harmless in itself — sim_time is derived, not accumulated
// — but a rate with no residue at all costs nothing here. 64 Hz (15,625,000 ns) is the other
// exact option worth remembering.
DEFAULT_FIXED_DT :: time.Second / 50

// Pacer — one fixed-rate timeline. Cheap enough to have several of (a 50 Hz simulation and a
// 10 Hz AI tick are two Pacers, not one scheduler), though this engine currently runs one.
//
// `steps_taken` is the ONLY source of simulated time: `sim_time` is that count multiplied by
// `fixed_dt`, never a running sum. That is m11-01's "derive, don't accumulate" rule applied to
// the second timeline — it is what keeps game time exact through pauses, hitches and clamps.
//
// Invariant, for the lifetime of the pacer: every nanosecond ever fed in is either in
// `steps_taken * fixed_dt` or in `accumulator`, exactly. Integer nanoseconds are what make that
// true; the same bookkeeping in `f32` seconds drifts (m11-01 measured 1,989.9 ms over 100,000
// frames).
Pacer :: struct {
	fixed_dt:    time.Duration, // the step; written by pacer_init and never again
	accumulator: time.Duration, // unspent real time; always < fixed_dt once an advance returns
	steps_taken: u64, // steps since init — the game timeline's only source
}

// Frame_Steps — one frame's timing report: how much simulation this frame owes, and how far
// past the last completed step the frame ended up.
//
// `count == 0` is legal and ORDINARY, not an error: at a 50 Hz step and a 60 fps display,
// 20 ms > 16.67 ms, so roughly one frame in six takes no step at all. Any per-frame logic that
// assumes at least one step ran is wrong on this configuration.
Frame_Steps :: struct {
	count: int, // simulation steps to run this frame; may be 0
	alpha: f32, // [0,1) — phase between the last completed step and the next
}

// pacer_init — set the step and empty the pacer. `fixed_dt` must be positive.
pacer_init :: proc(p: ^Pacer, fixed_dt: time.Duration = DEFAULT_FIXED_DT) {
	assert(fixed_dt > 0, "fixed_dt must be positive")
	p.fixed_dt = fixed_dt
}

// pacer_advance — deposit one frame's worth of real time and report what it bought.
//
// `dt` is the clock's CLAMPED delta: the hitch policy lives upstream, in the frame clock, which
// is what keeps this side spiral-proof — the time entering the accumulator per frame is bounded
// regardless of how long the frame actually took, so catch-up work is bounded too, and under
// sustained overload the simulation simply runs behind real time ("appear to slow down under
// heavy load") instead of queueing steps it can never work off.
//
// Requires `dt >= 0`; a monotonic clock cannot produce anything else.
//
// Consequence of clamping upstream rather than capping steps here: the accumulator is drained to
// below `fixed_dt` on every advance, so `alpha < 1` is structural rather than a value anyone has
// to clamp. (Capping the step count while keeping the leftovers would break exactly that.)
pacer_advance :: proc(p: ^Pacer, dt: time.Duration) -> Frame_Steps {
	assert(dt >= 0, "dt must be positive")

	steps: Frame_Steps
	p.accumulator += dt

	if p.accumulator >= p.fixed_dt {
		num_steps := p.accumulator / p.fixed_dt
		p.steps_taken += u64(num_steps)
		steps.count += int(num_steps)
	}
	p.accumulator %= p.fixed_dt

	steps.alpha = pacer_alpha(p)

	return steps
}

// pacer_alpha — the current phase, `accumulator / fixed_dt`, in [0,1). The same value the last
// advance reported; separate because the render path wants to ask without advancing anything.
pacer_alpha :: proc(p: ^Pacer) -> f32 {
	return f32(f64(p.accumulator) / f64(p.fixed_dt))
}

// sim_time — the game timeline: `steps_taken * fixed_dt`. Exact by construction, at any age,
// through any number of pauses and hitches, because it was never a sum of deltas.
sim_time :: proc(p: ^Pacer) -> time.Duration {
	return time.Duration(p.steps_taken) * p.fixed_dt
}

// step_seconds — the fixed step as `f32` seconds, which is the unit gameplay math wants
// (`pos += vel * dt`, and `core:math/linalg` is f32). Handed to simulation code so it need not
// convert, or guess.
step_seconds :: proc(p: ^Pacer) -> f32 {
	return f32(time.duration_seconds(p.fixed_dt))
}
