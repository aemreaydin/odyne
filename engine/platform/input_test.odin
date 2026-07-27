#+private file
package platform

// Tier 1 — the input state machine as PURE LOGIC. No pool, no handle, no window, no OS.
// Runs on every platform under plain `odin test`, in parallel, with leak tracking:
//
//   odin test engine/platform -collection:engine=engine
//
// These used to fish a `^Window_State` out of the pool via a headless window, which made a
// pure state machine look like it needed a window, a handle grammar and an initialised OS.
// It never did — it needed an `Input_State`. Everything that genuinely needs a window (a
// real OS event reaching the right window's state) moved to `tests/platform`, where it runs
// on the main thread against a real window on both platforms.
//
// Note there is no `init()`, no `shutdown()` and no `Window_Handle` anywhere below. That
// absence is the point: if a test here ever needs one, the seam has drifted.

import "core:testing"

@(test)
test_edge_derivation_from_transition_counts :: proc(t: ^testing.T) {
	// The pure derivation: two or more flips always contain both an up→down and a down→up;
	// a single flip counts only in the direction it landed.
	testing.expect(t, !was_pressed(Button_State{}), "zero value is neither pressed nor released")
	testing.expect(t, !was_released(Button_State{}), "zero value is neither pressed nor released")

	testing.expect(t, was_pressed(Button_State{half_transitions = 1, ended_down = true}))
	testing.expect(t, !was_released(Button_State{half_transitions = 1, ended_down = true}))

	testing.expect(t, was_released(Button_State{half_transitions = 1, ended_down = false}))
	testing.expect(t, !was_pressed(Button_State{half_transitions = 1, ended_down = false}))

	// A sub-frame tap: level round-tripped, both edges must survive.
	testing.expect(t, was_pressed(Button_State{half_transitions = 2, ended_down = false}))
	testing.expect(t, was_released(Button_State{half_transitions = 2, ended_down = false}))
}

@(test)
test_key_level_and_press_edge :: proc(t: ^testing.T) {
	input: Input_State

	record_key(&input, .A, true)
	testing.expect(t, input.keys[.A].ended_down, "recorded key must report down")
	testing.expect(t, was_pressed(input.keys[.A]), "first frame must report the press edge")
	testing.expect(t, !was_released(input.keys[.A]), "no release happened")
	testing.expect(t, !input.keys[.B].ended_down, "other keys must be untouched")
}

@(test)
test_press_edge_lasts_one_frame :: proc(t: ^testing.T) {
	input: Input_State

	record_key(&input, .A, true)
	retire_input(&input) // empty frame: the edge retires, the level persists

	testing.expect(t, input.keys[.A].ended_down, "level persists across frames while held")
	testing.expect(t, !was_pressed(input.keys[.A]), "press edge must last exactly one frame")
}

@(test)
test_release_edge :: proc(t: ^testing.T) {
	input: Input_State

	record_key(&input, .A, true)
	retire_input(&input)
	record_key(&input, .A, false)

	testing.expect(t, !input.keys[.A].ended_down, "released key must not report down")
	testing.expect(t, was_released(input.keys[.A]), "release frame must report the release edge")
	testing.expect(t, !was_pressed(input.keys[.A]), "no press this frame")

	retire_input(&input)
	testing.expect(t, !was_released(input.keys[.A]), "release edge must last exactly one frame")
}

@(test)
test_subframe_tap_is_not_lost :: proc(t: ^testing.T) {
	// platform-input: "Sub-frame tap is not lost" — the reason the model counts transitions
	// instead of storing a level.
	input: Input_State

	record_key(&input, .Space, true)
	record_key(&input, .Space, false)

	testing.expect(t, !input.keys[.Space].ended_down, "the tap ended up")
	testing.expect(t, was_pressed(input.keys[.Space]), "the press must survive the round trip")
	testing.expect(t, was_released(input.keys[.Space]), "the release must survive the round trip")
}

