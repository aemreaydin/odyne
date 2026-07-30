package timing

import "core:time"

// 50 Hz: 1/50 s is exactly 20,000,000 ns, where 1/60 s truncates to 16,666,666.
DEFAULT_FIXED_DT :: time.Second / 50

/*
One fixed-rate timeline; several may coexist (a 50 Hz simulation and a 10 Hz AI tick are
two Pacers). Every nanosecond fed in is either in `steps_taken * fixed_dt` or in
`accumulator`, exactly — the conservation the integer representation exists to hold.
*/
Pacer :: struct {
	fixed_dt:    time.Duration, // set by pacer_init and never written again
	accumulator: time.Duration, // unspent real time; always < fixed_dt once an advance returns
	steps_taken: u64,
}

/*
One frame's timing report: the simulation it owes, and its phase past the last step. A
`count` of 0 is ordinary rather than an error — a 50 Hz step under a 60 fps display takes
no step roughly one frame in six, so per-frame logic must not assume one ran.
*/
Frame_Steps :: struct {
	count: int,
	alpha: f32, // [0,1) — phase between the last completed step and the next
}

// Sets the step and empties the pacer. Panics unless `fixed_dt` is positive.
pacer_init :: proc(p: ^Pacer, fixed_dt: time.Duration = DEFAULT_FIXED_DT) {
	assert(fixed_dt > 0, "fixed_dt must be positive")
	p.fixed_dt = fixed_dt
}

/*
Deposits one frame of real time and reports the steps it bought. `dt` must be the frame
clock's already-clamped delta and must be non-negative — hitch policy lives upstream, and
passing a raw delta here reintroduces the unbounded catch-up the clamp exists to prevent.

The accumulator is drained below `fixed_dt` on every advance, so the reported alpha is
always < 1 without anyone clamping it.
*/
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

// The current phase in [0,1), as last reported by `pacer_advance`. Advances nothing.
pacer_alpha :: proc(p: ^Pacer) -> f32 {
	return f32(f64(p.accumulator) / f64(p.fixed_dt))
}

// The game timeline, `steps_taken * fixed_dt`. A product, never a sum, so it stays exact
// at any age and through any number of pauses and hitches.
sim_time :: proc(p: ^Pacer) -> time.Duration {
	return time.Duration(p.steps_taken) * p.fixed_dt
}

// The fixed step as `f32` seconds — the unit gameplay math and `core:math/linalg` use.
step_seconds :: proc(p: ^Pacer) -> f32 {
	return f32(time.duration_seconds(p.fixed_dt))
}
