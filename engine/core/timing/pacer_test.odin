#+private file
package timing

// Tutor-written conformance tests for the m11-02 fixed-timestep pacer. They bind to the agreed
// interface in the lesson's design.md (§Agreed interface — the pacer contract table), and to the
// `core-timing` spec delta's pacing / conservation / phase requirements.
//
// NOTHING HERE TOUCHES A CLOCK. That is the payoff of the pacer taking a `Duration` rather than a
// `^Frame_Clock` (design finding 3): every contract below is `i64` arithmetic, so a 100,000-frame
// session runs in microseconds, nothing sleeps, and nothing is platform-dependent. The frame
// clock has its own tests, which came with it from katas/timing/.
//
// Every test asserts at least one positive-path expectation, so the benign stubs fail all of
// them. Run: odin test engine/core/timing

import "core:testing"
import "core:time"

// The default step, spelled out. 50 Hz was chosen precisely because this number is exact.
STEP :: 20 * time.Millisecond

// A 144 Hz frame period — the case that produces 0-step frames at a 50 Hz simulation.
FRAME_144 :: time.Duration(6_944_444)

ALPHA_EPS :: f32(1e-6)

expect_alpha :: proc(t: ^testing.T, got, want: f32, label: string, loc := #caller_location) {
	delta := got - want
	if delta < 0 {
		delta = -delta
	}
	testing.expectf(t, delta <= ALPHA_EPS, "%s: alpha %v, want %v", label, got, want, loc = loc)
}

// ── init, defaults, and the exactness the rate was chosen for ──────────────────────────────

@(test)
test_pacer_init_defaults_to_an_exact_50hz_step :: proc(t: ^testing.T) {
	// The reason 50 Hz is the default: its period is a whole number of nanoseconds, so a step is
	// the rate's true period rather than a truncation of it. 60 Hz is not, and the contrast is
	// the point — 16,666,666 × 60 is 40 ns short of a second, forever.
	testing.expect_value(t, DEFAULT_FIXED_DT, STEP)
	testing.expect_value(t, DEFAULT_FIXED_DT * 50, time.Second)
	testing.expect(
		t,
		(time.Second / 60) * 60 != time.Second,
		"60 Hz should NOT be exact in integer nanoseconds - if this fires, the premise changed",
	)

	p: Pacer
	pacer_init(&p)
	testing.expect_value(t, p.fixed_dt, STEP)
	testing.expect_value(t, p.accumulator, time.Duration(0))
	testing.expect_value(t, p.steps_taken, u64(0))
	testing.expect_value(t, sim_time(&p), time.Duration(0))
	expect_alpha(t, pacer_alpha(&p), 0, "fresh pacer")
	expect_alpha(t, step_seconds(&p), 0.02, "step_seconds at 50 Hz")
}

@(test)
test_pacer_init_accepts_an_explicit_rate :: proc(t: ^testing.T) {
	// 64 Hz — the other rate that is exact in nanoseconds, and whose seconds value is also exact
	// in f32 (0.015625 = 2^-6), so step_seconds carries no rounding at all here.
	p: Pacer
	pacer_init(&p, time.Second / 64)
	testing.expect_value(t, p.fixed_dt, time.Duration(15_625_000))
	testing.expect_value(t, step_seconds(&p), f32(0.015625))

	// Re-initializing empties the pacer: it is a reset, not a rate change on a running timeline.
	pacer_init(&p, STEP)
	testing.expect_value(t, p.fixed_dt, STEP)
	testing.expect_value(t, p.steps_taken, u64(0))
	testing.expect_value(t, p.accumulator, time.Duration(0))
}

// ── step counting: zero, one, many ─────────────────────────────────────────────────────────

@(test)
test_frame_shorter_than_a_step_takes_none :: proc(t: ^testing.T) {
	// 144 fps against a 50 Hz simulation. A 0-step frame is ORDINARY — the deposited time is
	// retained, not lost, and the phase is what the renderer interpolates with.
	p: Pacer
	pacer_init(&p)

	got := pacer_advance(&p, FRAME_144)
	testing.expect_value(t, got.count, 0)
	testing.expect_value(t, p.steps_taken, u64(0))
	testing.expect_value(t, sim_time(&p), time.Duration(0))
	testing.expect_value(t, p.accumulator, FRAME_144)
	expect_alpha(t, got.alpha, f32(f64(FRAME_144) / f64(STEP)), "one 144 Hz frame")
}

