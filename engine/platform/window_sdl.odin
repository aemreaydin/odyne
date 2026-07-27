package platform

import "core:c"
import "core:strings"
import sdl "vendor:sdl3"
import "engine:core/containers/handle_pool"

// The SDL3 window backend. One backend, every OS — there are no `#+build` files in this
// package any more.
//
// WHAT SDL IS AND IS NOT HERE
//
// SDL supplies MECHANISM only: a native window, and an event queue carrying that window's
// OS messages. Every piece of POLICY the engine cares about still lives in `window.odin`
// and `input.odin` — the handle pool, the half-transition edge algebra, the retire
// boundary, the frame-coherence rule, the invalid-handle grammar. That split is the whole
// point of the seam: this file was written against tests that never changed.
//
// ROUTING WITHOUT A USER-DATA POINTER
//
// SDL tags every window event with an `SDL_WindowID`, so the backend needs no per-window
// user-data slot (Win32's `GWLP_USERDATA`, Cocoa's delegate). Resolution is a linear scan
// over the pool's live contents keyed on that id — which is what makes it survive the
// swap-with-last relocation `handle_pool.remove` performs. MAX_WINDOWS is 4; a scan is
// cheaper than any index would be.
//
// THREADING
//
// SDL video is main-thread-only on macOS, exactly as AppKit is underneath it. `init`,
// `create_window`, `destroy_window` and `poll_events` must all be called from the thread
// that owns the event loop. `tests/platform` is a `main()` for this reason.

@(private)
_Native_Window :: struct {
	win: ^sdl.Window,
	id:  sdl.WindowID,
}

// g_initialized guards double-init. SDL_Init is reference-counted and would happily
// succeed a second time, but the platform contract says a second init without an
// intervening shutdown is an error that leaves the live window system undisturbed.
@(private)
g_initialized: bool

// init starts SDL's video subsystem and prepares the window pool from `allocator`.
// A second init without a shutdown → .Init_Failed, before any allocation happens.
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

// shutdown destroys any remaining windows, frees the pool, and stops SDL. Every
// outstanding Window_Handle is dead afterwards.
shutdown :: proc() {
	if !g_initialized {
		return
	}

	destroy_window_pool(&g_window_pool)
	sdl.Quit()
	g_initialized = false
}

// create_window creates a native window per `desc` (ZII ⇒ visible 1280×720 "odyne").
// The returned handle is the only name upper layers ever have for the window.
//
// The pool insert happens FIRST so that a full pool costs nothing native, and so the
// window never exists without a handle naming it. A native failure unwinds the insert.
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

	// SDL copies the title, so the temporary cstring does not have to outlive the call.
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

	// Adopt whatever SDL actually gave us rather than what was asked for; a window manager
	// is entitled to clamp, and `client_size` must report what exists.
	w, hgt: c.int
	if sdl.GetWindowSize(win, &w, &hgt) {
		ws.size = {i32(w), i32(hgt)}
	}

	return h, .None
}

// destroy_window closes the native window and stales the handle. This is the ONLY path
// that destroys a window — a user's close click merely sets should_close.
destroy_window :: proc(h: Window_Handle) -> Window_Error {
	window_state, ok := get_state(h)
	if !ok {
		return .Invalid_Handle
	}

	sdl.DestroyWindow(window_state.win)
	handle_pool.remove(&g_window_pool, h)
	return .None
}

// poll_events drains SDL's event queue without blocking — call once per frame. Every
// query answers from state fixed here, so the whole frame sees one coherent world.
//
// Retiring first is what makes an edge last exactly one frame: last frame's transition
// counts are cleared, then this frame's messages deposit new ones.
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
			// Focus loss clears levels, pending transitions and wheel WITHOUT edges, so a
			// key held across an Alt-Tab does not read as released on return. The cursor
			// position deliberately survives. SDL releases its implicit drag capture itself.
			if ws, ok := state_from_window_id(ev.window.windowID); ok {
				clear_input_states(ws)
				ws.focused = false
			}

		case .KEY_DOWN, .KEY_UP, .MOUSE_MOTION, .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP, .MOUSE_WHEEL:
			handle_input_event(ev)
		}
	}
}

// set_window_title renames the native window. Invalid handle → .Invalid_Handle; the
// native call itself is best-effort (a cosmetic OS rejection is not reported).
set_window_title :: proc(h: Window_Handle, title: string) -> Window_Error {
	window_state, ok := get_state(h)
	if !ok {
		return .Invalid_Handle
	}

	ctitle := strings.clone_to_cstring(title, context.temp_allocator)
	sdl.SetWindowTitle(window_state.win, ctitle)
	return .None
}

// framebuffer_size returns the client area in PHYSICAL PIXELS — the value a swapchain is
// sized from, and on a Retina display twice `client_size` on each axis. Invalid handle →
// {0,0}.
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

// state_from_window_id resolves an SDL window id to its pool entry by scanning the live
// dense array. A scan rather than a cached index because `handle_pool.remove` relocates
// entries (swap-with-last), so no index survives a destroy — only identity does.
@(private)
state_from_window_id :: proc(id: sdl.WindowID) -> (^Window_State, bool) {
	for &window_state in handle_pool.slice(&g_window_pool) {
		if window_state.id == id {
			return &window_state, true
		}
	}
	return nil, false
}
