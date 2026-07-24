#+private file
package platform

// Tutor-written conformance tests for the m10-02 platform input system. They bind to the
// agreed interface (design.md §Agreed interface) and trace to the platform-input spec
// delta. Written RED against the stubs; the learner implements until green.
//
// All windows are hidden. Tests synthesize user input by posting the real messages
// straight to the hidden window's queue with PostMessageW — deterministic and
// focus-independent (unlike SendInput, which targets whatever window the OS thinks is
// focused). lparam layouts follow the WM_KEYDOWN reference: bits 16–23 scancode,
// bit 24 extended (right Ctrl/Alt), bit 30 previous key state, bit 31 transition.
//
// MUST run single-threaded (shared package state, per-thread Win32 queues):
//   odin test engine/platform -collection:engine=engine -define:ODIN_TEST_THREADS=1

import win32 "core:sys/windows"
import "core:testing"
import "engine:core/containers/handle_pool"

VK_A: win32.WPARAM : 0x41 // letters have no VK_ constant; A is its ASCII value
VK_UNASSIGNED: win32.WPARAM : 0xE8 // documented-unassigned VK code

LP_KEYDOWN: win32.LPARAM : 1 // repeat count 1, everything else 0
LP_KEYDOWN_REPEAT: win32.LPARAM : 1 | (1 << 30) // previous-state flag: autorepeat
LP_KEYUP: win32.LPARAM : 1 | (1 << 30) | (1 << 31) // prev down + transition up
LP_EXTENDED: win32.LPARAM : 1 << 24 // right-hand Ctrl/Alt
LP_ALT_CONTEXT: win32.LPARAM : 1 << 29 // context code: Alt held (sys-key messages)

// hwnd_of reaches into the pool for a window's native handle — test-only plumbing for
// synthesizing OS-side actions. Returns nil if the handle doesn't resolve. (Deliberate
// duplicate of window_test.odin's copy: test files are self-contained by convention.)
hwnd_of :: proc(h: Window_Handle) -> win32.HWND {
	ptr, err := handle_pool.get_ptr(&g_window_pool, h)
	if err != .None {
		return nil
	}
	return ptr.hwnd
}

// pos_lparam packs signed client coordinates the way mouse messages carry them:
// x in the low word, y in the high word, both signed 16-bit.
pos_lparam :: proc(x, y: i16) -> win32.LPARAM {
	return win32.LPARAM(u32(u16(y)) << 16 | u32(u16(x)))
}

// wheel_wparam packs a wheel delta (multiples/divisions of WHEEL_DELTA=120) into the
// high word of wparam.
wheel_wparam :: proc(delta: i16) -> win32.WPARAM {
	return win32.WPARAM(u32(u16(delta)) << 16)
}

@(test)
test_input_key_level_and_press_edge :: proc(t: ^testing.T) {
	init()
	defer shutdown()
	h, err := create_window({hidden = true})
	testing.expect_value(t, err, Window_Error.None)
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(hwnd, win32.WM_KEYDOWN, VK_A, LP_KEYDOWN)
	testing.expect(
		t,
		!key_down(h, .A),
		"state is fixed at the pump — not observable before poll_events",
	)

	poll_events()
	testing.expect(t, key_down(h, .A), "held key must report down after the pump")
	testing.expect(t, key_pressed(h, .A), "first frame must report the press edge")
	testing.expect(t, !key_released(h, .A), "no release happened")
	testing.expect(t, !key_down(h, .B), "other keys must be untouched")
}

@(test)
test_input_press_edge_lasts_one_frame :: proc(t: ^testing.T) {
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(hwnd, win32.WM_KEYDOWN, VK_A, LP_KEYDOWN)
	poll_events()
	poll_events() // empty frame: edge must retire, level must persist

	testing.expect(t, key_down(h, .A), "level persists across frames while held")
	testing.expect(t, !key_pressed(h, .A), "press edge must last exactly one frame")
}

@(test)
test_input_release_edge :: proc(t: ^testing.T) {
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(hwnd, win32.WM_KEYDOWN, VK_A, LP_KEYDOWN)
	poll_events()
	win32.PostMessageW(hwnd, win32.WM_KEYUP, VK_A, LP_KEYUP)
	poll_events()

	testing.expect(t, !key_down(h, .A), "released key must not report down")
	testing.expect(t, key_released(h, .A), "release frame must report the release edge")
	testing.expect(t, !key_pressed(h, .A), "no press this frame")

	poll_events()
	testing.expect(t, !key_released(h, .A), "release edge must last exactly one frame")
}