@(test)
test_single_step_leaves_the_remainder :: proc(t: ^testing.T) {
	p: Pacer
	pacer_init(&p)

	got := pacer_advance(&p, 25 * time.Millisecond)
	testing.expect_value(t, got.count, 1)
	testing.expect_value(t, p.steps_taken, u64(1))
	testing.expect_value(t, sim_time(&p), STEP)
	testing.expect_value(t, p.accumulator, 5 * time.Millisecond)
	expect_alpha(t, got.alpha, 0.25, "25 ms at a 20 ms step")
}

@(test)
test_exact_step_leaves_no_phase :: proc(t: ^testing.T) {
	p: Pacer
	pacer_init(&p)

	got := pacer_advance(&p, STEP)
	testing.expect_value(t, got.count, 1)
	testing.expect_value(t, p.accumulator, time.Duration(0))
	expect_alpha(t, got.alpha, 0, "exactly one step")
}

@(test)
test_the_boundary_is_one_nanosecond_wide :: proc(t: ^testing.T) {
	// A step is owed at `>= fixed_dt`, not at `> fixed_dt`. One nanosecond short takes no step;
	// the nanosecond that follows takes it.
	p: Pacer
	pacer_init(&p)

	short := pacer_advance(&p, STEP - 1)
	testing.expect_value(t, short.count, 0)
	expect_alpha(t, short.alpha, f32(f64(STEP - 1) / f64(STEP)), "one ns short")
	testing.expectf(t, short.alpha < 1, "phase must stay below 1, got %v", short.alpha)

	last := pacer_advance(&p, 1)
	testing.expect_value(t, last.count, 1)
	testing.expect_value(t, p.accumulator, time.Duration(0))
	expect_alpha(t, last.alpha, 0, "the nanosecond that completes the step")
}

@(test)
test_phase_stays_below_one_at_the_very_top_of_the_range :: proc(t: ^testing.T) {
	// The phase is `accumulator / fixed_dt` and the contract is [0,1) — STRICTLY below one,
	// because the render path uses it to blend between the last completed step and the next, and
	// alpha == 1 means "a state that does not exist yet".
	//
	// The last few nanoseconds below a step are where that promise is hardest to keep, and where
	// the choice of division matters: 20,000,000 sits above 2^24, so consecutive f32 values there
	// are 2 apart, and `f32(19_999_999)` rounds to 20,000,000 exactly. A division performed in f32
	// therefore returns exactly 1.0 — the invariant broken by the rounding, not by the arithmetic.
	// Dividing in f64 (53 bits, exact for these integers) and narrowing the RESULT gives
	// 0.99999994. Same rule as m11-01's `duration_seconds`: do the integer work first, convert last.
	//
	// A tolerance-based check cannot catch this — the error is 6e-8 — so this asserts the
	// inequality itself.
	for k in 1 ..= 16 {
		p: Pacer
		pacer_init(&p)
		got := pacer_advance(&p, STEP - time.Duration(k))
		testing.expectf(t, got.count == 0, "%d ns short: count %d, want 0", k, got.count)
		testing.expectf(t, got.alpha < 1, "%d ns short: phase %v must be < 1", k, got.alpha)
		testing.expectf(
			t,
			pacer_alpha(&p) < 1,
			"%d ns short: queried phase %v must be < 1",
			k,
			pacer_alpha(&p),
		)
	}
}

@(test)
test_a_long_frame_takes_several_steps :: proc(t: ^testing.T) {
	p: Pacer
	pacer_init(&p)

	got := pacer_advance(&p, 100 * time.Millisecond)
	testing.expect_value(t, got.count, 5)
	testing.expect_value(t, p.steps_taken, u64(5))
	testing.expect_value(t, sim_time(&p), 100 * time.Millisecond)
	expect_alpha(t, got.alpha, 0, "five whole steps")
}

