#+private file
package timing

// Tutor-written conformance tests for the m11-01 timing kata. They bind to the agreed
// interface in design.md (per-operation contract table). Written RED against the stubs;
// the learner implements until green.
//
// Everything except the three wait_until cases drives the state machine with FABRICATED
// timestamps — that is what frame_start's `now` parameter buys (design.md finding 2): a
// 100,000-frame session is simulated in microseconds and no test sleeps.
//
// Every test asserts at least one positive-path expectation, so the benign stubs fail all
// of them. Run: odin test katas/timing

import "core:testing"
import "core:time"

// A deliberately NON-ZERO epoch: monotonic clocks count from boot, so anything that assumes
// origin == 0 (or that reads a timestamp as if it were an elapsed time) fails here.
EPOCH_NS :: i64(43_200_000_000_000) // 12 h of uptime

FRAME_60_NS :: i64(16_666_667) // ~1/60 s
FRAME_60 :: time.Duration(FRAME_60_NS)

// at — fabricate a monotonic timestamp `ns` nanoseconds after the epoch. Built with
// tick_add rather than by poking Tick._nsec: the underscore means "not yours".
at :: proc(ns: i64) -> time.Tick {
	return time.tick_add(time.Tick{}, time.Duration(EPOCH_NS + ns))
}

approx :: proc(a, b, eps: f64) -> bool {
	d := a - b
	return d < eps && d > -eps
}

@(test)
test_init_starts_frame_zero :: proc(t: ^testing.T) {
	clock: Frame_Clock
	t0 := at(0)
	clock_init(&clock, t0)

	testing.expect_value(t, clock.origin, t0)
	testing.expect_value(t, clock.prev, t0)
	testing.expect_value(t, clock.dt, time.Duration(0))
	testing.expect_value(t, clock.raw_dt, time.Duration(0))
	testing.expect_value(t, clock.elapsed, time.Duration(0))
	testing.expect_value(t, clock.frame_index, u64(0))
	testing.expect_value(t, clock.history.count, 0)
	testing.expect_value(t, clock.max_dt, 100 * time.Millisecond)
	testing.expect_value(t, clock.clamp_dt, time.Second / 60)
}

@(test)
test_first_frame_start_measures_and_records :: proc(t: ^testing.T) {
	clock: Frame_Clock
	clock_init(&clock, at(0))

	dt := frame_start(&clock, at(FRAME_60_NS))

	testing.expect_value(t, dt, FRAME_60)
	testing.expect_value(t, clock.dt, FRAME_60)
	testing.expect_value(t, clock.raw_dt, FRAME_60)
	testing.expect_value(t, clock.elapsed, FRAME_60)
	testing.expect_value(t, clock.prev, at(FRAME_60_NS))
	testing.expect_value(t, clock.origin, at(0)) // origin is never rewritten
	testing.expect_value(t, clock.frame_index, u64(1))
	testing.expect_value(t, clock.history.count, 1)
	testing.expect_value(t, history_average(&clock.history), FRAME_60)
}

@(test)
test_elapsed_is_exact_over_a_long_session :: proc(t: ^testing.T) {
	clock: Frame_Clock
	clock_init(&clock, at(0))

	FRAMES :: 100_000
	for i in 1 ..= FRAMES {
		frame_start(&clock, at(i64(i) * FRAME_60_NS))
	}

	// elapsed must be exactly now - origin: 100,000 * 16,666,667 ns = 27.8 minutes, to the
	// nanosecond. An accumulated `elapsed += dt` cannot promise this, which is the point.
	testing.expect_value(t, clock.elapsed, time.Duration(i64(FRAMES) * FRAME_60_NS))
	testing.expect_value(t, clock.frame_index, u64(FRAMES))
	testing.expect(
		t,
		approx(elapsed_seconds(&clock), 1666.6667, 1e-6),
		"elapsed_seconds must be exact over a long session",
	)
	testing.expect_value(t, clock.history.count, HISTORY_CAPACITY) // ring saturates
}

