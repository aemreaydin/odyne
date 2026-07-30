package platform

import "engine:core/containers/handle_pool"

// Reference to a live window; the zero value never resolves.
Window_Handle :: distinct u64

@(private)
WND_CLASS_NAME :: "OdyneMainClass"

@(private)
MAX_WINDOWS :: 4

@(private)
DEFAULT_TITLE :: "odyne"

@(private)
DEFAULT_WIDTH :: 1280

@(private)
DEFAULT_HEIGHT :: 720

// Requested window properties. The zero value is a working configuration.
Window_Desc :: struct {
	title:  string, // "" ⇒ "odyne"
	width:  i32, // ≤0 ⇒ 1280
	height: i32, // ≤0 ⇒ 720
	hidden: bool, // create the window without showing it
}

Window_Error :: enum {
	None,
	Init_Failed, // the platform backend failed to start
	Create_Failed, // the backend refused to create the window
	Invalid_Handle, // zero, stale, or foreign handle
}

@(private)
Window_State :: struct {
	handle:          Window_Handle,
	size:            [2]i32, // client area, tracked across resizes
	close_requested: bool,
	input:           Input_State,
	focused:         bool,
	using impl:      _Native_Window,
}

@(private)
g_window_pool: handle_pool.Handle_Pool(Window_State, Window_Handle)

@(private)
get_desc_or_default :: proc(desc: Window_Desc) -> Window_Desc {
	return {
		title = len(desc.title) == 0 ? DEFAULT_TITLE : desc.title,
		width = desc.width <= 0 ? DEFAULT_WIDTH : desc.width,
		height = desc.height <= 0 ? DEFAULT_HEIGHT : desc.height,
		hidden = desc.hidden,
	}
}

@(private)
destroy_window_pool :: proc(window_pool: ^handle_pool.Handle_Pool(Window_State, Window_Handle)) {
	for !handle_pool.is_empty(window_pool) {
		h := handle_pool.slice(window_pool)[0].handle
		destroy_window(h)
	}
	handle_pool.destroy(window_pool)
}

@(private)
get_state :: proc(h: Window_Handle) -> (^Window_State, bool) {
	window_state, err := handle_pool.get_ptr(&g_window_pool, h)
	return window_state, err == .None
}

// Raises or clears the window's close request, which `should_close` reports. The window is
// not destroyed; the loop owning it decides what to do.
set_should_close :: proc(h: Window_Handle, should_close: bool = true) -> Window_Error {
	window_state, ok := get_state(h)
	if !ok {
		return .Invalid_Handle
	}
	window_state.close_requested = should_close
	return .None
}

// Whether `h` still refers to a live window. False for a destroyed or foreign handle.
is_open :: proc(h: Window_Handle) -> bool {
	return handle_pool.has(&g_window_pool, h)
}

// Whether the window has been asked to close, by the user or by `set_should_close`. An
// invalid handle reports false.
should_close :: proc(h: Window_Handle) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return window_state.close_requested
}

// Whether the window currently holds keyboard focus. An invalid handle reports false.
has_focus :: proc(h: Window_Handle) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return window_state.focused
}

// The window's current client area in pixels, tracking resizes. This is the truth after
// creation, not `Window_Desc`. An invalid handle reports `{0, 0}`.
client_size :: proc(h: Window_Handle) -> [2]i32 {
	window_state, ok := get_state(h)
	if !ok {
		return {0, 0}
	}
	return window_state.size
}