@(test)
test_repeat_produces_no_edge :: proc(t: ^testing.T) {
	// platform-input: "Key repeat produces no edges" — no level flip, so no transition, by
	// construction rather than by filtering.
	input: Input_State

	record_key(&input, .A, true)
	retire_input(&input)
	record_key(&input, .A, true) // autorepeat: already down

	testing.expect(t, input.keys[.A].ended_down, "repeat keeps the key down")
	testing.expect(t, !was_pressed(input.keys[.A]), "repeat must not manufacture a press edge")
}

@(test)
test_command_modifier_is_addressable :: proc(t: ^testing.T) {
	// platform-input ADDED: "The primary command modifier is addressable".
	input: Input_State

	record_key(&input, .Left_Command, true)
	testing.expect(t, input.keys[.Left_Command].ended_down, "the command modifier must be bindable")
	testing.expect(t, !input.keys[.Right_Command].ended_down, "L and R must be independent")
}

@(test)
test_mouse_buttons_level_and_edges :: proc(t: ^testing.T) {
	input: Input_State

	record_mouse_button(&input, .Left, true)
	testing.expect(t, input.buttons[.Left].ended_down, "recorded button must report down")
	testing.expect(t, was_pressed(input.buttons[.Left]), "press edge on the first frame")
	testing.expect(t, !input.buttons[.Right].ended_down, "other buttons untouched")

	retire_input(&input)
	record_mouse_button(&input, .Left, false)
	testing.expect(t, !input.buttons[.Left].ended_down, "released button must not report down")
	testing.expect(t, was_released(input.buttons[.Left]), "release edge must be observable")
}

@(test)
test_cursor_position_signed_and_persistent :: proc(t: ^testing.T) {
	input: Input_State

	record_cursor(&input, {120, 80})
	testing.expect_value(t, input.cursor, [2]i32{120, 80})

	// Negative coordinates are legal while a drag is captured and must not become a large
	// positive artifact.
	record_cursor(&input, {-7, -3})
	testing.expect_value(t, input.cursor, [2]i32{-7, -3})

	retire_input(&input) // cursor persists across the retire boundary; only counters reset
	testing.expect_value(t, input.cursor, [2]i32{-7, -3})
}

@(test)
test_wheel_accumulates_then_resets :: proc(t: ^testing.T) {
	// platform-input: one standard wheel notch = 1.0, accumulated within the frame, reset at
	// the retire boundary. Fractions are legal — that is how a continuous device lands in
	// this unit.
	input: Input_State

	record_wheel(&input, 1.0)
	record_wheel(&input, 0.5)
	testing.expect_value(t, input.wheel, f32(1.5))

	retire_input(&input)
	testing.expect_value(t, input.wheel, f32(0))

	record_wheel(&input, -0.25) // toward the user, sub-notch: a trackpad's shape
	testing.expect_value(t, input.wheel, f32(-0.25))
}

@(test)
test_input_states_are_independent :: proc(t: ^testing.T) {
	// Two Input_States never share storage. This is the portable half of "per-window input
	// routing"; that an OS event reaches the RIGHT one is wiring, and is asserted against a
	// real window in tests/platform.
	a, b: Input_State

	record_key(&a, .W, true)
	record_cursor(&b, {10, 20})

	testing.expect(t, a.keys[.W].ended_down, "state A recorded the key")
	testing.expect(t, !b.keys[.W].ended_down, "state B must be untouched")
	testing.expect_value(t, a.cursor, [2]i32{0, 0})
	testing.expect_value(t, b.cursor, [2]i32{10, 20})
}

@(test)
test_transition_count_saturates :: proc(t: ^testing.T) {
	// half_transitions is a u8 and must saturate, never wrap — a wrap to zero would erase an
	// edge that really happened.
	input: Input_State

	for i in 0 ..< 600 {
		record_key(&input, .A, i % 2 == 0)
	}

	testing.expect(t, was_pressed(input.keys[.A]), "an edge must survive saturation")
	testing.expect(t, was_released(input.keys[.A]), "an edge must survive saturation")
}