@(test)
test_clamp_substitutes_and_keeps_raw :: proc(t: ^testing.T) {
	clock: Frame_Clock
	clock_init(&clock, at(0), max_dt = 100 * time.Millisecond, clamp_dt = time.Second / 60)

	frame_start(&clock, at(FRAME_60_NS)) // a normal frame: untouched
	testing.expect_value(t, clock.dt, FRAME_60)

	dt := frame_start(&clock, at(FRAME_60_NS + 3 * i64(time.Second))) // a 3 s hitch
	testing.expect_value(t, dt, time.Second / 60)
	testing.expect_value(t, clock.dt, time.Second / 60)
	testing.expect_value(t, clock.raw_dt, 3 * time.Second) // the hitch stays observable
}

@(test)
test_clamp_disabled_when_max_dt_zero :: proc(t: ^testing.T) {
	clock: Frame_Clock
	clock_init(&clock, at(0), max_dt = 0)

	dt := frame_start(&clock, at(3 * i64(time.Second)))

	testing.expect_value(t, dt, 3 * time.Second)
	testing.expect_value(t, clock.dt, 3 * time.Second)
	testing.expect_value(t, clock.raw_dt, 3 * time.Second)
}

@(test)
test_clamping_diverges_sum_of_dt_from_elapsed :: proc(t: ^testing.T) {
	clock: Frame_Clock
	clock_init(&clock, at(0), max_dt = 100 * time.Millisecond, clamp_dt = time.Second / 60)

	sum: time.Duration
	sum += frame_start(&clock, at(FRAME_60_NS))
	sum += frame_start(&clock, at(FRAME_60_NS + 3 * i64(time.Second)))

	// elapsed is REAL time and is never clamped; the dts were. The divergence is by design.
	testing.expect_value(t, clock.elapsed, time.Duration(FRAME_60_NS + 3 * i64(time.Second)))
	testing.expect_value(t, sum, FRAME_60 + time.Second / 60)
	testing.expect(t, sum < clock.elapsed, "clamped dts must sum to LESS than real elapsed")
}

@(test)
test_zero_length_frame_is_legal :: proc(t: ^testing.T) {
	clock: Frame_Clock
	clock_init(&clock, at(0))

	frame_start(&clock, at(FRAME_60_NS))
	dt := frame_start(&clock, at(FRAME_60_NS)) // same timestamp: a zero-length frame

	testing.expect_value(t, dt, time.Duration(0))
	testing.expect_value(t, clock.raw_dt, time.Duration(0))
	testing.expect_value(t, clock.elapsed, FRAME_60)
	testing.expect_value(t, clock.frame_index, u64(2)) // still a frame; still counted
	testing.expect_value(t, clock.history.count, 2) // still a sample, even at 0
}

@(test)
test_dt_and_elapsed_conversions :: proc(t: ^testing.T) {
	clock: Frame_Clock
	clock_init(&clock, at(0), max_dt = 0)

	frame_start(&clock, at(FRAME_60_NS))
	testing.expect(
		t,
		approx(f64(dt_seconds(&clock)), 0.016666667, 1e-6),
		"dt_seconds converts ns to f32 seconds",
	)

	// 10 hours in one jump: f32 would have lost sub-ms resolution long before here.
	ten_h: Frame_Clock
	clock_init(&ten_h, at(0), max_dt = 0)
	frame_start(&ten_h, at(36_000 * i64(time.Second)))
	testing.expect(
		t,
		approx(elapsed_seconds(&ten_h), 36000.0, 1e-9),
		"elapsed_seconds needs f64 to stay exact at 10 h",
	)
}

@(test)
test_history_empty_then_partial_window :: proc(t: ^testing.T) {
	h: Frame_History

	testing.expect_value(t, history_average(&h), time.Duration(0))
	testing.expect_value(t, history_min(&h), time.Duration(0))
	testing.expect_value(t, history_max(&h), time.Duration(0))

	history_push(&h, 10 * time.Millisecond)
	history_push(&h, 20 * time.Millisecond)
	history_push(&h, 30 * time.Millisecond)

	// Statistics range over `count`, not over capacity: 60 ms / 3, not 60 ms / 100.
	testing.expect_value(t, h.count, 3)
	testing.expect_value(t, h.sum, 60 * i64(time.Millisecond))
	testing.expect_value(t, history_average(&h), 20 * time.Millisecond)
	testing.expect_value(t, history_min(&h), 10 * time.Millisecond)
	testing.expect_value(t, history_max(&h), 30 * time.Millisecond)
}