@(test)
test_input_subframe_tap_not_lost :: proc(t: ^testing.T) {
	// THE Q1 test: down and up drain in the SAME poll. A level-only snapshot loses
	// this tap (SDL documents that failure); half-transition counts must not.
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(hwnd, win32.WM_KEYDOWN, VK_A, LP_KEYDOWN)
	win32.PostMessageW(hwnd, win32.WM_KEYUP, VK_A, LP_KEYUP)
	poll_events()

	testing.expect(t, key_pressed(h, .A), "sub-frame tap must still report its press edge")
	testing.expect(t, key_released(h, .A), "sub-frame tap must still report its release edge")
	testing.expect(t, !key_down(h, .A), "the level honestly ended up")
}

@(test)
test_input_repeat_produces_no_edge :: proc(t: ^testing.T) {
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(hwnd, win32.WM_KEYDOWN, VK_A, LP_KEYDOWN)
	poll_events()
	win32.PostMessageW(hwnd, win32.WM_KEYDOWN, VK_A, LP_KEYDOWN_REPEAT) // autorepeat
	poll_events()

	testing.expect(t, key_down(h, .A), "repeat: key still down")
	testing.expect(t, !key_pressed(h, .A), "repeat must not produce a press edge")
}

@(test)
test_input_unmapped_vk_ignored :: proc(t: ^testing.T) {
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(hwnd, win32.WM_KEYDOWN, VK_UNASSIGNED, LP_KEYDOWN)
	win32.PostMessageW(hwnd, win32.WM_KEYDOWN, VK_A, LP_KEYDOWN)
	poll_events()

	testing.expect(t, key_down(h, .A), "positive guard: the mapped key beside it still lands")
	testing.expect(t, !key_down(h, .Unknown), "unmapped VKs are ignored, not recorded on .Unknown")
	testing.expect(t, !key_pressed(h, .Unknown), "no edge for unmapped VKs")
}

@(test)
test_input_left_right_ctrl_distinguished :: proc(t: ^testing.T) {
	// wparam says only VK_CONTROL; the extended bit (lparam bit 24) says which side.
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(hwnd, win32.WM_KEYDOWN, win32.WPARAM(win32.VK_CONTROL), LP_KEYDOWN)
	poll_events()
	testing.expect(t, key_down(h, .Left_Ctrl), "non-extended VK_CONTROL is the left key")
	testing.expect(t, !key_down(h, .Right_Ctrl), "right ctrl must not fire")

	win32.PostMessageW(
		hwnd,
		win32.WM_KEYDOWN,
		win32.WPARAM(win32.VK_CONTROL),
		LP_KEYDOWN | LP_EXTENDED,
	)
	poll_events()
	testing.expect(t, key_down(h, .Right_Ctrl), "extended VK_CONTROL is the right key")
}

@(test)
test_input_syskey_records_alt :: proc(t: ^testing.T) {
	// Alt arrives as a SYS message (context code set). It must be observable as a key;
	// pass-through to DefWindowProcW is verified at the demo checkpoint (Alt+F4).
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(
		hwnd,
		win32.WM_SYSKEYDOWN,
		win32.WPARAM(win32.VK_MENU),
		LP_KEYDOWN | LP_ALT_CONTEXT,
	)
	poll_events()

	testing.expect(t, key_down(h, .Left_Alt), "sys-key Alt must be observable as a key")
	testing.expect(t, key_pressed(h, .Left_Alt), "with its press edge")
}

@(test)
test_input_mouse_position :: proc(t: ^testing.T) {
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(hwnd, win32.WM_MOUSEMOVE, 0, pos_lparam(100, 50))
	poll_events()
	testing.expect_value(t, mouse_position(h), [2]i32{100, 50})

	// Signed decode: capture/multi-monitor coordinates are legally negative. An
	// unsigned LOWORD/HIWORD decode turns -10 into 65526.
	win32.PostMessageW(hwnd, win32.WM_MOUSEMOVE, 0, pos_lparam(-10, -5))
	poll_events()
	testing.expect_value(t, mouse_position(h), [2]i32{-10, -5})
}

@(test)
test_input_mouse_button_edges :: proc(t: ^testing.T) {
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(
		hwnd,
		win32.WM_LBUTTONDOWN,
		win32.WPARAM(win32.MK_LBUTTON),
		pos_lparam(10, 10),
	)
	poll_events()
	testing.expect(t, mouse_down(h, .Left), "button down after the pump")
	testing.expect(t, mouse_pressed(h, .Left), "with its press edge")
	testing.expect(t, !mouse_down(h, .Right), "other buttons untouched")

	win32.PostMessageW(hwnd, win32.WM_LBUTTONUP, 0, pos_lparam(10, 10))
	poll_events()
	testing.expect(t, !mouse_down(h, .Left), "button up after release")
	testing.expect(t, mouse_released(h, .Left), "with its release edge")
}

