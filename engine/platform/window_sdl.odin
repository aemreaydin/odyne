package platform

import "core:c"
import "core:strings"
import "engine:core/containers/handle_pool"
import sdl "vendor:sdl3"

@(private)
_Native_Window :: struct {
	win: ^sdl.Window,
	id:  sdl.WindowID,
}

@(private)
g_initialized: bool

// Starts the platform backend. Must be called before any window exists, and paired with
// `shutdown`. Calling it twice reports `.Init_Failed` rather than reinitializing.
init :: proc(allocator := context.allocator) -> Window_Error {
	if g_initialized {
		return .Init_Failed
	}
	if !sdl.Init({.VIDEO}) {
		return .Init_Failed
	}

	handle_pool.init(&g_window_pool, MAX_WINDOWS, allocator)
	g_initialized = true
	return .None
}

// Destroys every remaining window and shuts the backend down. Safe to call when
// uninitialized. Every outstanding window handle is dead afterwards.
shutdown :: proc() {
	if !g_initialized {
		return
	}

	destroy_window_pool(&g_window_pool)
	sdl.Quit()
	g_initialized = false
}

// Creates a window from `desc`, filling zero fields with defaults. Fails with
// `.Create_Failed` once MAX_WINDOWS are live.
create_window :: proc(desc: Window_Desc) -> (h: Window_Handle, err: Window_Error) {
	window_desc := get_desc_or_default(desc)
	window_state := Window_State {
		size = {window_desc.width, window_desc.height},
	}

	handle, pool_err := handle_pool.add(&g_window_pool, window_state)
	if pool_err != .None {
		return {}, .Create_Failed
	}
	h = handle

	flags := sdl.WindowFlags{.RESIZABLE, .HIGH_PIXEL_DENSITY}
	if window_desc.hidden {
		flags += {.HIDDEN}
	}

	title := strings.clone_to_cstring(window_desc.title, context.temp_allocator)
	win := sdl.CreateWindow(title, c.int(window_desc.width), c.int(window_desc.height), flags)
	if win == nil {
		handle_pool.remove(&g_window_pool, h)
		return {}, .Create_Failed
	}

	ws, ok := get_state(h)
	assert(ok, "window state lookup shouldn't fail immediately after add")
	ws.win = win
	ws.id = sdl.GetWindowID(win)

	w, hgt: c.int
	if sdl.GetWindowSize(win, &w, &hgt) {
		ws.size = {i32(w), i32(hgt)}
	}

	return h, .None
}

// Destroys the window and retires `h`. Queued events for it are dropped by the next pump.
destroy_window :: proc(h: Window_Handle) -> Window_Error {
	window_state, ok := get_state(h)
	if !ok {
		return .Invalid_Handle
	}

	sdl.DestroyWindow(window_state.win)
	handle_pool.remove(&g_window_pool, h)
	return .None
}

// Drains the OS event queue into per-window state and retires the previous frame's input
// edges. Call exactly once per frame, before reading any input.
poll_events :: proc() {
	for &window_state in handle_pool.slice(&g_window_pool) {
		retire_input(&window_state.input)
	}

	ev: sdl.Event
	for sdl.PollEvent(&ev) {
		#partial switch ev.type {
		case .WINDOW_CLOSE_REQUESTED:
			if ws, ok := state_from_window_id(ev.window.windowID); ok {
				ws.close_requested = true
			}

		case .WINDOW_RESIZED:
			if ws, ok := state_from_window_id(ev.window.windowID); ok {
				ws.size = {ev.window.data1, ev.window.data2}
			}

		case .WINDOW_FOCUS_GAINED:
			if ws, ok := state_from_window_id(ev.window.windowID); ok {
				ws.focused = true
			}

		case .WINDOW_FOCUS_LOST:
			if ws, ok := state_from_window_id(ev.window.windowID); ok {
				clear_input_states(ws)
				ws.focused = false
			}

		case .KEY_DOWN, .KEY_UP, .MOUSE_MOTION, .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP, .MOUSE_WHEEL:
			handle_input_event(ev)
		}
	}
}

// Sets the window title.
set_window_title :: proc(h: Window_Handle, title: string) -> Window_Error {
	window_state, ok := get_state(h)
	if !ok {
		return .Invalid_Handle
	}

	ctitle := strings.clone_to_cstring(title, context.temp_allocator)
	sdl.SetWindowTitle(window_state.win, ctitle)
	return .None
}

// The drawable size in pixels, which differs from `client_size` on high-DPI displays. This
// is the size a swapchain must match. An invalid handle reports `{0, 0}`.
framebuffer_size :: proc(h: Window_Handle) -> [2]i32 {
	window_state, ok := get_state(h)
	if !ok {
		return {0, 0}
	}

	w, hgt: c.int
	if !sdl.GetWindowSizeInPixels(window_state.win, &w, &hgt) {
		return window_state.size
	}
	return {i32(w), i32(hgt)}
}

@(private)
state_from_window_id :: proc(id: sdl.WindowID) -> (^Window_State, bool) {
	for &window_state in handle_pool.slice(&g_window_pool) {
		if window_state.id == id {
			return &window_state, true
		}
	}
	return nil, false
}
