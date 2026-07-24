package platform

import win32 "core:sys/windows"

@(private = "file")
vk_to_key: [256]Key

// lparam bit 31 — the key message's transition state: SET on key-up, clear on key-down.
@(private = "file")
KEY_UP_BIT :: 1 << 31

@(private = "file")
WHEEL_DELTA :: 120

// handle_input_message records one input message into window_state.input per the agreed
// contract (level flip + half-transition count; cursor; wheel; silent clear on focus
// loss). Returns true if the message was an input message this system recorded.
@(private)
handle_input_message :: proc(
	window_state: ^Window_State,
	hwnd: win32.HWND,
	msg: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> bool {
	input := &window_state.input

	switch msg {
	case win32.WM_KEYDOWN, win32.WM_KEYUP, win32.WM_SYSKEYDOWN, win32.WM_SYSKEYUP:
		key := key_from_vk_extended(wparam, lparam)
		if key == .Unknown {
			break
		}
		is_down := (lparam & KEY_UP_BIT) == 0
		process_state(&input.keys[key], is_down)
	case win32.WM_MBUTTONDOWN, win32.WM_RBUTTONDOWN, win32.WM_LBUTTONDOWN, win32.WM_XBUTTONDOWN:
		process_mouse_state(window_state, hwnd, msg, wparam, true)
	case win32.WM_MBUTTONUP, win32.WM_RBUTTONUP, win32.WM_LBUTTONUP, win32.WM_XBUTTONUP:
		process_mouse_state(window_state, hwnd, msg, wparam, false)
	case win32.WM_MOUSEMOVE:
		x_coord := win32.GET_X_LPARAM(lparam)
		y_coord := win32.GET_Y_LPARAM(lparam)
		input.cursor = {i32(x_coord), i32(y_coord)}
	case win32.WM_MOUSEWHEEL:
		wheel_raw := win32.GET_WHEEL_DELTA_WPARAM(wparam)
		input.wheel += f32(wheel_raw) / WHEEL_DELTA
	case:
		return false
	}

	return true
}

// key_down reports the key's level as of the last poll_events. Invalid handle → false.
key_down :: proc(h: Window_Handle, k: Key) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return window_state.input.keys[k].ended_down
}

// key_pressed reports whether ≥1 up→down transition occurred during the last drain
// (autorepeat produces none). Invalid handle → false.
key_pressed :: proc(h: Window_Handle, k: Key) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return was_pressed(window_state.input.keys[k])
}

// key_released reports whether ≥1 down→up transition occurred during the last drain.
// Invalid handle → false.
key_released :: proc(h: Window_Handle, k: Key) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return was_released(window_state.input.keys[k])
}

// mouse_down reports the button's level as of the last poll_events. Invalid handle → false.
mouse_down :: proc(h: Window_Handle, b: Mouse_Button) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return window_state.input.buttons[b].ended_down
}

// mouse_pressed reports whether ≥1 up→down transition occurred during the last drain.
// Invalid handle → false.
mouse_pressed :: proc(h: Window_Handle, button: Mouse_Button) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return was_pressed(window_state.input.buttons[button])
}

// mouse_released reports whether ≥1 down→up transition occurred during the last drain.
// Invalid handle → false.
mouse_released :: proc(h: Window_Handle, button: Mouse_Button) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return was_released(window_state.input.buttons[button])
}

// mouse_position returns the cursor position in signed client pixels as of the last
// poll_events. Invalid handle → {0, 0}.
mouse_position :: proc(h: Window_Handle) -> [2]i32 {
	window_state, ok := get_state(h)
	if !ok {
		return {0, 0}
	}
	return window_state.input.cursor
}

// mouse_wheel returns the wheel motion accumulated during the last drain, in detents
// (+ away from user), reset each poll. Invalid handle → 0.
mouse_wheel :: proc(h: Window_Handle) -> f32 {
	window_state, ok := get_state(h)
	if !ok {
		return 0
	}
	return window_state.input.wheel
}

@(private)
begin_input_frame :: proc(window_state: ^Window_State) {
	for &button in window_state.input.buttons {
		button.half_transitions = 0
	}
	for &key in window_state.input.keys {
		key.half_transitions = 0
	}
	window_state.input.wheel = 0
}

@(private)
clear_input_states :: proc(window_state: ^Window_State) {
	clear_buttons(window_state)
	clear_keys(window_state)
	window_state.input.wheel = 0
}

@(private)
clear_keys :: proc(window_state: ^Window_State) {
	for &key in window_state.input.keys {
		key.ended_down = false
		key.half_transitions = 0
	}
}