@(test)
test_input_wheel_accumulates_and_resets :: proc(t: ^testing.T) {
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	// One notch plus a half-notch from a free-spinning wheel, same frame: 1.5 detents.
	win32.PostMessageW(hwnd, win32.WM_MOUSEWHEEL, wheel_wparam(120), pos_lparam(0, 0))
	win32.PostMessageW(hwnd, win32.WM_MOUSEWHEEL, wheel_wparam(60), pos_lparam(0, 0))
	poll_events()
	testing.expect_value(t, mouse_wheel(h), f32(1.5))

	poll_events()
	testing.expect_value(t, mouse_wheel(h), f32(0)) // accumulator resets each frame
}

@(test)
test_input_killfocus_clears_silently :: proc(t: ^testing.T) {
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(hwnd, win32.WM_KEYDOWN, VK_A, LP_KEYDOWN)
	win32.PostMessageW(
		hwnd,
		win32.WM_LBUTTONDOWN,
		win32.WPARAM(win32.MK_LBUTTON),
		pos_lparam(5, 5),
	)
	poll_events()
	testing.expect(t, key_down(h, .A), "precondition: key held")
	testing.expect(t, mouse_down(h, .Left), "precondition: button held")

	win32.PostMessageW(hwnd, win32.WM_KILLFOCUS, 0, 0)
	poll_events()

	testing.expect(t, !key_down(h, .A), "focus loss must clear key levels")
	testing.expect(t, !key_released(h, .A), "silently — no release edge")
	testing.expect(t, !mouse_down(h, .Left), "focus loss must clear button levels")
	testing.expect(t, !mouse_released(h, .Left), "silently — no release edge")
}

@(test)
test_input_capture_follows_buttons :: proc(t: ^testing.T) {
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(
		hwnd,
		win32.WM_LBUTTONDOWN,
		win32.WPARAM(win32.MK_LBUTTON),
		pos_lparam(5, 5),
	)
	poll_events()
	testing.expect(t, win32.GetCapture() == hwnd, "first button-down must take capture")

	// Overlap a second button: capture must hold until the LAST button releases.
	win32.PostMessageW(
		hwnd,
		win32.WM_RBUTTONDOWN,
		win32.WPARAM(win32.MK_LBUTTON | win32.MK_RBUTTON),
		pos_lparam(5, 5),
	)
	win32.PostMessageW(hwnd, win32.WM_LBUTTONUP, win32.WPARAM(win32.MK_RBUTTON), pos_lparam(5, 5))
	poll_events()
	testing.expect(t, win32.GetCapture() == hwnd, "capture holds while ANY button is down")

	win32.PostMessageW(hwnd, win32.WM_RBUTTONUP, 0, pos_lparam(5, 5))
	poll_events()
	testing.expect(t, win32.GetCapture() == nil, "last button-up must release capture")
}

@(test)
test_input_has_focus :: proc(t: ^testing.T) {
	// Amendment: focus is observable. A hidden window never receives real focus, so the
	// bookkeeping is driven by posted WM_SETFOCUS/WM_KILLFOCUS like every other test.
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	testing.expect(t, !has_focus(h), "hidden window starts unfocused")

	win32.PostMessageW(hwnd, win32.WM_SETFOCUS, 0, 0)
	poll_events()
	testing.expect(t, has_focus(h), "focus gain must be observable after the pump")

	win32.PostMessageW(hwnd, win32.WM_KILLFOCUS, 0, 0)
	poll_events()
	testing.expect(t, !has_focus(h), "focus loss must be observable after the pump")

	zero: Window_Handle
	testing.expect(t, !has_focus(zero), "invalid handle: false")
}

@(test)
test_input_cursor_persists_after_focus_loss :: proc(t: ^testing.T) {
	// Amendment: the focus-loss clear zeroes levels/counters/wheel but NOT the cursor —
	// last-known position beats a fabricated {0,0}.
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(hwnd, win32.WM_MOUSEMOVE, 0, pos_lparam(100, 50))
	poll_events()
	testing.expect_value(t, mouse_position(h), [2]i32{100, 50})

	win32.PostMessageW(hwnd, win32.WM_KILLFOCUS, 0, 0)
	poll_events()
	testing.expect_value(t, mouse_position(h), [2]i32{100, 50})
}

