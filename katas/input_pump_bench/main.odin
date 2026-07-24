package main

// Tutor-run measurement for lesson m10-02: platform input.
//   (1) empty poll_events cost — now includes the per-frame input retire
//       (begin_input_frame: zero all half_transition counters + wheel); the delta
//       vs m10-01's 185 ns empty pump IS the snapshot bookkeeping cost
//   (2) flooded pump ns/msg — WM_MOUSEMOVE flood (a 1000 Hz gaming mouse's message)
//       and an alternating WM_KEYDOWN/WM_KEYUP flood (worst-case: every message
//       flips a level and bumps a counter; TranslateMessage also synthesizes a
//       WM_CHAR per keydown, drained in the same pump — denominator is POSTED msgs)
//   (3) key_down / mouse_position query cost — the per-frame read path
// Window is hidden (as in the tests): a visible window could receive real user
// input mid-bench. The hwnd for flooding comes from FindWindowW — OS-side
// instrumentation, same stance as the tests' PostMessageW.
// Queries accumulate into printed values so -o:speed can't elide the loops.
//
// Run:  odin run katas/input_pump_bench -o:speed -collection:engine=engine

import "core:fmt"
import win32 "core:sys/windows"
import "core:time"
import "engine:platform"

PUMP_N :: 1_000_000
BATCH :: 1_000 // per-round posts; safely under the 10,000 queue limit
ROUNDS :: 1_000
QUERY_N :: 10_000_000

LP_KEYDOWN: win32.LPARAM : 1
LP_KEYUP: win32.LPARAM : 1 | (1 << 30) | (1 << 31)

main :: proc() {
	platform.init()
	h, err := platform.create_window({title = "odyne input bench", hidden = true})
	assert(err == .None, "bench window must create")

	hwnd := win32.FindWindowW(
		win32.utf8_to_wstring("OdyneMainClass"),
		win32.utf8_to_wstring("odyne input bench"),
	)
	assert(hwnd != nil, "bench window must be findable")

	for _ in 0 ..< 16 { // drain creation-time messages before timing
		platform.poll_events()
	}

	// (1) empty pump — PeekMessageW + one window's input retire
	p0 := time.tick_now()
	for _ in 0 ..< PUMP_N {
		platform.poll_events()
	}
	pump_ns := f64(time.duration_nanoseconds(time.tick_since(p0))) / f64(PUMP_N)

	// (1b) empty pump with 4 windows — the retire loop runs per live window, so the
	// 1→4 window slope isolates the per-window snapshot bookkeeping cost from
	// whatever PeekMessageW costs (which differs visible vs hidden).
	h2, _ := platform.create_window({title = "b2", hidden = true})
	h3, _ := platform.create_window({title = "b3", hidden = true})
	h4, _ := platform.create_window({title = "b4", hidden = true})
	for _ in 0 ..< 16 {
		platform.poll_events()
	}
	p1 := time.tick_now()
	for _ in 0 ..< PUMP_N {
		platform.poll_events()
	}
	pump4_ns := f64(time.duration_nanoseconds(time.tick_since(p1))) / f64(PUMP_N)
	retire_ns := (pump4_ns - pump_ns) / 3.0
	platform.destroy_window(h2)
	platform.destroy_window(h3)
	platform.destroy_window(h4)
	for _ in 0 ..< 16 {
		platform.poll_events()
	}

	// (2a) mousemove flood — post a batch untimed, time only the drain
	move_drain: time.Duration
	for round in 0 ..< ROUNDS {
		for i in 0 ..< BATCH {
			x := win32.LPARAM(i % 800)
			y := win32.LPARAM((round + i) % 600)
			win32.PostMessageW(hwnd, win32.WM_MOUSEMOVE, 0, y << 16 | x)
		}
		d0 := time.tick_now()
		platform.poll_events()
		move_drain += time.tick_since(d0)
	}
	move_ns := f64(time.duration_nanoseconds(move_drain)) / f64(BATCH * ROUNDS)

	// (2b) key flood — alternating down/up so every message flips level + counter
	key_drain: time.Duration
	for _ in 0 ..< ROUNDS {
		for i in 0 ..< BATCH {
			if i & 1 == 0 {
				win32.PostMessageW(hwnd, win32.WM_KEYDOWN, 'A', LP_KEYDOWN)
			} else {
				win32.PostMessageW(hwnd, win32.WM_KEYUP, 'A', LP_KEYUP)
			}
		}
		d0 := time.tick_now()
		platform.poll_events()
		key_drain += time.tick_since(d0)
	}
	key_ns := f64(time.duration_nanoseconds(key_drain)) / f64(BATCH * ROUNDS)

	// (3) query costs
	acc := 0
	q0 := time.tick_now()
	for _ in 0 ..< QUERY_N {
		if platform.key_down(h, .A) {
			acc += 1
		}
	}
	key_query_ns := f64(time.duration_nanoseconds(time.tick_since(q0))) / f64(QUERY_N)

	pos_acc: i32
	q1 := time.tick_now()
	for _ in 0 ..< QUERY_N {
		pos_acc += platform.mouse_position(h).x
	}
	pos_query_ns := f64(time.duration_nanoseconds(time.tick_since(q1))) / f64(QUERY_N)

	platform.shutdown()

	// 1000 Hz projection: a polling gaming mouse delivers ~1000 msg/s → ~16.7/frame @60fps
	msgs_per_frame := 1000.0 / 60.0
	frame_ns := msgs_per_frame * move_ns
	budget_pct := frame_ns / 16_666_667.0 * 100.0

	fmt.printfln("empty poll_events : %8.1f ns/frame  (N=%d; m10-01 baseline 185)", pump_ns, PUMP_N)
	fmt.printfln("empty pump, 4 win : %8.1f ns/frame  → retire ≈ %.1f ns/window", pump4_ns, retire_ns)
	fmt.printfln("mousemove flood   : %8.1f ns/msg    (N=%d)", move_ns, BATCH * ROUNDS)
	fmt.printfln("key flood         : %8.1f ns/msg    (N=%d posted; +WM_CHAR per down)", key_ns, BATCH * ROUNDS)
	fmt.printfln("1000 Hz mouse @60fps: %6.0f ns/frame = %.4f%% of 16.7 ms budget", frame_ns, budget_pct)
	fmt.printfln("key_down          : %8.2f ns/query  (N=%d, acc=%d)", key_query_ns, QUERY_N, acc)
	fmt.printfln("mouse_position    : %8.2f ns/query  (N=%d, acc=%d)", pos_query_ns, QUERY_N, pos_acc)
}
