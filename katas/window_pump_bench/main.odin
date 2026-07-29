package main

// Tutor-run measurement for lesson m10-01: the platform window.
//   (1) empty poll_events cost — the per-frame overhead the engine pays forever
//   (2) should_close query cost — the other per-frame call in the loop condition
//   (3) init and create_window(visible) one-shot wall times
// The window is visible for the run's duration (~a second of black flash) — that IS
// the init→visible measurement. should_close accumulates into a printed value so
// -o:speed can't elide the loop.
//
// Run:  odin run katas/window_pump_bench -o:speed -collection:engine=engine

import "core:fmt"
import "core:time"
import "engine:platform"

PUMP_N :: 1_000_000
QUERY_N :: 10_000_000

main :: proc() {
	t0 := time.tick_now()
	platform.init()
	t1 := time.tick_now()
	h, err := platform.create_window({title = "odyne pump bench"})
	t2 := time.tick_now()
	assert(err == .None, "bench window must create")

	for _ in 0 ..< 16 { 	// drain creation-time messages before timing
		platform.poll_events()
	}

	p0 := time.tick_now()
	for _ in 0 ..< PUMP_N {
		platform.poll_events()
	}
	pump_ns := f64(time.duration_nanoseconds(time.tick_since(p0))) / f64(PUMP_N)

	acc := 0
	q0 := time.tick_now()
	for _ in 0 ..< QUERY_N {
		if platform.should_close(h) {
			acc += 1
		}
	}
	query_ns := f64(time.duration_nanoseconds(time.tick_since(q0))) / f64(QUERY_N)

	platform.shutdown()

	init_ms := f64(time.duration_nanoseconds(time.tick_diff(t0, t1))) / 1e6
	create_ms := f64(time.duration_nanoseconds(time.tick_diff(t1, t2))) / 1e6
	fmt.printfln("init             : %8.3f ms", init_ms)
	fmt.printfln("create (visible) : %8.3f ms", create_ms)
	fmt.printfln("empty poll_events: %8.1f ns/frame  (N=%d)", pump_ns, PUMP_N)
	fmt.printfln("should_close     : %8.2f ns/query  (N=%d, acc=%d)", query_ns, QUERY_N, acc)
}
