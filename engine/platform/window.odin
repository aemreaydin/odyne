package platform

import "engine:core/containers/handle_pool"

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

Window_Desc :: struct {
	title:  string, // "" ⇒ "odyne"
	width:  i32, // 0 ⇒ 1280 (client area)
	height: i32, // 0 ⇒ 720
	hidden: bool, // ZII false ⇒ visible
}

Window_Error :: enum {
	None,
	Init_Failed, // window-class registration failed
	Create_Failed, // native window creation failed
	Destroy_Failed,
	Invalid_Handle, // zero, stale, or foreign handle
}

@(private)
Window_State :: struct {
	handle:          Window_Handle,
	size:            [2]i32,
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
		hidden = desc.hidden, // no default to apply — ZII false is already "visible"
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

// set_should_close sets or clears the close-requested flag, observable via should_close.
// Invalid handle → .Invalid_Handle.
set_should_close :: proc(h: Window_Handle, should_close: bool = true) -> Window_Error {
	window_state, ok := get_state(h)
	if !ok {
		return .Invalid_Handle
	}
	window_state.close_requested = should_close
	return .None
}

// is_open reports whether `h` names a live window. Garbage-safe.
is_open :: proc(h: Window_Handle) -> bool {
	return handle_pool.has(&g_window_pool, h)
}

// should_close reports whether close has been requested since create. The window stays open
// until destroy_window. Invalid handle → false.
should_close :: proc(h: Window_Handle) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return window_state.close_requested
}

// has_focus reports whether `h` held keyboard focus as of the last poll_events.
// Invalid handle → false.
has_focus :: proc(h: Window_Handle) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return window_state.focused
}

// client_size returns the window's current client area, or {0,0} on an invalid handle.
client_size :: proc(h: Window_Handle) -> [2]i32 {
	window_state, ok := get_state(h)
	if !ok {
		return {0, 0}
	}
	return window_state.size
}
