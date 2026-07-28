package main

// Tutor-run measurement for lesson m11-01: high-resolution timing.
// Five axes from the lesson's Performance notes:
//   (a) clock-read cost — time.tick_now() ns/call on this machine, vs the 30 ns (TSC-class)
//       and 0.8–1.0 us (platform-timer) poles [MS-QPC]
//   (b) sleep overshoot — requested vs actual for time.sleep, time.accurate_sleep, and the
//       kata's wait_until at two margins; mean and max
//   (c) drift — 100k frames: f32-accumulated vs f64-accumulated vs derived elapsed
//   (d) the tick->ns overflow point, at 10 MHz and at 1 GHz (arithmetic, not a benchmark)
//   (e) per-frame overhead — frame_start, the history queries, and the cost of passing an
//       824 B struct by value instead of by pointer
//
// Timed read loops accumulate a data-dependent value that is printed, so -o:speed cannot
// elide them (the m02-01 lesson).
//
// Run:  odin run katas/timing_bench -o:speed

import "base:intrinsics"
import "core:fmt"
import "core:time"
import tm "../timing"

READS :: 10_000_000 // clock-read and query iterations
FRAMES :: 100_000 // simulated frames for the drift and frame_start axes
TRIALS :: 30 // sleep trials per (method, duration)

FRAME_60_NS :: i64(16_666_667)
BUDGET_60_NS :: f64(16_666_667) // one 60 fps frame, for "% of budget"

at :: proc(ns: i64) -> time.Tick {
	// 12 h of fake uptime, so nothing can accidentally treat a timestamp as an elapsed time.
	return time.tick_add(time.Tick{}, time.Duration(43_200_000_000_000 + ns))
}

main :: proc() {
	fmt.println("=== m11-01 timing — tutor measurement ===")
	fmt.printfln(
		"size_of(Frame_Clock) = %d B  ·  size_of(Frame_History) = %d B  ·  HISTORY_CAPACITY = %d",
		size_of(tm.Frame_Clock),
		size_of(tm.Frame_History),
		tm.HISTORY_CAPACITY,
	)

	bench_clock_read()
	bench_sleep_overshoot()
	bench_drift()
	demo_overflow()
	bench_per_frame()
}

// ── (a) clock-read cost ───────────────────────────────────────────────────────
bench_clock_read :: proc() {
	fmt.println("\n--- (a) clock read ---")

	base := time.tick_now()
	acc: i64
	start := time.tick_now()
	for _ in 0 ..< READS {
		acc += i64(time.tick_diff(base, time.tick_now()))
	}
	elapsed := time.tick_since(start)
	per := f64(elapsed) / f64(READS)

	fmt.printfln("time.tick_now()  : %.2f ns/call  (%d reads, acc=%d)", per, READS, acc)
	fmt.printfln(
		"                   %.4f%% of a 60 fps frame per read · %.0f reads per ms of spinning",
		100 * per / BUDGET_60_NS,
		1_000_000 / per,
	)
}

// ── (b) sleep overshoot ───────────────────────────────────────────────────────
Sleep_Result :: struct {
	mean_ns: f64,
	max_ns:  i64,
}

measure :: proc(requested: time.Duration, method: proc(_: time.Duration)) -> Sleep_Result {
	total: i64
	worst: i64
	for _ in 0 ..< TRIALS {
		start := time.tick_now()
		method(requested)
		actual := i64(time.tick_since(start))
		over := actual - i64(requested)
		total += over
		worst = max(worst, over)
	}
	return {mean_ns = f64(total) / f64(TRIALS), max_ns = worst}
}

sleep_plain :: proc(d: time.Duration) {time.sleep(d)}
sleep_accurate :: proc(d: time.Duration) {time.accurate_sleep(d)}
wait_margin_1ms :: proc(d: time.Duration) {
	_ = tm.wait_until(time.tick_add(time.tick_now(), d), 1 * time.Millisecond)
}
wait_margin_0 :: proc(d: time.Duration) {
	_ = tm.wait_until(time.tick_add(time.tick_now(), d), 0)
}
wait_margin_4ms :: proc(d: time.Duration) {
	_ = tm.wait_until(time.tick_add(time.tick_now(), d), 4 * time.Millisecond)
}
wait_pure_spin :: proc(d: time.Duration) {
	_ = tm.wait_until(time.tick_add(time.tick_now(), d), 1 * time.Second) // margin > remaining
}

