package main

// Tier 2 — the portable window contract, asserted through the PUBLIC API against REAL
// windows, on every platform. Traces to the `platform-window` spec delta.
//
// Every window here is `hidden = true`: a real, fully functional native window that is
// never ordered front. That is the m10-01 concept, and it is sufficient — the reason the
// old portable suite needed a *headless* window (no native window at all) was that
// `odin test` could not create one on macOS. This harness can, so `hidden` is the only
// concept left and nothing test-shaped has to exist in `package platform`.
//
// NOT HERE, DELIBERATELY:
//   - Anything reaching `Window_State`. This package cannot see it.

import "core:testing"
import "engine:platform"

PORTABLE_WINDOW_TESTS := []Test_Case {
	{"window/lifecycle", test_lifecycle},
	{"window/shutdown_stales_handles", test_shutdown_stales_handles},
	{"window/zii_desc_applies_defaults", test_zii_desc_applies_defaults},
	{"window/explicit_size_honored", test_explicit_size_honored},
	{"window/close_is_recorded_not_obeyed", test_close_is_recorded_not_obeyed},
	{"window/invalid_handles_are_safe", test_invalid_handles_are_safe},
	{"window/stale_handle_grammar", test_stale_handle_grammar},
	{"window/mutators_apply_on_live_handles", test_mutators_apply_on_live_handles},
	{"window/windows_are_independent", test_windows_are_independent},
	{"window/pump_is_safe_with_no_windows", test_pump_is_safe_with_no_windows},
	{"window/frame_coherence", test_frame_coherence},
	{"window/framebuffer_is_a_scale_of_client", test_framebuffer_is_a_scale_of_client},
	{"window/exhausting_the_pool_fails_cleanly", test_exhausting_the_pool_fails_cleanly},
}

// opened creates a hidden window and asserts it came out valid, so a failure to create
// reports once here rather than as a cascade of confusing downstream expectations.
opened :: proc(t: ^testing.T, desc: platform.Window_Desc = {}) -> (platform.Window_Handle, bool) {
	d := desc
	d.hidden = true
	h, err := platform.create_window(d)
	if !testing.expect_value(t, err, platform.Window_Error.None) {
		return 0, false
	}
	if !testing.expect(t, h != platform.Window_Handle(0), "window must not be the zero handle") {
		return 0, false
	}
	return h, true
}

test_lifecycle :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	h, ok := opened(t)
	if !ok {return}

	testing.expect(t, platform.is_open(h), "created window must report open")
	testing.expect_value(t, platform.destroy_window(h), platform.Window_Error.None)
	testing.expect(t, !platform.is_open(h), "destroy must stale the handle")
}

test_shutdown_stales_handles :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)

	h, ok := opened(t)
	if !ok {
		platform.shutdown()
		return
	}

	platform.shutdown() // must evict everything and free all state (the leak check binds here)
	testing.expect(t, !platform.is_open(h), "shutdown must stale outstanding handles")
}

test_zii_desc_applies_defaults :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	h, ok := opened(t) // otherwise ZII
	if !ok {return}

	testing.expect_value(t, platform.client_size(h), [2]i32{1280, 720})
}

test_explicit_size_honored :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	h, ok := opened(t, {title = "odyne-test", width = 640, height = 360})
	if !ok {return}

	testing.expect_value(t, platform.client_size(h), [2]i32{640, 360})
}

test_close_is_recorded_not_obeyed :: proc(t: ^testing.T) {
	// SDL reports the ✕ as SDL_EVENT_WINDOW_CLOSE_REQUESTED and destroys nothing on its
	// own, so the request/command split the engine promises is the one the OS already
	// gives it. Asserted here through the API; the ✕ itself is covered at the demo
	// checkpoint rather than by a synthesized event.
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	h, ok := opened(t)
	if !ok {return}

	testing.expect(t, !platform.should_close(h), "fresh window must not report close-requested")
	testing.expect_value(t, platform.set_should_close(h), platform.Window_Error.None)

	testing.expect(t, platform.should_close(h), "close request must be observable")
	testing.expect(t, platform.is_open(h), "close is a REQUEST — the window must still be open")

	testing.expect_value(t, platform.set_should_close(h, false), platform.Window_Error.None)
	testing.expect(t, !platform.should_close(h), "clearing the request must be observable")
}

test_invalid_handles_are_safe :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	_, ok := opened(t) // positive guard: the system works
	if !ok {return}

	zero: platform.Window_Handle
	testing.expect(t, !platform.is_open(zero), "zero handle must never resolve")
	testing.expect(t, !platform.should_close(zero), "zero handle must answer false")
	testing.expect(t, !platform.has_focus(zero), "zero handle must answer unfocused")
	testing.expect_value(t, platform.client_size(zero), [2]i32{0, 0})
	testing.expect_value(t, platform.framebuffer_size(zero), [2]i32{0, 0})
	testing.expect_value(t, platform.destroy_window(zero), platform.Window_Error.Invalid_Handle)

	junk := platform.Window_Handle(0xDEAD_BEEF_F00D_CAFE)
	testing.expect(t, !platform.is_open(junk), "garbage handle must never resolve")
	testing.expect_value(t, platform.framebuffer_size(junk), [2]i32{0, 0})
	testing.expect_value(t, platform.destroy_window(junk), platform.Window_Error.Invalid_Handle)
}

