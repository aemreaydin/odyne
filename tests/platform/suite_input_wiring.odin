package main

// Tier 3 — the input WIRING: a real event reaches the right window's state and shows up
// in the right query, through a real pump on a real window.
//
// WHY THIS IS PORTABLE NOW
//
// Under Win32 and Cocoa this tier could not exist as one file. Driving it needed a
// synthesized native message (`PostMessageW`, an `NSEvent`), so it split into a per-OS
// suite each of which only ran on its own machine — and the Cocoa half never ran at all
// from a Windows box, or vice versa. `SDL_PushEvent` puts a synthetic event on the same
// queue the OS writes to, so one suite now drives the backend everywhere.
//
// This is the tier that catches a mis-wired scancode table, a routing bug that lands an
// event on the wrong window, or a retire that runs on the wrong side of the drain. The
// pure edge algebra underneath is tier 1 (`engine/platform/input_test.odin`); the state
// machine is not re-tested here, only the path into it.

import "core:c"
import "core:testing"
import "engine:platform"
import sdl "vendor:sdl3"

WIRING_TESTS := []Test_Case {
	{"wiring/press_edge_lasts_one_frame", test_press_edge_lasts_one_frame},
	{"wiring/autorepeat_produces_no_edge", test_autorepeat_produces_no_edge},
	{"wiring/release_edge", test_release_edge},
	{"wiring/sub_frame_tap_is_not_lost", test_sub_frame_tap_is_not_lost},
	{"wiring/modifiers_are_side_specific", test_modifiers_are_side_specific},
	{"wiring/unmapped_scancode_is_ignored", test_unmapped_scancode_is_ignored},
	{"wiring/mouse_motion_and_negatives", test_mouse_motion_and_negatives},
	{"wiring/button_edges", test_button_edges},
	{"wiring/wheel_accumulates_then_resets", test_wheel_accumulates_then_resets},
	{"wiring/focus_loss_clears_silently", test_focus_loss_clears_silently},
	{"wiring/events_route_per_window", test_events_route_per_window},
}

// wired opens a hidden window and recovers its SDL id. The id is found by scanning
// SDL's own window list for the title, NOT by reaching into `package platform` — this
// package still sees only the public surface, and the seam stays sealed.
@(private = "file")
wired :: proc(t: ^testing.T, title: string) -> (platform.Window_Handle, sdl.WindowID, bool) {
	h, err := platform.create_window({title = title, hidden = true})
	if !testing.expect_value(t, err, platform.Window_Error.None) {
		return 0, 0, false
	}

	count: c.int
	wins := sdl.GetWindows(&count)
	for i in 0 ..< count {
		if string(sdl.GetWindowTitle(wins[i])) == title {
			// Drain the creation-time traffic so a test's first pump sees only its own events.
			for _ in 0 ..< 8 {platform.poll_events()}
			return h, sdl.GetWindowID(wins[i]), true
		}
	}
	testing.expect(t, false, "the created window must be findable in SDL's window list")
	return 0, 0, false
}

@(private = "file")
push_key :: proc(wid: sdl.WindowID, sc: sdl.Scancode, down: bool, repeat := false) {
	ev := sdl.Event {
		key = {
			type = down ? .KEY_DOWN : .KEY_UP,
			windowID = wid,
			scancode = sc,
			down = down,
			repeat = repeat,
		},
	}
	_ = sdl.PushEvent(&ev)
}

@(private = "file")
push_button :: proc(wid: sdl.WindowID, button: u8, down: bool) {
	ev := sdl.Event {
		button = {
			type = down ? .MOUSE_BUTTON_DOWN : .MOUSE_BUTTON_UP,
			windowID = wid,
			button = button,
			down = down,
		},
	}
	_ = sdl.PushEvent(&ev)
}

