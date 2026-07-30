package platform

import sdl "vendor:sdl3"

// Routes one input event to its window's state. Events for a destroyed window are dropped
// silently, because the queue can outlive a destroy by a frame.
@(private)
handle_input_event :: proc(ev: sdl.Event) {
	#partial switch ev.type {
	case .KEY_DOWN, .KEY_UP:
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

/*
Maps a physical SDL scancode to the platform key set. Scancodes name the physical key, so
`Key.W` is the key above `Key.S` on QWERTY, AZERTY and Dvorak alike — a keycode would give
the character the layout produces, which is right for text entry and wrong for movement.

SDL has far more scancodes than `Key` covers; anything unmapped returns `.Unknown`, which
callers drop before it can record a transition.
*/
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