@(test)
test_the_catch_up_bound_is_max_dt_over_fixed_dt :: proc(t: ^testing.T) {
	// The clamp lives UPSTREAM, in the frame clock, so the pacer's worst case is whatever the
	// clock is willing to report. With m11-02's defaults (max_dt 100 ms, clamp_dt = fixed_dt):
	//
	//   a 2 s hitch  → the clock reports clamp_dt (20 ms) → 1 step
	//   a 99 ms frame → passes the threshold untouched     → 4 steps
	//
	// So the worst catch-up comes from a MEDIUM hitch, not a huge one — substituting a sane delta
	// is strictly gentler than capping at the threshold would be, and either way the count is
	// bounded by max_dt / fixed_dt = 5 without the pacer needing a step cap of its own.
	hitched: Pacer
	pacer_init(&hitched)
	after_hitch := pacer_advance(&hitched, STEP) // what the clock substitutes for a 2 s stall
	testing.expect_value(t, after_hitch.count, 1)

	medium: Pacer
	pacer_init(&medium)
	after_medium := pacer_advance(&medium, 99 * time.Millisecond)
	testing.expect_value(t, after_medium.count, 4)

	at_threshold: Pacer
	pacer_init(&at_threshold)
	worst := pacer_advance(&at_threshold, DEFAULT_MAX_DT_FOR_TEST)
	testing.expect_value(t, worst.count, 5)
}

// The loop's clamp threshold, restated here so this package's tests do not import `game`
// (which would be an upward dependency). Kept in step with game.DEFAULT_MAX_DT by the
// game-loop spec delta's "clamp threshold at least the fixed step" requirement.
DEFAULT_MAX_DT_FOR_TEST :: 100 * time.Millisecond

// ── pause: a zero delta is the whole mechanism ─────────────────────────────────────────────

@(test)
test_zero_delta_advances_nothing :: proc(t: ^testing.T) {
	// Pause is the ABSENCE of a deposit, which is why the pacer needs no pause flag: the loop
	// simply feeds nothing. Simulated time and the phase must both stand still, so that resuming
	// continues from the same phase instead of jumping.
	p: Pacer
	pacer_init(&p)

	// Run one real frame first, so what the pause has to preserve is a NON-zero state — a test
	// that only checks "nothing moved" is passed by a pacer that never moves at all.
	pacer_advance(&p, 29 * time.Millisecond) // 1 step, 9 ms left over
	testing.expect_value(t, p.steps_taken, u64(1))
	testing.expect_value(t, sim_time(&p), STEP)
	expect_alpha(t, pacer_alpha(&p), 0.45, "before the pause")

	frozen_alpha := pacer_alpha(&p)
	frozen_sim := sim_time(&p)
	frozen_acc := p.accumulator

	for _ in 0 ..< 3 {
		got := pacer_advance(&p, 0)
		testing.expect_value(t, got.count, 0)
		expect_alpha(t, got.alpha, frozen_alpha, "paused frame")
	}

	testing.expect_value(t, sim_time(&p), frozen_sim)
	testing.expect_value(t, p.accumulator, frozen_acc)
	testing.expect_value(t, p.steps_taken, u64(1))
	expect_alpha(t, pacer_alpha(&p), frozen_alpha, "after the pause")
}

// ── the phase ──────────────────────────────────────────────────────────────────────────────

@(test)
test_phase_progresses_then_wraps_at_a_step :: proc(t: ^testing.T) {
	p: Pacer
	pacer_init(&p)

	quarter := STEP / 4
	want := [4]f32{0.25, 0.5, 0.75, 0.0}
	want_count := [4]int{0, 0, 0, 1}

	for i in 0 ..< 4 {
		got := pacer_advance(&p, quarter)
		testing.expectf(
			t,
			got.count == want_count[i],
			"deposit %d: count %d, want %d",
			i + 1,
			got.count,
			want_count[i],
		)
		expect_alpha(t, got.alpha, want[i], "quarter-step deposit")
	}
	testing.expect_value(t, p.steps_taken, u64(1))
	testing.expect_value(t, sim_time(&p), STEP)
}