@(test)
test_history_exactly_full :: proc(t: ^testing.T) {
	h: Frame_History
	for _ in 0 ..< HISTORY_CAPACITY {
		history_push(&h, 16 * time.Millisecond)
	}

	testing.expect_value(t, h.count, HISTORY_CAPACITY)
	testing.expect_value(t, h.sum, i64(HISTORY_CAPACITY) * 16 * i64(time.Millisecond))
	testing.expect_value(t, history_average(&h), 16 * time.Millisecond)
}

@(test)
test_history_eviction_recomputes_extremes :: proc(t: ^testing.T) {
	h: Frame_History

	history_push(&h, 40 * time.Millisecond) // the spike, at the oldest end
	for _ in 1 ..< HISTORY_CAPACITY {
		history_push(&h, 16 * time.Millisecond)
	}
	testing.expect_value(t, h.count, HISTORY_CAPACITY)
	testing.expect_value(t, history_max(&h), 40 * time.Millisecond)

	// One more push evicts the spike. A max maintained as a scalar cannot recover from this;
	// scanning the window can.
	history_push(&h, 16 * time.Millisecond)
	testing.expect_value(t, history_max(&h), 16 * time.Millisecond)
	testing.expect_value(t, history_min(&h), 16 * time.Millisecond)
	testing.expect_value(t, h.sum, i64(HISTORY_CAPACITY) * 16 * i64(time.Millisecond))
	testing.expect_value(t, history_average(&h), 16 * time.Millisecond)
	testing.expect_value(t, h.count, HISTORY_CAPACITY) // saturated, not grown
}

@(test)
test_history_sum_exact_after_many_wraps :: proc(t: ^testing.T) {
	sample :: proc(i: int) -> time.Duration {
		return time.Duration(10_000_000 + i64(i % 7) * 1_000_000) // 10–16 ms, varying
	}

	h: Frame_History
	N :: 10_000
	for i in 0 ..< N {
		history_push(&h, sample(i))
	}

	// Independent reference: the last HISTORY_CAPACITY samples. Integer nanoseconds make
	// this exact after 100 wraps; an f32 running sum would not be.
	ref: i64
	for i in N - HISTORY_CAPACITY ..< N {
		ref += i64(sample(i))
	}

	testing.expect_value(t, h.count, HISTORY_CAPACITY)
	testing.expect_value(t, h.sum, ref)
	testing.expect_value(t, history_average(&h), time.Duration(ref / i64(HISTORY_CAPACITY)))
}

@(test)
test_frame_start_records_raw_not_clamped :: proc(t: ^testing.T) {
	clock: Frame_Clock
	clock_init(&clock, at(0), max_dt = 100 * time.Millisecond, clamp_dt = time.Second / 60)

	frame_start(&clock, at(FRAME_60_NS))
	frame_start(&clock, at(FRAME_60_NS + 3 * i64(time.Second)))

	// The overlay must be able to show the hitch, so the history stores real frame times.
	testing.expect_value(t, history_max(&clock.history), 3 * time.Second)
	testing.expect_value(t, clock.dt, time.Second / 60)
}

@(test)
test_wait_until_past_deadline_returns_immediately :: proc(t: ^testing.T) {
	deadline := time.tick_add(time.tick_now(), -time.Second) // one second ago

	start := time.tick_now()
	got := wait_until(deadline)
	waited := time.tick_since(start)

	testing.expect(
		t,
		time.tick_diff(deadline, got) >= 0,
		"must return a tick at or after the deadline",
	)
	testing.expect(t, waited < 5 * time.Millisecond, "a past deadline must not sleep")
}

@(test)
test_wait_until_reaches_deadline :: proc(t: ^testing.T) {
	deadline := time.tick_add(time.tick_now(), 5 * time.Millisecond)

	got := wait_until(deadline, 1 * time.Millisecond)

	testing.expect(t, time.tick_diff(deadline, got) >= 0, "must never return before the deadline")
	testing.expect(
		t,
		time.tick_diff(deadline, got) < 100 * time.Millisecond,
		"must not overshoot a 5 ms wait by 100 ms",
	)
}

@(test)
test_wait_until_pure_sleep_reaches_deadline :: proc(t: ^testing.T) {
	deadline := time.tick_add(time.tick_now(), 3 * time.Millisecond)

	got := wait_until(deadline, 0) // spin_margin 0: sleep only, no busy tail

	testing.expect(t, time.tick_diff(deadline, got) >= 0, "pure sleep must still not return early")
}