@(private)
clear_buttons :: proc(window_state: ^Window_State) {
	for &button in window_state.input.buttons {
		button.ended_down = false
		button.half_transitions = 0
	}
	window_state.input.buttons_down = {}
	window_state.holds_capture = false
}

@(private)
update_capture :: proc(window_state: ^Window_State, hwnd: win32.HWND) {
	if !window_state.holds_capture && card(window_state.input.buttons_down) > 0 {
		window_state.holds_capture = true
		win32.SetCapture(hwnd)
	} else if window_state.holds_capture && card(window_state.input.buttons_down) == 0 {
		window_state.holds_capture = false
		win32.ReleaseCapture()
	}
}

@(private)
init_vk_table :: proc() {
	for c in 0 ..< 26 {
		vk_to_key[u32('A') + u32(c)] = Key(u8(Key.A) + u8(c))
	}

	for d in 0 ..< 10 {
		vk_to_key[u32('0') + u32(d)] = Key(u8(Key.Num_0) + u8(d))
	}

	for f in 0 ..< 12 {
		vk_to_key[u32(win32.VK_F1) + u32(f)] = Key(u8(Key.F1) + u8(f))
	}

	vk_to_key[win32.VK_SPACE] = .Space
	vk_to_key[win32.VK_RETURN] = .Enter
	vk_to_key[win32.VK_ESCAPE] = .Escape
	vk_to_key[win32.VK_TAB] = .Tab
	vk_to_key[win32.VK_BACK] = .Backspace

	vk_to_key[win32.VK_LEFT] = .Left
	vk_to_key[win32.VK_RIGHT] = .Right
	vk_to_key[win32.VK_UP] = .Up
	vk_to_key[win32.VK_DOWN] = .Down

	vk_to_key[win32.VK_LSHIFT] = .Left_Shift
	vk_to_key[win32.VK_RSHIFT] = .Right_Shift
	vk_to_key[win32.VK_LCONTROL] = .Left_Ctrl
	vk_to_key[win32.VK_RCONTROL] = .Right_Ctrl
	vk_to_key[win32.VK_LMENU] = .Left_Alt
	vk_to_key[win32.VK_RMENU] = .Right_Alt
}

@(private = "file")
process_state :: proc(b: ^Button_State, is_down: bool) {
	if b.ended_down != is_down {
		b.ended_down = is_down
		if b.half_transitions < max(u8) {
			b.half_transitions += 1
		}
	}
}

@(private = "file")
process_mouse_state :: proc(
	window_state: ^Window_State,
	hwnd: win32.HWND,
	msg: win32.UINT,
	wparam: win32.WPARAM,
	is_down: bool,
) {
	button, ok := button_from_msg(msg, wparam)
	if !ok {
		return
	}

	if is_down {
		window_state.input.buttons_down += {button}
	} else {
		window_state.input.buttons_down -= {button}
	}
	process_state(&window_state.input.buttons[button], is_down)
	update_capture(window_state, hwnd)
}

@(private = "file")
key_from_vk :: proc "contextless" (vk: win32.WPARAM) -> Key {
	if vk >= len(vk_to_key) do return .Unknown
	return vk_to_key[vk]
}

@(private = "file")
key_from_vk_extended :: proc "contextless" (vk: win32.WPARAM, lparam: win32.LPARAM) -> Key {
	scancode := u32((lparam >> 16) & 0xFF)
	extended := (lparam & (1 << 24)) != 0

	switch vk {
	case win32.VK_SHIFT:
		mapped := win32.MapVirtualKeyW(scancode, win32.MAPVK_VSC_TO_VK_EX)
		return mapped == u32(win32.VK_RSHIFT) ? .Right_Shift : .Left_Shift
	case win32.VK_CONTROL:
		return extended ? .Right_Ctrl : .Left_Ctrl
	case win32.VK_MENU:
		return extended ? .Right_Alt : .Left_Alt
	}
	return key_from_vk(vk)
}

@(private = "file")
button_from_msg :: proc "contextless" (
	msg: win32.UINT,
	wparam: win32.WPARAM,
) -> (
	Mouse_Button,
	bool,
) {
	switch msg {
	case win32.WM_MBUTTONDOWN, win32.WM_MBUTTONUP:
		return .Middle, true
	case win32.WM_RBUTTONDOWN, win32.WM_RBUTTONUP:
		return .Right, true
	case win32.WM_LBUTTONDOWN, win32.WM_LBUTTONUP:
		return .Left, true
	case win32.WM_XBUTTONDOWN, win32.WM_XBUTTONUP:
		xbutton := win32.HIWORD(wparam)
		return xbutton == 1 ? .X1 : .X2, true
	}
	return {}, false
}

