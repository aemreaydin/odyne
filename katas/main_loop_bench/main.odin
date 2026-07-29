package main

// m11-02 measurement task: the main loop and the frame limiter, measured.
//
// SECTIONS
//   a1/a2/a3  pacing baseline: waiter overshoot, cold vs after platform.init vs + timeBeginPeriod
//   b         frame pacing under the real loop: period distribution and cumulative slippage
//   c         step-count histogram at several render rates against a 50 Hz simulation
//   d         timeline exactness over 100,000 frames: derived vs i64-accumulated vs f32
//   e         the spiral, demonstrated under each catch-up bound
//   f         pacer and history overhead, as a fraction of a frame budget
//
// WHY a1/a2/a3 RUN IN CHILD PROCESSES
//
// Found the hard way. Windows revokes an elevated timer resolution from a process that has been
// sleeping and is not visible to the user, after ~8-16 s, and `timeBeginPeriod` cannot get it back
// [MS-TIMEPERIOD, Windows 11 clause]. A single-process bench therefore measures phase 1 honestly
// and phases 2 and 3 in the degraded regime, which made `timeBeginPeriod` look inert when it is
// not. One process per phase, same trick as tests/platform.
//
// Run: odin build katas/main_loop_bench -collection:engine=engine -o:speed -out:build/main_loop_bench.exe
// (SDL3.dll must sit beside the binary; ./scripts/build.ps1 puts it in build/.)

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:time"
import "engine:core/timing"
import "engine:game"
import "engine:platform"

// A deliberately non-zero epoch, as in m11-01's bench: a monotonic clock counts from boot, so
// anything that mistakes a timestamp for an elapsed time fails here. Built with tick_add rather
// than by poking Tick._nsec -- the underscore means "not yours".
at :: proc(ns: i64) -> time.Tick {
	return time.tick_add(time.Tick{}, time.Duration(43_200_000_000_000 + ns))
}

FIXED :: 20 * time.Millisecond // the engine's default simulation step, 50 Hz, exact in ns

// ─────────────────────────────────────────────────────────────────────────────
// (a) pacing baseline
// ─────────────────────────────────────────────────────────────────────────────

// 12 trials, not 30: a table has to finish well inside the ~8 s window before Windows revokes the
// timer resolution, or it measures two different regimes and averages them.
TRIALS :: 12

DURATIONS := [3]time.Duration {
	1 * time.Millisecond,
	5 * time.Millisecond,
	time.Duration(16_666_666),
}

Waiter :: struct {
	name: string,
	wait: proc(d: time.Duration) -> time.Duration, // returns overshoot: how much later than asked
}

wait_sleep :: proc(d: time.Duration) -> time.Duration {
	start := time.tick_now()
	time.sleep(d)
	return time.tick_since(start) - d
}

wait_accurate :: proc(d: time.Duration) -> time.Duration {
	start := time.tick_now()
	time.accurate_sleep(d)
	return time.tick_since(start) - d
}

wait_engine :: proc(d: time.Duration) -> time.Duration {
	deadline := time.tick_add(time.tick_now(), d)
	return time.tick_diff(deadline, timing.wait_until(deadline, 1 * time.Millisecond))
}

WAITERS := [3]Waiter {
	{"time.sleep", wait_sleep},
	{"time.accurate_sleep", wait_accurate},
	{"wait_until m=1ms", wait_engine},
}

Stats :: struct {
	mean, worst, best: time.Duration,
	stddev:            f64,
}

// Odin's fmt zero-pads a width applied to %f, so cells are formatted first and padded as strings.
cell :: proc(d: time.Duration) -> string {
	return fmt.tprintf("%.1fus", f64(d) / 1000.0)
}

waiter_table :: proc(label: string) {
	fmt.printfln("--- %s ---", label)
	fmt.printfln(
		"%-22s %13s %13s %13s %13s %13s %13s",
		"waiter",
		"1ms mean",
		"1ms worst",
		"5ms mean",
		"5ms worst",
		"16.7ms mean",
		"16.7ms worst",
	)
	for w in WAITERS {
		s: [3]Stats
		for d, i in DURATIONS {
			total: i64
			for _ in 0 ..< TRIALS {
				over := w.wait(d)
				total += i64(over)
				s[i].worst = max(s[i].worst, over)
			}
			s[i].mean = time.Duration(total / TRIALS)
		}
		fmt.printfln(
			"%-22s %13s %13s %13s %13s %13s %13s",
			w.name,
			cell(s[0].mean),
			cell(s[0].worst),
			cell(s[1].mean),
			cell(s[1].worst),
			cell(s[2].mean),
			cell(s[2].worst),
		)
	}
}

