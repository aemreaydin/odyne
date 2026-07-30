package platform

// Physical key identity, layout-independent.
Key :: enum u8 {
	Unknown = 0,
	A,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,
	Num_0,
	Num_1,
	Num_2,
	Num_3,
	Num_4,
	Num_5,
	Num_6,
	Num_7,
	Num_8,
	Num_9,
	Space,
	Enter,
	Escape,
	Tab,
	Backspace,
	Left,
	Right,
	Up,
	Down,
	Left_Shift,
	Right_Shift,
	Left_Ctrl,
	Right_Ctrl,
	Left_Alt,
	Right_Alt,
	Left_Command,
	Right_Command,
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,
}

Mouse_Button :: enum u8 {
	Left,
	Right,
	Middle,
	X1,
	X2,
}

// One window's input for the current frame. Edges are retired by the event pump, so they
// read true for exactly one frame.
Input_State :: struct {
	keys:         [Key]Button_State,
	buttons:      [Mouse_Button]Button_State,
	buttons_down: bit_set[Mouse_Button],
	cursor:       [2]i32,
	wheel:        f32, // accumulated this frame; reset by the pump
}

/*
A button across one frame. Counting transitions rather than sampling state is what makes a
press-and-release within a single frame observable instead of lost.
*/
Button_State :: struct {
	half_transitions: u8, // saturates rather than wrapping
	ended_down:       bool, // state at the end of the frame
}

// Whether `k` is held at the end of the frame — level state, safe to read from a simulation
// step. An invalid handle reports false.
key_down :: proc(h: Window_Handle, k: Key) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return window_state.input.keys[k].ended_down
}

// Whether `k` went down this frame. An edge: true for exactly one frame, so it must be read
// once per frame and latched, never from a simulation step that may run zero or many times.
key_pressed :: proc(h: Window_Handle, k: Key) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return was_pressed(window_state.input.keys[k])
}

// Whether `k` went up this frame. An edge; see `key_pressed`.
key_released :: proc(h: Window_Handle, k: Key) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return was_released(window_state.input.keys[k])
}

// Whether `b` is held at the end of the frame — level state. An invalid handle reports false.
mouse_down :: proc(h: Window_Handle, b: Mouse_Button) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return window_state.input.buttons[b].ended_down
}

// Whether `button` went down this frame. An edge; see `key_pressed`.
mouse_pressed :: proc(h: Window_Handle, button: Mouse_Button) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return was_pressed(window_state.input.buttons[button])
}

// Whether `button` went up this frame. An edge; see `key_pressed`.
mouse_released :: proc(h: Window_Handle, button: Mouse_Button) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return was_released(window_state.input.buttons[button])
}

// Cursor position in client-area pixels. An invalid handle reports `{0, 0}`.
mouse_position :: proc(h: Window_Handle) -> [2]i32 {
	window_state, ok := get_state(h)
	if !ok {
		return {0, 0}
	}
	return window_state.input.cursor
}

// Wheel movement accumulated this frame, reset by the pump. An invalid handle reports 0.
mouse_wheel :: proc(h: Window_Handle) -> f32 {
	window_state, ok := get_state(h)
	if !ok {
		return 0
	}
	return window_state.input.wheel
}

// Two transitions means the button both went down and came back up within the frame, which
// still counts as a press.
@(private)
was_pressed :: proc(b: Button_State) -> bool {
	return b.half_transitions >= 2 || (b.half_transitions == 1 && b.ended_down)
}

@(private)
was_released :: proc(b: Button_State) -> bool {
	return b.half_transitions >= 2 || (b.half_transitions == 1 && !b.ended_down)
}

@(private)
record_key :: proc(input: ^Input_State, k: Key, is_down: bool) {
	state := &input.keys[k]
	if state.ended_down != is_down {
		state.ended_down = is_down
		if state.half_transitions < max(u8) {
			state.half_transitions += 1
		}
	}
}

@(private)
record_mouse_button :: proc(input: ^Input_State, b: Mouse_Button, is_down: bool) {
	state := &input.buttons[b]
	if state.ended_down != is_down {
		state.ended_down = is_down
		if state.half_transitions < max(u8) {
			state.half_transitions += 1
		}
	}
}

@(private)
record_cursor :: proc(input: ^Input_State, pos: [2]i32) {
	input.cursor = pos
}

@(private)
record_wheel :: proc(input: ^Input_State, delta: f32) {
	input.wheel += delta
}

// Clears the per-frame edges and wheel while leaving held state intact. Called once per
// pump, which is what bounds an edge to a single frame.
@(private)
retire_input :: proc(input: ^Input_State) {
	for &button in input.buttons {
		button.half_transitions = 0
	}
	for &key in input.keys {
		key.half_transitions = 0
	}
	input.wheel = 0
}

// Drops all input including held state — used on focus loss, so keys held when the window
// lost focus do not read as still held when it returns.
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
}