// The strategy the kata had BEFORE the refactor, kept here for comparison only: sleep in
// margin-sized chunks instead of one big sleep. More syscalls — but each chunk's overshoot is
// bounded by the chunk, not by the whole wait.
wait_chunked :: proc(d: time.Duration) {
	margin :: 1 * time.Millisecond
	deadline := time.tick_add(time.tick_now(), d)
	for {
		remaining := time.tick_diff(time.tick_now(), deadline)
		if remaining <= 0 {
			return
		}
		if remaining > margin {
			time.sleep(margin)
		}
	}
}

bench_sleep_overshoot :: proc() {
	fmt.printfln("\n--- (b) sleep overshoot (%d trials each, overshoot = actual - requested) ---", TRIALS)

	durations := [?]time.Duration {
		1 * time.Millisecond,
		5 * time.Millisecond,
		time.Duration(FRAME_60_NS),
	}
	names := [?]string {
		"time.sleep         ",
		"time.accurate_sleep",
		"wait_until m=0     ",
		"wait_until m=1ms   ",
		"wait_until m=4ms   ",
		"wait_until spin    ",
		"chunked m=1ms (old)",
	}
	methods := [?]proc(_: time.Duration) {
		sleep_plain,
		sleep_accurate,
		wait_margin_0,
		wait_margin_1ms,
		wait_margin_4ms,
		wait_pure_spin,
		wait_chunked,
	}

	for d in durations {
		fmt.printfln("  requested %v:", d)
		for i in 0 ..< len(methods) {
			r := measure(d, methods[i])
			fmt.printfln(
				"    %s  mean +%8.1f us   max +%8.1f us   (%.1f%% of the request)",
				names[i],
				r.mean_ns / 1000,
				f64(r.max_ns) / 1000,
				100 * r.mean_ns / f64(d),
			)
		}
	}
}

// ── (c) drift: accumulate vs derive ───────────────────────────────────────────
bench_drift :: proc() {
	fmt.printfln("\n--- (c) drift over %d frames of 16.666667 ms ---", FRAMES)

	clock: tm.Frame_Clock
	tm.clock_init(&clock, at(0), max_dt = 0)

	acc32: f32
	acc64: f64
	for i in 1 ..= FRAMES {
		tm.frame_start(&clock, at(i64(i) * FRAME_60_NS))
		acc32 += tm.dt_seconds(&clock)
		acc64 += f64(tm.dt_seconds(&clock))
	}

	exact_ns := i64(FRAMES) * FRAME_60_NS
	exact := f64(exact_ns) / 1e9
	derived := tm.elapsed_seconds(&clock)

	fmt.printfln("  exact (integer ns)      : %.6f s", exact)
	fmt.printfln(
		"  derived (now - origin)  : %.6f s   error %+.3f ms",
		derived,
		1000 * (derived - exact),
	)
	fmt.printfln(
		"  accumulated in f64      : %.6f s   error %+.3f ms",
		acc64,
		1000 * (acc64 - exact),
	)
	fmt.printfln(
		"  accumulated in f32      : %.6f s   error %+.3f ms  <-- the reason for the rule",
		f64(acc32),
		1000 * (f64(acc32) - exact),
	)
}

// ── (d) the tick->ns overflow point ───────────────────────────────────────────
mul_div :: proc(val, num, den: i64) -> i64 {
	// The stdlib's overflow-safe conversion: split the quotient and the remainder.
	q := val / den
	r := val % den
	return q * num + r * num / den
}

