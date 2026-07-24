package platform

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

// Button_State — one digital input's frame record (mechanism C, half-transition counts):
// the level at the end of the last drain plus how many times it flipped during that
// drain. A sub-frame tap leaves {half_transitions = 2, ended_down = false} — the tap
// survives the drain even though the level round-tripped.
Button_State :: struct {
	half_transitions: u8, // level flips during the last drain (saturate, don't wrap)
	ended_down:       bool,
}

// was_pressed reports whether `b` recorded ≥1 up→down transition during the last drain:
// two or more flips always contain one; a single flip counts only if it landed down.
@(private)
was_pressed :: proc(b: Button_State) -> bool {
	return b.half_transitions >= 2 || (b.half_transitions == 1 && b.ended_down)
}

// was_released reports whether `b` recorded ≥1 down→up transition during the last drain:
// two or more flips always contain one; a single flip counts only if it landed up.
@(private)
was_released :: proc(b: Button_State) -> bool {
	return b.half_transitions >= 2 || (b.half_transitions == 1 && !b.ended_down)
}

// Input_State — one window's input snapshot, embedded in Window_State. Counters and
// wheel reset when poll_events retires the frame; levels and cursor persist.
Input_State :: struct {
	keys:         [Key]Button_State,
	buttons:      [Mouse_Button]Button_State,
	buttons_down: bit_set[Mouse_Button],
	cursor:       [2]i32, // client px, signed (negatives legal under capture)
	wheel:        f32, // detents this frame (raw/120), + away from user
}