test_stale_handle_grammar :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	h, ok := opened(t)
	if !ok {return}
	testing.expect_value(t, platform.destroy_window(h), platform.Window_Error.None)

	// Queries answer benign zeros; mutators report the error.
	testing.expect(t, !platform.is_open(h), "destroyed handle must not report open")
	testing.expect(t, !platform.should_close(h), "stale handle must answer false, not crash")
	testing.expect_value(t, platform.client_size(h), [2]i32{0, 0})
	testing.expect_value(t, platform.framebuffer_size(h), [2]i32{0, 0})
	testing.expect_value(t, platform.destroy_window(h), platform.Window_Error.Invalid_Handle)
	testing.expect_value(t, platform.set_should_close(h), platform.Window_Error.Invalid_Handle)
	testing.expect_value(
		t,
		platform.set_window_title(h, "nope"),
		platform.Window_Error.Invalid_Handle,
	)
}

test_mutators_apply_on_live_handles :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	h, ok := opened(t)
	if !ok {return}

	testing.expect_value(t, platform.set_should_close(h), platform.Window_Error.None)
	testing.expect(t, platform.should_close(h), "set_should_close(true) must be observable")
	testing.expect_value(t, platform.set_window_title(h, "renamed"), platform.Window_Error.None)
	testing.expect_value(t, platform.set_window_title(h, ""), platform.Window_Error.None)
	testing.expect_value(
		t,
		platform.set_window_title(h, "ünïcødé ✕"),
		platform.Window_Error.None,
	)
}

test_windows_are_independent :: proc(t: ^testing.T) {
	// Destroying w1 makes the pool swap-relocate w2's state. Every backend's event routing
	// has to survive that — the SDL backend resolves an SDL_WindowID by scanning the live
	// pool contents for exactly this reason: no cached index outlives a relocation.
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	w1, ok1 := opened(t, {title = "one", width = 640, height = 360})
	w2, ok2 := opened(t, {title = "two", width = 800, height = 450})
	if !ok1 || !ok2 {return}

	testing.expect_value(t, platform.set_should_close(w2), platform.Window_Error.None)
	testing.expect_value(t, platform.destroy_window(w1), platform.Window_Error.None)

	testing.expect(t, platform.is_open(w2), "surviving window must still be open")
	testing.expect_value(t, platform.client_size(w2), [2]i32{800, 450})
	testing.expect(t, platform.should_close(w2), "survivor's state must survive relocation")
	testing.expect(t, !platform.should_close(w1), "stale handle must not report survivor's state")

	// And the survivor must still be mutable through its own handle after relocating.
	testing.expect_value(t, platform.set_window_title(w2, "still two"), platform.Window_Error.None)
}

test_pump_is_safe_with_no_windows :: proc(t: ^testing.T) {
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	platform.poll_events() // must not block, must not crash with an empty pool
	platform.poll_events()
	testing.expect(t, true, "an idle pump with no windows must return")
}

test_frame_coherence :: proc(t: ^testing.T) {
	// platform-window: "Queries agree within a frame". Two reads with no intervening pump
	// must return the same value — the property that makes a frame's view of the world
	// self-consistent. SDL's queue gives this for free: every state write happens inside
	// poll_events, so nothing can change under a frame that is already reading.
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	h, ok := opened(t, {width = 640, height = 360})
	if !ok {return}

	first := platform.client_size(h)
	second := platform.client_size(h)
	testing.expect_value(t, first, second)
	testing.expect_value(t, first, [2]i32{640, 360})

	testing.expect_value(t, platform.has_focus(h), platform.has_focus(h))
	testing.expect_value(t, platform.should_close(h), platform.should_close(h))
	testing.expect_value(t, platform.framebuffer_size(h), platform.framebuffer_size(h))
}

test_framebuffer_is_a_scale_of_client :: proc(t: ^testing.T) {
	// design.md §6: client_size is LOGICAL, framebuffer_size is PIXELS. The portable
	// invariant is the relationship, not the number — this machine's scale factor is not
	// the contract. GLFW draws the same line between screen coordinates and framebuffer
	// size for exactly this reason [[GLFW]](https://www.glfw.org/docs/latest/window_guide.html).
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	h, ok := opened(t, {width = 640, height = 360})
	if !ok {return}

	client := platform.client_size(h)
	fb := platform.framebuffer_size(h)

	testing.expect(t, fb.x > 0 && fb.y > 0, "a live window's framebuffer must be non-empty")
	testing.expect(
		t,
		fb.x >= client.x && fb.y >= client.y,
		"framebuffer must not be smaller than the logical size",
	)
	testing.expectf(
		t,
		fb.x % client.x == 0 && fb.y % client.y == 0,
		"framebuffer %v must be an integer scale of client %v",
		fb,
		client,
	)
	testing.expectf(
		t,
		fb.x / client.x == fb.y / client.y,
		"framebuffer %v must scale both axes equally from client %v",
		fb,
		client,
	)
}

test_exhausting_the_pool_fails_cleanly :: proc(t: ^testing.T) {
	// The pool is bounded (MAX_WINDOWS is package-private, so this asserts the BEHAVIOUR:
	// creation past the limit reports .Create_Failed and leaves the live windows intact —
	// it must not crash, and it must not leak the native window it half-made).
	testing.expect_value(t, platform.init(), platform.Window_Error.None)
	defer platform.shutdown()

	handles: [dynamic]platform.Window_Handle
	defer delete(handles)

	saw_failure := false
	for _ in 0 ..< 16 {
		h, err := platform.create_window({hidden = true, width = 320, height = 240})
		if err != .None {
			testing.expect_value(t, err, platform.Window_Error.Create_Failed)
			testing.expect_value(t, h, platform.Window_Handle(0))
			saw_failure = true
			break
		}
		append(&handles, h)
	}

	testing.expect(t, saw_failure, "creation past the pool limit must report .Create_Failed")
	for h in handles {
		testing.expect(t, platform.is_open(h), "a failed create must not disturb live windows")
	}
}