section_a1 :: proc() {
	waiter_table("a1: cold -- no timer resolution requested by anyone in this process")
}

section_a2 :: proc() {
	if platform.init() != .None {return}
	defer platform.shutdown()
	waiter_table("a2: after platform.init({.VIDEO}) -- did SDL lower it for us?")
}

section_a3 :: proc() {
	if platform.init() != .None {return}
	defer platform.shutdown()
	if !TIMER_RESOLUTION_AVAILABLE || !set_timer_resolution(1) {
		fmt.println("a3 skipped: no timer-resolution knob, or the request was refused")
		return
	}
	defer clear_timer_resolution(1)
	waiter_table("a3: after platform.init AND our own timeBeginPeriod(1)")
}

// ─────────────────────────────────────────────────────────────────────────────
// (b) frame pacing under the real loop
// ─────────────────────────────────────────────────────────────────────────────

B_FRAMES :: 900
B_TARGET :: 60

Loop_Probe :: struct {
	count:   int,
	dts:     [B_FRAMES]time.Duration, // per-frame REAL delta, pre-clamp
	elapsed: time.Duration,           // clock elapsed at the last frame
	steps:   [8]int,                  // histogram of steps per frame
}

probe_dts: Loop_Probe

probe_frame :: proc(app: ^game.App, user: rawptr) {
	p := cast(^Loop_Probe)user
	if p.count < B_FRAMES {
		p.dts[p.count] = app.clock.raw_dt
		p.count += 1
	}
	p.elapsed = app.clock.elapsed
	idx := min(app.steps.count, len(p.steps) - 1)
	p.steps[idx] += 1
	if p.count >= B_FRAMES {
		platform.set_should_close(app.window, true)
	}
}

// Mean/min/max/stddev over dts[lo:hi).
window_stats :: proc(dts: []time.Duration) -> (s: Stats) {
	if len(dts) == 0 {return}
	s.best = time.MAX_DURATION
	total: i64
	for d in dts {
		total += i64(d)
		s.best = min(s.best, d)
		s.worst = max(s.worst, d)
	}
	s.mean = time.Duration(total / i64(len(dts)))
	sum_sq: f64
	for d in dts {
		diff := f64(d - s.mean)
		sum_sq += diff * diff
	}
	s.stddev = math.sqrt(sum_sq / f64(len(dts)))
	return
}

run_loop_probe :: proc(unlimited: bool, hidden: bool) -> time.Duration {
	probe_dts = {}
	cfg := game.App_Config {
		initial_window = {title = "odyne bench", hidden = hidden},
		target_fps     = B_TARGET,
		unlimited      = unlimited,
	}
	start := time.tick_now()
	err := game.run(cfg, {user = &probe_dts, frame = probe_frame})
	wall := time.tick_since(start)
	if err != .None {
		fmt.printfln("game.run failed: %v", err)
	}
	return wall
}

section_b :: proc(hidden: bool) {
	period := time.Second / B_TARGET

	fmt.printfln(
		"--- b: %d frames, target %d fps (period %v), %s window ---",
		B_FRAMES,
		B_TARGET,
		period,
		hidden ? "HIDDEN" : "VISIBLE",
	)

	wall := run_loop_probe(false, hidden)
	all := window_stats(probe_dts.dts[:probe_dts.count])
	early := window_stats(probe_dts.dts[1:301]) // frame 0's dt is 0 by contract, so start at 1
	late := window_stats(probe_dts.dts[max(0, probe_dts.count - 300):probe_dts.count])

	report :: proc(label: string, s: Stats) {
		fmt.printfln(
			"  %-14s mean %-11s min %-11s max %-11s stddev %.3fms",
			label,
			fmt.tprintf("%v", s.mean),
			fmt.tprintf("%v", s.best),
			fmt.tprintf("%v", s.worst),
			s.stddev / 1e6,
		)
	}
	report("all frames", all)
	report("frames 1-300", early)
	report("last 300", late)

	ideal := time.Duration(i64(probe_dts.count) * i64(period))
	fmt.printfln(
		"  cumulative: elapsed %v vs ideal %v -> slippage %v (%.4f%% slow)",
		probe_dts.elapsed,
		ideal,
		probe_dts.elapsed - ideal,
		100.0 * f64(probe_dts.elapsed - ideal) / f64(ideal),
	)
	fmt.printf("  steps/frame histogram: ")
	for n, i in probe_dts.steps {
		if n > 0 {fmt.printf("%d:%d  ", i, n)}
	}
	fmt.printfln("\n  wall time for the paced run: %v", wall)

	unlimited_wall := run_loop_probe(true, hidden)
	fmt.printfln(
		"  same %d frames UNLIMITED: %v wall (%.0f fps) -- %.0fx faster, and one core busy",
		probe_dts.count,
		unlimited_wall,
		f64(probe_dts.count) / time.duration_seconds(unlimited_wall),
		f64(wall) / f64(unlimited_wall),
	)
}

