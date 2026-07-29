package main

// Tier 2 — the input contract reachable through the PUBLIC API, on a real window.
//
// READ THIS BEFORE ADDING TO IT.
//
// This package cannot see `Window_State`, `record_key` or `get_state`, so it cannot inject
// input. That is not a gap in the harness — it is the harness telling you where two
// different things had been fused together:
//
//   1. The STATE MACHINE — half-transition counting, edge derivation, the retire boundary,
//      sub-frame taps, saturation. This is pure logic over an `Input_State`. It needs no
//      window, no handle, no pool and no OS. It belongs in `engine/platform/input_test.odin`
//      under `odin test`, operating on a bare `Input_State{}` value. Today those tests take
//      a `^Window_State` fished out of the pool via a headless window, which is why they
//      look like they need a window when they do not.
//
//   2. The WIRING — that a real OS event reaches the right window's state and shows up in
//      the right query. This DOES need a window and a pump, and driving it needs a
//      synthesized event. `SDL_PushEvent` makes that portable now (see
//      `katas/input_pump_bench`, which floods the pump exactly that way) — so unlike the
//      Win32/Cocoa era there is no per-OS suite it has to live in. Nothing asserts it yet.
//
// What is left over — and what is below — is the portable part that needs a live window:
// the zero state of a fresh one, the benign answers for a dead one, and the promise that
// pumping an idle window invents nothing.

import "core:testing"
import "engine:platform"

PORTABLE_INPUT_TESTS := []Test_Case {
	{"input/fresh_window_is_quiet", test_fresh_window_is_quiet},
	{"input/queries_reject_invalid_handles", test_input_queries_reject_invalid_handles},
	{"input/idle_pump_invents_nothing", test_idle_pump_invents_nothing},
	{"input/queries_agree_within_a_frame", test_input_queries_agree_within_a_frame},
	{"input/state_is_per_window", test_input_state_is_per_window},
}

// ALL_KEYS / ALL_BUTTONS let the sweeps below assert over the whole enum rather than a
// hand-picked sample, so a key added to the public set is covered the day it lands.
sweep_keys :: proc(t: ^testing.T, h: platform.Window_Handle, msg: string) {
	for k in platform.Key {
		testing.expectf(t, !platform.key_down(h, k), "%s: %v must not report down", msg, k)
		testing.expectf(t, !platform.key_pressed(h, k), "%s: %v must not report a press", msg, k)
		testing.expectf(
			t,
			!platform.key_released(h, k),
			"%s: %v must not report a release",
			msg,
			k,
		)
	}
	for b in platform.Mouse_Button {
		testing.expectf(t, !platform.mouse_down(h, b), "%s: %v must not report down", msg, b)
		testing.expectf(t, !platform.mouse_pressed(h, b), "%s: %v must not report a press", msg, b)
		testing.expectf(
			t,
			!platform.mouse_released(h, b),
			"%s: %v must not report a release",
			msg,
			b,
		)
	}
}

test_fresh_window_is_quiet :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	h, ok := opened(t)
	if !ok {return}

	sweep_keys(t, h, "fresh window")
	testing.expect_value(t, platform.mouse_position(h), [2]i32{0, 0})
	testing.expect_value(t, platform.mouse_wheel(h), f32(0))
}

test_input_queries_reject_invalid_handles :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	h, ok := opened(t) // positive guard: the system works
	if !ok {return}
	testing.expect(t, platform.is_open(h), "live window must be open")

	zero: platform.Window_Handle
	sweep_keys(t, zero, "zero handle")
	testing.expect_value(t, platform.mouse_position(zero), [2]i32{0, 0})
	testing.expect_value(t, platform.mouse_wheel(zero), f32(0))

	junk := platform.Window_Handle(0xDEAD_BEEF_F00D_CAFE)
	sweep_keys(t, junk, "garbage handle")
	testing.expect_value(t, platform.mouse_position(junk), [2]i32{0, 0})
	testing.expect_value(t, platform.mouse_wheel(junk), f32(0))

	// A stale handle answers like a dead one, not like the window it used to name.
	stale := h
	testing.expect_value(t, platform.destroy_window(h), platform.Window_Error.None)
	sweep_keys(t, stale, "stale handle")
	testing.expect_value(t, platform.mouse_position(stale), [2]i32{0, 0})
	testing.expect_value(t, platform.mouse_wheel(stale), f32(0))
}

test_idle_pump_invents_nothing :: proc(t: ^testing.T) {
	// The retire boundary runs on every pump. Pumping an idle hidden window must not
	// manufacture an edge, and must not leave a stale one standing either.
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	h, ok := opened(t)
	if !ok {return}

	for _ in 0 ..< 4 {
		platform.poll_events()
		sweep_keys(t, h, "after an idle pump")
		testing.expect_value(t, platform.mouse_wheel(h), f32(0))
	}
}

test_input_queries_agree_within_a_frame :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	h, ok := opened(t)
	if !ok {return}

	testing.expect_value(t, platform.mouse_position(h), platform.mouse_position(h))
	testing.expect_value(t, platform.mouse_wheel(h), platform.mouse_wheel(h))
	testing.expect_value(t, platform.key_down(h, .W), platform.key_down(h, .W))
	testing.expect_value(t, platform.mouse_down(h, .Left), platform.mouse_down(h, .Left))
}

test_input_state_is_per_window :: proc(t: ^testing.T) {
	// platform-input: "Per-window input routing" — the portable half. Two live windows each
	// carry their own input state, and destroying one must not disturb the other's, INCLUDING
	// after the pool swap-relocates it. Proving an event lands on the right one needs a
	// synthesized native event; that half is in the per-OS suites.
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	w1, ok1 := opened(t, {title = "one"})
	w2, ok2 := opened(t, {title = "two"})
	if !ok1 || !ok2 {return}

	sweep_keys(t, w1, "window one")
	sweep_keys(t, w2, "window two")

	testing.expect_value(t, platform.destroy_window(w1), platform.Window_Error.None)
	platform.poll_events()

	sweep_keys(t, w2, "survivor after relocation")
	testing.expect_value(t, platform.mouse_position(w2), [2]i32{0, 0})
	testing.expect_value(t, platform.mouse_wheel(w2), f32(0))
}
