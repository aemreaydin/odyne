#+private
package platform

// Tutor-written conformance tests for the m10-01 platform window. They bind to the agreed
// interface (design.md §Agreed interface) and trace to the platform-window spec delta.
// Written RED against the stub; the learner implements until green.
//
// All windows are hidden (fully functional, never shown). Tests are in-package and reach
// the private pool to fetch an hwnd when they must synthesize user actions (posting
// WM_CLOSE, resizing via SetWindowPos). Every test asserts at least one positive-path
// expectation, so the benign stub fails all of them.
//
// MUST run single-threaded — Win32 message queues are per-thread and the window system
// shares package state:
//   odin test engine/platform -collection:engine=engine -define:ODIN_TEST_THREADS=1

import "core:testing"
import win32 "core:sys/windows"
import "engine:core/containers/handle_pool"

// hwnd_of reaches into the pool for a window's native handle — test-only plumbing for
// synthesizing OS-side actions. Returns nil if the handle doesn't resolve.
hwnd_of :: proc(h: Window_Handle) -> win32.HWND {
	ptr, err := handle_pool.get_ptr(&g_window_pool, h)
	if err != .None {
		return nil
	}
	return ptr.hwnd
}

@(test)
test_lifecycle_and_shutdown :: proc(t: ^testing.T) {
	init()
	h, err := create_window({hidden = true})
	testing.expect_value(t, err, Window_Error.None)
	testing.expect(t, h != Window_Handle(0), "handle must not be the zero handle")
	testing.expect(t, is_open(h), "created window must report open")

	shutdown() // must destroy remaining windows and free all state (leak check binds here)
	testing.expect(t, !is_open(h), "shutdown must close remaining windows")
}

@(test)
test_zii_desc_applies_defaults :: proc(t: ^testing.T) {
	init()
	defer shutdown()

	h, err := create_window({hidden = true}) // otherwise ZII
	testing.expect_value(t, err, Window_Error.None)
	testing.expect_value(t, client_size(h), [2]i32{1280, 720})
}

@(test)
test_explicit_size_honored :: proc(t: ^testing.T) {
	init()
	defer shutdown()

	h, err := create_window({title = "odyne-test", width = 640, height = 360, hidden = true})
	testing.expect_value(t, err, Window_Error.None)
	testing.expect_value(t, client_size(h), [2]i32{640, 360})
}

@(test)
test_close_is_recorded_not_obeyed :: proc(t: ^testing.T) {
	init()
	defer shutdown()

	h, err := create_window({hidden = true})
	testing.expect_value(t, err, Window_Error.None)
	testing.expect(t, !should_close(h), "fresh window must not report close-requested")

	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}
	win32.PostMessageW(hwnd, win32.WM_CLOSE, 0, 0) // the ✕ button, synthesized
	poll_events()

	testing.expect(t, should_close(h), "close request must be observable after the pump")
	testing.expect(t, is_open(h), "close is a REQUEST — the window must still be open")

	testing.expect_value(t, destroy_window(h), Window_Error.None)
	testing.expect(t, !is_open(h), "destroy must close the window")
}

@(test)
test_destroy_stales_handle :: proc(t: ^testing.T) {
	init()
	defer shutdown()

	h, err := create_window({hidden = true})
	testing.expect_value(t, err, Window_Error.None)
	testing.expect_value(t, destroy_window(h), Window_Error.None)

	testing.expect(t, !is_open(h), "destroyed handle must not report open")
	testing.expect(t, !should_close(h), "stale handle must answer false, not crash")
	testing.expect_value(t, client_size(h), [2]i32{0, 0})
	testing.expect_value(t, destroy_window(h), Window_Error.Invalid_Handle) // double destroy
}

@(test)
test_invalid_handles_safe :: proc(t: ^testing.T) {
	init()
	defer shutdown()

	_, err := create_window({hidden = true}) // positive guard: the system works
	testing.expect_value(t, err, Window_Error.None)

	zero: Window_Handle
	testing.expect(t, !is_open(zero), "zero handle must never resolve")
	testing.expect(t, !should_close(zero), "zero handle must answer false")
	testing.expect_value(t, client_size(zero), [2]i32{0, 0})
	testing.expect_value(t, destroy_window(zero), Window_Error.Invalid_Handle)

	junk := Window_Handle(0xDEAD_BEEF_F00D_CAFE)
	testing.expect(t, !is_open(junk), "garbage handle must never resolve")
	testing.expect_value(t, destroy_window(junk), Window_Error.Invalid_Handle)
}

@(test)
test_resize_reflected_after_pump :: proc(t: ^testing.T) {
	init()
	defer shutdown()

	h, err := create_window({width = 640, height = 360, hidden = true})
	testing.expect_value(t, err, Window_Error.None)

	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	// Grow the client area by exactly 160×90 by growing the outer rect the same
	// amount — style-agnostic (border size cancels out).
	wr: win32.RECT
	win32.GetWindowRect(hwnd, &wr)
	win32.SetWindowPos(
		hwnd,
		nil,
		0,
		0,
		(wr.right - wr.left) + 160,
		(wr.bottom - wr.top) + 90,
		win32.SWP_NOMOVE | win32.SWP_NOZORDER | win32.SWP_NOACTIVATE,
	)
	poll_events()

	testing.expect_value(t, client_size(h), [2]i32{800, 450})
}

@(test)
test_destroying_one_window_leaves_other_intact :: proc(t: ^testing.T) {
	// THE Q1 test: destroying w1 makes the pool swap-relocate w2's state. Because
	// GWLP_USERDATA holds w2's HANDLE (not a pointer), w2's message routing must
	// survive the relocation.
	init()
	defer shutdown()

	w1, e1 := create_window({title = "one", hidden = true})
	w2, e2 := create_window({title = "two", hidden = true})
	testing.expect_value(t, e1, Window_Error.None)
	testing.expect_value(t, e2, Window_Error.None)

	testing.expect_value(t, destroy_window(w1), Window_Error.None)
	testing.expect(t, is_open(w2), "surviving window must still be open")

	hwnd2 := hwnd_of(w2) // fresh resolve AFTER the relocation
	if !testing.expect(t, hwnd2 != nil, "test plumbing: surviving hwnd must resolve") {
		return
	}
	win32.PostMessageW(hwnd2, win32.WM_CLOSE, 0, 0)
	poll_events()

	testing.expect(t, should_close(w2), "surviving window's events must still route to it")
	testing.expect(t, !should_close(w1), "stale handle must not report the survivor's events")
}