test_press_edge_lasts_one_frame :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()
	h, wid, ok := wired(t, "wiring-press")
	if !ok {return}

	push_key(wid, .W, true)
	platform.poll_events()
	testing.expect(t, platform.key_down(h, .W), "W must report down once the event is pumped")
	testing.expect(t, platform.key_pressed(h, .W), "W must report a press edge that frame")
	testing.expect(t, !platform.key_released(h, .W), "a press must not also read as a release")

	platform.poll_events()
	testing.expect(t, platform.key_down(h, .W), "the level must persist across frames")
	testing.expect(t, !platform.key_pressed(h, .W), "the press edge must be gone the next frame")
}

test_autorepeat_produces_no_edge :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()
	h, wid, ok := wired(t, "wiring-repeat")
	if !ok {return}

	push_key(wid, .W, true)
	platform.poll_events()
	push_key(wid, .W, true, repeat = true)
	platform.poll_events()

	testing.expect(t, platform.key_down(h, .W), "an autorepeat must leave the key down")
	testing.expect(
		t,
		!platform.key_pressed(h, .W),
		"an autorepeat must NOT manufacture a press edge",
	)
}

test_release_edge :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()
	h, wid, ok := wired(t, "wiring-release")
	if !ok {return}

	push_key(wid, .W, true)
	platform.poll_events()
	push_key(wid, .W, false)
	platform.poll_events()

	testing.expect(t, !platform.key_down(h, .W), "W must not report down after the key-up")
	testing.expect(t, platform.key_released(h, .W), "W must report a release edge that frame")

	platform.poll_events()
	testing.expect(
		t,
		!platform.key_released(h, .W),
		"the release edge must be gone the next frame",
	)
}

test_sub_frame_tap_is_not_lost :: proc(t: ^testing.T) {
	// The whole reason input is a transition COUNT and not a level diff: a tap that opens
	// and closes between two pumps must still be visible as both edges.
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()
	h, wid, ok := wired(t, "wiring-tap")
	if !ok {return}

	push_key(wid, .Q, true)
	push_key(wid, .Q, false)
	platform.poll_events()

	testing.expect(t, platform.key_pressed(h, .Q), "a sub-frame tap must still show a press edge")
	testing.expect(
		t,
		platform.key_released(h, .Q),
		"a sub-frame tap must still show a release edge",
	)
	testing.expect(t, !platform.key_down(h, .Q), "a sub-frame tap must not end the frame down")
}

test_modifiers_are_side_specific :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()
	h, wid, ok := wired(t, "wiring-mods")
	if !ok {return}

	push_key(wid, .LSHIFT, true)
	platform.poll_events()
	testing.expect(
		t,
		platform.key_down(h, .Left_Shift),
		"left shift must be observable on its own",
	)
	testing.expect(t, !platform.key_down(h, .Right_Shift), "the right variant must be independent")

	push_key(wid, .LSHIFT, false)
	push_key(wid, .RGUI, true)
	platform.poll_events()
	testing.expect(
		t,
		platform.key_down(h, .Right_Command),
		"GUI/Command must map side-specifically",
	)
	testing.expect(t, !platform.key_down(h, .Left_Command), "the left variant must be independent")
}

test_unmapped_scancode_is_ignored :: proc(t: ^testing.T) {
	// SDL has ~240 scancodes and `Key` has 69. An unmapped one must be dropped before it
	// can record anything — not crash, and not alias onto some other key.
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()
	h, wid, ok := wired(t, "wiring-unmapped")
	if !ok {return}

	push_key(wid, .INSERT, true)
	push_key(wid, .PRINTSCREEN, true)
	platform.poll_events()

	sweep_keys(t, h, "after unmapped scancodes")
}

test_mouse_motion_and_negatives :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()
	h, wid, ok := wired(t, "wiring-motion")
	if !ok {return}

	ev := sdl.Event {
		motion = {type = .MOUSE_MOTION, windowID = wid, x = 120, y = 45},
	}
	_ = sdl.PushEvent(&ev)
	platform.poll_events()
	testing.expect_value(t, platform.mouse_position(h), [2]i32{120, 45})

	// A drag above or left of the client area must read negative, not wrap to a large
	// positive — the classic Win32 LOWORD sign bug, asserted here for any backend.
	ev.motion.x, ev.motion.y = -12, -34
	_ = sdl.PushEvent(&ev)
	platform.poll_events()
	testing.expect_value(t, platform.mouse_position(h), [2]i32{-12, -34})
}