@(test)
test_input_focus_loss_releases_capture :: proc(t: ^testing.T) {
	// Amendment: WM_KILLFOCUS mid-chord releases capture (design.md §Amendment). Without
	// the release, the OS keeps routing mouse input to a window whose bookkeeping says
	// "no chord" — and since the flag and set are already cleared, no code path ever
	// calls ReleaseCapture again: the capture leaks until something external steals it.
	init()
	defer shutdown()
	h, _ := create_window({hidden = true})
	hwnd := hwnd_of(h)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(
		hwnd,
		win32.WM_LBUTTONDOWN,
		win32.WPARAM(win32.MK_LBUTTON),
		pos_lparam(5, 5),
	)
	poll_events()
	testing.expect(t, win32.GetCapture() == hwnd, "precondition: chord capture taken")

	win32.PostMessageW(hwnd, win32.WM_KILLFOCUS, 0, 0)
	poll_events()

	testing.expect(t, win32.GetCapture() == nil, "focus loss mid-chord must release capture")
	testing.expect(t, !mouse_down(h, .Left), "chord cleared")
	testing.expect(t, !mouse_released(h, .Left), "silently — no release edge")
}

@(test)
test_input_stolen_capture_reconciled :: proc(t: ^testing.T) {
	// Amendment: the OS can reassign capture and notifies the loser via
	// WM_CAPTURECHANGED (sent even on self-release; never re-grab in response). Losing
	// capture ends the chord: button state clears silently, and the stale button-up
	// arriving later must NOT ReleaseCapture — that would strip the new owner.
	init()
	defer shutdown()
	w1, _ := create_window({title = "one", hidden = true})
	w2, _ := create_window({title = "two", hidden = true})
	hwnd1 := hwnd_of(w1)
	hwnd2 := hwnd_of(w2)
	if !testing.expect(t, hwnd1 != nil && hwnd2 != nil, "test plumbing: hwnds must resolve") {
		return
	}

	win32.PostMessageW(
		hwnd1,
		win32.WM_LBUTTONDOWN,
		win32.WPARAM(win32.MK_LBUTTON),
		pos_lparam(5, 5),
	)
	poll_events()
	testing.expect(t, win32.GetCapture() == hwnd1, "precondition: chord capture taken")
	testing.expect(t, mouse_down(w1, .Left), "precondition: button held")

	// The theft: WM_CAPTURECHANGED is SENT to w1's wndproc during this call.
	win32.SetCapture(hwnd2)
	poll_events()

	testing.expect(t, !mouse_down(w1, .Left), "losing capture ends the chord: level cleared")
	testing.expect(t, !mouse_released(w1, .Left), "silently — no release edge")
	testing.expect(t, win32.GetCapture() == hwnd2, "never re-grab in response")

	win32.PostMessageW(hwnd1, win32.WM_LBUTTONUP, 0, pos_lparam(5, 5))
	poll_events()
	testing.expect(t, win32.GetCapture() == hwnd2, "stale chord's up must not strip the new owner")

	win32.ReleaseCapture() // test hygiene: don't leak capture into later tests
}

@(test)
test_input_two_windows_independent :: proc(t: ^testing.T) {
	init()
	defer shutdown()
	w1, _ := create_window({title = "one", hidden = true})
	w2, _ := create_window({title = "two", hidden = true})
	hwnd1 := hwnd_of(w1)
	if !testing.expect(t, hwnd1 != nil, "test plumbing: hwnd must resolve") {
		return
	}

	win32.PostMessageW(hwnd1, win32.WM_KEYDOWN, VK_A, LP_KEYDOWN)
	poll_events()

	testing.expect(t, key_down(w1, .A), "target window sees its key")
	testing.expect(t, !key_down(w2, .A), "other window's state must be untouched")
}

@(test)
test_input_invalid_handles_safe :: proc(t: ^testing.T) {
	init()
	defer shutdown()
	valid, err := create_window({hidden = true})
	testing.expect_value(t, err, Window_Error.None)
	hwnd := hwnd_of(valid)
	if !testing.expect(t, hwnd != nil, "test plumbing: hwnd must resolve") {
		return
	}

	// Positive guard: the input path works for a valid handle (a benign stub fails here).
	win32.PostMessageW(hwnd, win32.WM_KEYDOWN, VK_A, LP_KEYDOWN)
	poll_events()
	testing.expect(t, key_down(valid, .A), "positive guard: valid handle sees the key")

	zero: Window_Handle
	junk := Window_Handle(0xDEAD_BEEF_F00D_CAFE)
	for h in ([2]Window_Handle{zero, junk}) {
		testing.expect(t, !key_down(h, .A), "invalid handle: key_down false")
		testing.expect(t, !key_pressed(h, .A), "invalid handle: key_pressed false")
		testing.expect(t, !key_released(h, .A), "invalid handle: key_released false")
		testing.expect(t, !mouse_down(h, .Left), "invalid handle: mouse_down false")
		testing.expect_value(t, mouse_position(h), [2]i32{0, 0})
		testing.expect_value(t, mouse_wheel(h), f32(0))
	}
}

