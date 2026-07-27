package platform

import sdl "vendor:sdl3"

// SDL3 input mechanism: translate one SDL event into the portable Input_State recorders.
//
// KEYS ARE POSITIONAL
//
// The table below keys off `SDL_Scancode`, never `SDL_Keycode`. A scancode names the
// PHYSICAL key — USB HID usage page 0x07 — so `Key.W` is the key above `Key.S` on QWERTY,
// AZERTY and Dvorak alike, and WASD keeps its shape. A keycode is the character the
// current layout produces from that key, which is the right currency for text entry and
// the wrong one for movement. This is the same contract the Win32 backend reached through
// scan codes and the Cocoa backend through `kVK` hardware codes.
//
// UNMAPPED KEYS ARE DROPPED
//
// SDL has ~240 scancodes; `Key` has 69. Anything absent maps to `.Unknown` and is
// discarded before it can record a transition, so a media key or an IME key cannot
// disturb frame state.

// handle_input_event routes one input event to its window's state. Events whose window
// is gone — the queue can outlive a destroy by a frame — are dropped silently.
@(private)
handle_input_event :: proc(ev: sdl.Event) {
	#partial switch ev.type {
	case .KEY_DOWN, .KEY_UP:
		// Autorepeat is a synthetic re-press of a key that never came up. Recording it
		// would manufacture a press edge every repeat interval, so it is dropped: the key
		// simply keeps reporting down.
		if ev.key.repeat {
			return
		}
		k := key_from_scancode(ev.key.scancode)
		if k == .Unknown {
			return
		}
		if ws, ok := state_from_window_id(ev.key.windowID); ok {
			record_key(&ws.input, k, ev.key.down)
		}

	case .MOUSE_MOTION:
		// Client-relative and signed: a drag above or left of the window must read
		// negative, not wrap into a large positive.
		if ws, ok := state_from_window_id(ev.motion.windowID); ok {
			record_cursor(&ws.input, {i32(ev.motion.x), i32(ev.motion.y)})
		}

	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		b, ok_button := button_from_sdl(ev.button.button)
		if !ok_button {
			return
		}
		if ws, ok := state_from_window_id(ev.button.windowID); ok {
			record_mouse_button(&ws.input, b, ev.button.down)
			if ev.button.down {
				ws.input.buttons_down += {b}
			} else {
				ws.input.buttons_down -= {b}
			}
		}

	case .MOUSE_WHEEL:
		// SDL already reports y in detents as a float, positive away from the user —
		// the platform contract verbatim, so there is no scaling to do here.
		if ws, ok := state_from_window_id(ev.wheel.windowID); ok {
			record_wheel(&ws.input, ev.wheel.y)
		}
	}
}

@(private)
button_from_sdl :: proc "contextless" (button: u8) -> (Mouse_Button, bool) {
	switch button {
	case sdl.BUTTON_LEFT:
		return .Left, true
	case sdl.BUTTON_RIGHT:
		return .Right, true
	case sdl.BUTTON_MIDDLE:
		return .Middle, true
	case sdl.BUTTON_X1:
		return .X1, true
	case sdl.BUTTON_X2:
		return .X2, true
	}
	return {}, false
}

// key_from_scancode maps a physical SDL scancode to the platform key set.
// Anything outside the set → .Unknown, which callers drop.
@(private)
key_from_scancode :: proc "contextless" (sc: sdl.Scancode) -> Key {
	#partial switch sc {
	case .A:
		return .A
	case .B:
		return .B
	case .C:
		return .C
	case .D:
		return .D
	case .E:
		return .E
	case .F:
		return .F
	case .G:
		return .G
	case .H:
		return .H
	case .I:
		return .I
	case .J:
		return .J
	case .K:
		return .K
	case .L:
		return .L
	case .M:
		return .M
	case .N:
		return .N
	case .O:
		return .O
	case .P:
		return .P
	case .Q:
		return .Q
	case .R:
		return .R
	case .S:
		return .S
	case .T:
		return .T
	case .U:
		return .U
	case .V:
		return .V
	case .W:
		return .W
	case .X:
		return .X
	case .Y:
		return .Y
	case .Z:
		return .Z

	case ._0:
		return .Num_0
	case ._1:
		return .Num_1
	case ._2:
		return .Num_2
	case ._3:
		return .Num_3
	case ._4:
		return .Num_4
	case ._5:
		return .Num_5
	case ._6:
		return .Num_6
	case ._7:
		return .Num_7
	case ._8:
		return .Num_8
	case ._9:
		return .Num_9

	case .SPACE:
		return .Space
	case .RETURN:
		return .Enter
	case .ESCAPE:
		return .Escape
	case .TAB:
		return .Tab
	case .BACKSPACE:
		return .Backspace

	case .LEFT:
		return .Left
	case .RIGHT:
		return .Right
	case .UP:
		return .Up
	case .DOWN:
		return .Down

	// Left and right modifiers are distinct keys, not one key plus a side flag — the
	// platform-input contract requires each variant to be independently observable.
	case .LSHIFT:
		return .Left_Shift
	case .RSHIFT:
		return .Right_Shift
	case .LCTRL:
		return .Left_Ctrl
	case .RCTRL:
		return .Right_Ctrl
	case .LALT:
		return .Left_Alt
	case .RALT:
		return .Right_Alt
	// GUI is Command on macOS, Windows key elsewhere. Same physical key, same identity.
	case .LGUI:
		return .Left_Command
	case .RGUI:
		return .Right_Command

	case .F1:
		return .F1
	case .F2:
		return .F2
	case .F3:
		return .F3
	case .F4:
		return .F4
	case .F5:
		return .F5
	case .F6:
		return .F6
	case .F7:
		return .F7
	case .F8:
		return .F8
	case .F9:
		return .F9
	case .F10:
		return .F10
	case .F11:
		return .F11
	case .F12:
		return .F12
	}
	return .Unknown
}