@(test)
test_query_agrees_with_the_advance_report :: proc(t: ^testing.T) {
	// The render path reads the phase without advancing anything; it must see the same value the
	// advance just reported.
	p: Pacer
	pacer_init(&p)

	for dt in ([]time.Duration{FRAME_144, 3 * time.Millisecond, STEP, 47 * time.Millisecond}) {
		got := pacer_advance(&p, dt)
		expect_alpha(t, pacer_alpha(&p), got.alpha, "query after advance")
	}

	// Anchored to real values, so a pacer that reports 0 for everything cannot pass by agreeing
	// with itself: 6.944444 + 3 + 20 + 47 ms = 76.944444 ms ⇒ 3 steps, 16.944444 ms left over.
	testing.expect_value(t, p.steps_taken, u64(3))
	testing.expect_value(t, sim_time(&p), 60 * time.Millisecond)
	expect_alpha(t, pacer_alpha(&p), f32(f64(16_944_444) / f64(STEP)), "final phase")
}

// ── the invariants, over a long session ────────────────────────────────────────────────────

// A deterministic jitter source. `Math.random` has no place in a test whose failure has to be
// reproducible; xorshift64 from a fixed seed gives the same 100,000 frames on every machine.
rng_next :: proc(state: ^u64) -> u64 {
	x := state^
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	state^ = x
	return x
}

@(test)
test_time_is_conserved_and_the_phase_never_reaches_one :: proc(t: ^testing.T) {
	// The two invariants that matter most, checked over 100,000 jittered frames (~33 minutes of
	// simulated time). Failures are counted rather than logged per frame — one report, not
	// 100,000 of them.
	p: Pacer
	pacer_init(&p)

	seed: u64 = 0x9E3779B97F4A7C15
	total: time.Duration
	out_of_range := 0
	drift_seen := 0

	for _ in 0 ..< 100_000 {
		// 0 .. 40 ms — spans 0-step frames, 1-step frames and 2-step frames.
		dt := time.Duration(rng_next(&seed) % 40_000_001)
		total += dt

		got := pacer_advance(&p, dt)
		if got.alpha < 0 || got.alpha >= 1 {
			out_of_range += 1
		}
		if total != sim_time(&p) + p.accumulator {
			drift_seen += 1
		}
	}

	testing.expectf(t, out_of_range == 0, "phase left [0,1) on %d of 100,000 frames", out_of_range)
	testing.expectf(
		t,
		drift_seen == 0,
		"time was not conserved on %d of 100,000 frames",
		drift_seen,
	)
	testing.expect_value(t, sim_time(&p), time.Duration(p.steps_taken) * STEP)
	testing.expect_value(t, total - sim_time(&p), p.accumulator)
	testing.expect(t, p.accumulator < STEP, "the accumulator must be drained below one step")
	testing.expect(t, p.steps_taken > 0, "100,000 jittered frames must have taken some steps")
}

@(test)
test_simulated_time_is_a_product_not_a_sum :: proc(t: ^testing.T) {
	// Same total real time, delivered in wildly different chunk sizes: one 1-second frame versus
	// a thousand 1 ms frames. Because simulated time is derived from the step COUNT, both must
	// land on identical state — that is what makes the timeline independent of frame rate.
	one_lump: Pacer
	pacer_init(&one_lump)
	pacer_advance(&one_lump, time.Second)

	dribbled: Pacer
	pacer_init(&dribbled)
	for _ in 0 ..< 1000 {
		pacer_advance(&dribbled, time.Millisecond)
	}

	testing.expect_value(t, dribbled.steps_taken, one_lump.steps_taken)
	testing.expect_value(t, sim_time(&dribbled), sim_time(&one_lump))
	testing.expect_value(t, dribbled.accumulator, one_lump.accumulator)
	testing.expect_value(t, sim_time(&one_lump), time.Second)
	testing.expect_value(t, one_lump.steps_taken, u64(50))
}