test_button_edges :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()
	h, wid, ok := wired(t, "wiring-buttons")
	if !ok {return}

	push_button(wid, sdl.BUTTON_RIGHT, true)
	platform.poll_events()
	testing.expect(t, platform.mouse_down(h, .Right), "right button must report down")
	testing.expect(t, platform.mouse_pressed(h, .Right), "right button must report a press edge")
	testing.expect(t, !platform.mouse_down(h, .Left), "an untouched button must stay quiet")

	push_button(wid, sdl.BUTTON_RIGHT, false)
	platform.poll_events()
	testing.expect(t, !platform.mouse_down(h, .Right), "right button must report up")
	testing.expect(
		t,
		platform.mouse_released(h, .Right),
		"right button must report a release edge",
	)
}

test_wheel_accumulates_then_resets :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()
	h, wid, ok := wired(t, "wiring-wheel")
	if !ok {return}

	for v in ([2]f32{1.0, 0.5}) {
		ev := sdl.Event {
			wheel = {type = .MOUSE_WHEEL, windowID = wid, y = v},
		}
		_ = sdl.PushEvent(&ev)
	}
	platform.poll_events()
	testing.expect_value(t, platform.mouse_wheel(h), f32(1.5))

	platform.poll_events()
	testing.expect_value(t, platform.mouse_wheel(h), f32(0))
}

test_focus_loss_clears_silently :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()
	h, wid, ok := wired(t, "wiring-focus")
	if !ok {return}

	push_key(wid, .W, true)
	push_button(wid, sdl.BUTTON_LEFT, true)
	motion := sdl.Event {
		motion = {type = .MOUSE_MOTION, windowID = wid, x = 77, y = 88},
	}
	_ = sdl.PushEvent(&motion)
	platform.poll_events()
	testing.expect(t, platform.key_down(h, .W), "precondition: key held")
	testing.expect(t, platform.mouse_down(h, .Left), "precondition: button held")

	focus_lost := sdl.Event {
		window = {type = .WINDOW_FOCUS_LOST, windowID = wid},
	}
	_ = sdl.PushEvent(&focus_lost)
	platform.poll_events()

	// Silently: a key held across an Alt-Tab must not read as released on return, or the
	// game fires a jump the player never asked for.
	testing.expect(t, !platform.key_down(h, .W), "focus loss must clear the held key")
	testing.expect(t, !platform.key_released(h, .W), "focus loss must NOT produce a release edge")
	testing.expect(t, !platform.mouse_down(h, .Left), "focus loss must clear the held button")
	testing.expect(
		t,
		!platform.mouse_released(h, .Left),
		"focus loss must NOT produce a release edge",
	)
	testing.expect(t, !platform.has_focus(h), "the window must report unfocused")

	// The cursor is a position, not a transition — it survives.
	testing.expect_value(t, platform.mouse_position(h), [2]i32{77, 88})
}

test_events_route_per_window :: proc(t: ^testing.T) {
	// The half tier 2 cannot reach: not just that two windows have separate state, but
	// that an event actually lands on the one it names.
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	w1, id1, ok1 := wired(t, "wiring-route-one")
	w2, id2, ok2 := wired(t, "wiring-route-two")
	if !ok1 || !ok2 {return}
	testing.expect(t, id1 != id2, "two windows must have distinct SDL ids")

	push_key(id1, .A, true)
	platform.poll_events()
	testing.expect(t, platform.key_down(w1, .A), "the addressed window must see the key")
	testing.expect(t, !platform.key_down(w2, .A), "the other window must NOT see it")

	// And routing must survive the swap-with-last relocation that destroying w1 performs.
	testing.expect_value(t, platform.destroy_window(w1), platform.Window_Error.None)
	push_key(id2, .B, true)
	platform.poll_events()
	testing.expect(
		t,
		platform.key_down(w2, .B),
		"routing must survive the survivor being relocated",
	)
}