// ─────────────────────────────────────────────────────────────────────────────
// (c) step-count histogram
// ─────────────────────────────────────────────────────────────────────────────

section_c :: proc() {
	fmt.println("--- c: steps per frame, 50 Hz simulation, 2000 frames per rate ---")
	fmt.printfln(
		"%-12s %8s %8s %8s %8s %12s %12s",
		"render",
		"0 steps",
		"1",
		"2",
		"3+",
		"mean/frame",
		"expected",
	)

	for fps in ([]int{30, 50, 60, 100, 144}) {
		period := time.Second / time.Duration(fps)
		p: timing.Pacer
		timing.pacer_init(&p, FIXED)
		hist: [4]int
		for _ in 0 ..< 2000 {
			got := timing.pacer_advance(&p, period)
			hist[min(got.count, 3)] += 1
		}
		mean := f64(p.steps_taken) / 2000.0
		fmt.printfln(
			"%-12s %8s %8s %8s %8s %12s %12s",
			fmt.tprintf("%d fps", fps),
			fmt.tprintf("%d", hist[0]),
			fmt.tprintf("%d", hist[1]),
			fmt.tprintf("%d", hist[2]),
			fmt.tprintf("%d", hist[3]),
			fmt.tprintf("%.3f", mean),
			fmt.tprintf("%.3f", 50.0 / f64(fps)),
		)
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// (d) timeline exactness
// ─────────────────────────────────────────────────────────────────────────────

rng_next :: proc(state: ^u64) -> u64 {
	x := state^
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	state^ = x
	return x
}

section_d :: proc() {
	fmt.println("--- d: sim-time bookkeeping over 100,000 jittered frames ---")

	p: timing.Pacer
	timing.pacer_init(&p, FIXED)
	acc_i64: time.Duration
	acc_f32: f32
	step_f32 := f32(time.duration_seconds(FIXED))
	seed: u64 = 0x9E3779B97F4A7C15
	fed: time.Duration

	for _ in 0 ..< 100_000 {
		dt := time.Duration(rng_next(&seed) % 40_000_001)
		fed += dt
		got := timing.pacer_advance(&p, dt)
		for _ in 0 ..< got.count {
			acc_i64 += FIXED
			acc_f32 += step_f32
		}
	}

	derived := timing.sim_time(&p)
	fmt.printfln("  steps taken:            %d", p.steps_taken)
	fmt.printfln("  derived steps*fixed_dt: %v  (the reference)", derived)
	fmt.printfln("  accumulated in i64 ns:  %v  error %v", acc_i64, acc_i64 - derived)
	f32_as_ns := time.Duration(f64(acc_f32) * 1e9)
	fmt.printfln(
		"  accumulated in f32 s:   %v  error %v",
		f32_as_ns,
		f32_as_ns - derived,
	)
	fmt.printfln("  conservation: fed %v == sim %v + acc %v -> %v", fed, derived, p.accumulator, fed == derived + p.accumulator)

	// The 60 Hz residue, for contrast with the 50 Hz default.
	steps := i64(100_000)
	r60 := time.Second / 60
	shortfall := time.Duration(steps) * (time.Duration(1_000_000_000 / 60) - r60) // 0 by construction
	exact60_ns := f64(steps) * (1e9 / 60.0)
	fmt.printfln(
		"  60 Hz step is %v; %d steps land %.3f ms short of exact 60 Hz",
		r60,
		steps,
		(exact60_ns - f64(i64(steps) * i64(r60))) / 1e6,
	)
	fmt.printfln(
		"  50 Hz step is %v; %d steps land %.3f ms short of exact 50 Hz (shortfall const %v)",
		FIXED,
		steps,
		(f64(steps) * (1e9 / 50.0) - f64(i64(steps) * i64(FIXED))) / 1e6,
		shortfall,
	)
}

// ─────────────────────────────────────────────────────────────────────────────
// (e) the spiral, under each bound
// ─────────────────────────────────────────────────────────────────────────────

HITCH :: 2 * time.Second
NORMAL :: time.Duration(16_666_666)
AFTER :: 10 // normal frames simulated after the hitch

// Real clock + real pacer: the clamp is the clock's, so this is the engine's actual behaviour.
spiral_with_clock :: proc(max_dt, clamp_dt: time.Duration) -> (hitch_steps: int, debt: time.Duration) {
	c: timing.Frame_Clock
	timing.clock_init(&c, at(0), max_dt, clamp_dt)
	p: timing.Pacer
	timing.pacer_init(&p, FIXED)

	now: i64 = 0
	// One normal frame, then the hitch, then AFTER normal frames.
	now += i64(NORMAL)
	timing.pacer_advance(&p, timing.frame_start(&c, at(now)))

	now += i64(HITCH)
	hitch_steps = timing.pacer_advance(&p, timing.frame_start(&c, at(now))).count

	for _ in 0 ..< AFTER {
		now += i64(NORMAL)
		timing.pacer_advance(&p, timing.frame_start(&c, at(now)))
	}
	// Debt = real time the simulation never received.
	return hitch_steps, time.Duration(now) - timing.sim_time(&p)
}

// A step CAP instead of a dt clamp: the design we rejected. Keeps its leftovers, which is what
// makes the spiral visible.
spiral_with_cap :: proc(cap_steps: int) -> (hitch_steps: int, debt, leftover: time.Duration) {
	acc, sim: time.Duration
	feed := proc(acc, sim: ^time.Duration, dt: time.Duration, cap_steps: int) -> int {
		acc^ += dt
		n := 0
		for acc^ >= FIXED && n < cap_steps {
			acc^ -= FIXED
			sim^ += FIXED
			n += 1
		}
		return n
	}
	total: time.Duration
	total += NORMAL
	feed(&acc, &sim, NORMAL, cap_steps)
	total += HITCH
	hitch_steps = feed(&acc, &sim, HITCH, cap_steps)
	for _ in 0 ..< AFTER {
		total += NORMAL
		feed(&acc, &sim, NORMAL, cap_steps)
	}
	return hitch_steps, total - sim, acc
}

section_e :: proc() {
	fmt.printfln("--- e: a %v hitch at a %v step, then %d normal frames ---", HITCH, FIXED, AFTER)

	none_steps, none_debt := spiral_with_clock(0, 0) // max_dt <= 0 disables clamping entirely
	fmt.printfln(
		"  no bound at all:        hitch frame ran %4d steps   debt %v",
		none_steps,
		none_debt,
	)

	clamp_steps, clamp_debt := spiral_with_clock(100 * time.Millisecond, FIXED)
	fmt.printfln(
		"  dt clamp (the engine):  hitch frame ran %4d steps   debt %v",
		clamp_steps,
		clamp_debt,
	)

	cap_steps, cap_debt, leftover := spiral_with_cap(5)
	fmt.printfln(
		"  step cap of 5 only:     hitch frame ran %4d steps   debt %v   LEFTOVER STILL QUEUED %v",
		cap_steps,
		cap_debt,
		leftover,
	)
	fmt.printfln(
		"    (that leftover is %d further steps owed after the hitch is over -- the spiral)",
		i64(leftover) / i64(FIXED),
	)

	fmt.printfln(
		"  NOTE alpha: a kept leftover of %v over a %v step is alpha %.2f -- outside [0,1)",
		leftover,
		FIXED,
		f64(leftover) / f64(FIXED),
	)
}

// ─────────────────────────────────────────────────────────────────────────────
// (f) overhead
// ─────────────────────────────────────────────────────────────────────────────

section_f :: proc() {
	N :: 5_000_000
	budget := f64(16_666_666)
	fmt.printfln("--- f: per-frame overhead, %d iterations, as %% of a 16.67 ms budget ---", N)

	bench :: proc(label: string, n: int, ns_total: time.Duration, budget: f64) {
		per := f64(ns_total) / f64(n)
		fmt.printfln(
			"  %-34s %9s   %s%% of a frame",
			label,
			fmt.tprintf("%.2f ns", per),
			fmt.tprintf("%.6f", 100.0 * per / budget),
		)
	}

	{
		p: timing.Pacer
		timing.pacer_init(&p, FIXED)
		start := time.tick_now()
		acc: int
		for _ in 0 ..< N {
			acc += timing.pacer_advance(&p, NORMAL).count
		}
		bench(fmt.tprintf("pacer_advance (%d steps)", acc), N, time.tick_since(start), budget)
	}
	{
		h: timing.Frame_History
		start := time.tick_now()
		for i in 0 ..< N {
			timing.history_push(&h, time.Duration(i))
		}
		bench("history_push", N, time.tick_since(start), budget)
	}
	{
		h: timing.Frame_History
		for i in 0 ..< 100 {timing.history_push(&h, time.Duration(i))}
		start := time.tick_now()
		total: time.Duration
		for _ in 0 ..< N {
			total += timing.history_average(&h)
		}
		bench("history_average (O(1) via sum)", N, time.tick_since(start), budget)
		start = time.tick_now()
		for _ in 0 ..< N {
			total += timing.history_min(&h) + timing.history_max(&h)
		}
		bench("history_min + history_max (scans)", N, time.tick_since(start), budget)
		if total == 0 {fmt.println()} // keep the accumulator observable
	}
	{
		c: timing.Frame_Clock
		timing.clock_init(&c, at(0), 100 * time.Millisecond, FIXED)
		start := time.tick_now()
		for i in 0 ..< N {
			timing.frame_start(&c, at(i64(i + 1) * i64(NORMAL)))
		}
		bench("frame_start (incl. history push)", N, time.tick_since(start), budget)
	}
	{
		start := time.tick_now()
		total: i64
		for _ in 0 ..< N {
			total += i64(time.tick_now()._nsec)
		}
		bench("time.tick_now", N, time.tick_since(start), budget)
		if total == 0 {fmt.println()}
	}
}

// ─────────────────────────────────────────────────────────────────────────────

SECTIONS := [][2]string {
	{"a1", "pacing baseline, cold"},
	{"a2", "pacing baseline, after platform.init"},
	{"a3", "pacing baseline, + timeBeginPeriod(1)"},
	{"b", "frame pacing under the real loop, hidden window"},
	{"bv", "frame pacing under the real loop, visible window"},
}

run_section :: proc(name: string) -> bool {
	switch name {
	case "a1":
		section_a1()
	case "a2":
		section_a2()
	case "a3":
		section_a3()
	case "b":
		section_b(true)
	case "bv":
		section_b(false)
	case "c":
		section_c()
	case "d":
		section_d()
	case "e":
		section_e()
	case "f":
		section_f()
	case:
		return false
	}
	return true
}

main :: proc() {
	// Child mode: one section, so timer-resolution state cannot leak between measurements.
	for arg in os.args[1:] {
		if strings.has_prefix(arg, "--section=") {
			if !run_section(arg[len("--section="):]) {
				fmt.printfln("no such section: %s", arg)
				os.exit(1)
			}
			return
		}
	}

	fmt.printfln("odyne m11-02 main-loop bench on %v\n", ODIN_OS)

	// Sections that touch real time or the platform get their own process.
	for s in SECTIONS {
		state, stdout, stderr, err := os.process_exec(
			{command = {os.args[0], fmt.tprintf("--section=%s", s[0])}},
			context.allocator,
		)
		defer delete(stdout)
		defer delete(stderr)
		if err != nil {
			fmt.printfln("could not spawn section %s: %v", s[0], err)
			continue
		}
		os.write(os.stdout, stdout)
		os.write(os.stderr, stderr)
		if !state.success {
			fmt.printfln("section %s exited %v", s[0], state.exit_code)
		}
		fmt.println()
	}

	// The rest is arithmetic: no clock, no platform, no isolation needed.
	section_c()
	fmt.println()
	section_d()
	fmt.println()
	section_e()
	fmt.println()
	section_f()
}