demo_overflow :: proc() {
	fmt.println("\n--- (d) tick -> ns conversion: where naive multiply-then-divide dies ---")

	NS_PER_S :: i64(1_000_000_000)
	limit := max(i64) / NS_PER_S
	fmt.printfln("  ticks * 1e9 overflows i64 above %d ticks", limit)

	for freq in ([?]i64{10_000_000, 1_000_000_000}) {
		uptime := f64(limit) / f64(freq)
		ticks := limit + freq // one second past the limit
		naive, overflowed := intrinsics.overflow_mul(ticks, NS_PER_S)
		safe := mul_div(ticks, NS_PER_S, freq)
		fmt.printfln(
			"  %4.0f MHz: limit reached after %8.1f s of uptime (%.1f min)",
			f64(freq) / 1e6,
			uptime,
			uptime / 60,
		)
		fmt.printfln(
			"            at %d ticks: naive multiply overflowed=%v (wrapped to %d)",
			ticks,
			overflowed,
			naive,
		)
		fmt.printfln(
			"            quotient/remainder split: %d ns = %.3f s  (correct)",
			safe,
			f64(safe) / 1e9,
		)
	}
}

// ── (e) per-frame overhead ────────────────────────────────────────────────────
// #force_no_inline + a data-dependent index: without both, -o:speed inlines these, hoists the
// loop-invariant read, and reports 0.00 ns for a measurement that is supposed to price a copy.
by_value :: #force_no_inline proc(h: tm.Frame_History, i: int) -> time.Duration {
	return h.samples[i]
}
by_pointer :: #force_no_inline proc(h: ^tm.Frame_History, i: int) -> time.Duration {
	return h.samples[i]
}

bench_per_frame :: proc() {
	fmt.println("\n--- (e) per-frame overhead ---")

	// frame_start, including the history push.
	clock: tm.Frame_Clock
	tm.clock_init(&clock, at(0), max_dt = 0)
	acc: i64
	start := time.tick_now()
	for i in 1 ..= FRAMES {
		acc += i64(tm.frame_start(&clock, at(i64(i) * FRAME_60_NS)))
	}
	fs := f64(time.tick_since(start)) / f64(FRAMES)
	fmt.printfln("  frame_start (incl. history_push) : %6.2f ns/frame  (acc=%d)", fs, acc)

	// The three history queries: one O(1), two O(capacity) scans.
	qacc: i64
	start = time.tick_now()
	for _ in 0 ..< READS {
		qacc += i64(tm.history_average(&clock.history))
	}
	avg := f64(time.tick_since(start)) / f64(READS)

	start = time.tick_now()
	for _ in 0 ..< READS {
		qacc += i64(tm.history_min(&clock.history))
	}
	mn := f64(time.tick_since(start)) / f64(READS)

	start = time.tick_now()
	for _ in 0 ..< READS {
		qacc += i64(tm.history_max(&clock.history))
	}
	mx := f64(time.tick_since(start)) / f64(READS)

	fmt.printfln("  history_average (uses sum, O(1))  : %6.2f ns/call", avg)
	fmt.printfln("  history_min     (scans %d)       : %6.2f ns/call", tm.HISTORY_CAPACITY, mn)
	fmt.printfln("  history_max     (scans %d)       : %6.2f ns/call", tm.HISTORY_CAPACITY, mx)
	fmt.printfln("  scan / O(1) ratio                 : %6.1fx  (qacc=%d)", mn / avg, qacc)

	// Parameter passing: the same trivial read, by value vs by pointer.
	vacc: i64
	start = time.tick_now()
	for i in 0 ..< READS {
		vacc += i64(by_value(clock.history, i % tm.HISTORY_CAPACITY))
	}
	bv := f64(time.tick_since(start)) / f64(READS)

	start = time.tick_now()
	for i in 0 ..< READS {
		vacc += i64(by_pointer(&clock.history, i % tm.HISTORY_CAPACITY))
	}
	bp := f64(time.tick_since(start)) / f64(READS)

	fmt.printfln(
		"  read one field, %d B struct BY VALUE : %6.2f ns/call",
		size_of(tm.Frame_History),
		bv,
	)
	fmt.printfln("  read one field, same struct BY POINTER : %6.2f ns/call  (vacc=%d)", bp, vacc)

	total := fs + avg + mn + mx
	fmt.printfln(
		"\n  a frame that ticks the clock and reads avg/min/max: %.1f ns = %.4f%% of a 60 fps budget",
		total,
		100 * total / BUDGET_60_NS,
	)
}
