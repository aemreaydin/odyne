package platform

import "base:runtime"
import win32 "core:sys/windows"
import "engine:core/containers/handle_pool"

@(private)
CLASS_NAME :: "OdyneMainClass"

@(private)
WIN_POOL_CAP :: 4

// Window_State — the pool item behind each Window_Handle. GWLP_USERDATA holds the
// HANDLE (a LONG_PTR-sized integer), never a pointer into the pool: any remove may
// relocate any item (swap-with-last), and only a handle survives relocation.
@(private)
Window_State :: struct {
	handle:          Window_Handle,
	hwnd:            win32.HWND,
	size:            [2]i32, // client area
	close_requested: bool,
	input:           Input_State, // m10-02: per-window input snapshot
	focused:         bool, // m10-02 amendment: keyboard focus as of the last poll
	holds_capture:   bool,
}

@(private)
g_window_pool: handle_pool.Handle_Pool(Window_State, Window_Handle)

// init prepares the window system: the pool is initialized from `allocator`.
// Single-threaded by contract — call from the thread that will pump messages.
init :: proc(allocator := context.allocator) {
	handle_pool.init(&g_window_pool, WIN_POOL_CAP, allocator)

	hinstance := win32.HINSTANCE(win32.GetModuleHandleW(nil))
	assert(hinstance != nil, "instance shouldn't be nil")

	atom := register_class(hinstance)
	assert(atom != 0, "register class shouldn't return 0")

	init_vk_table()
}

// shutdown destroys any remaining windows (best-effort), then frees the window system's
// state. Every outstanding Window_Handle is dead afterwards — a window whose native
// destroy fails is still evicted from the pool, so shutdown always terminates.
shutdown :: proc() {
	for !handle_pool.is_empty(&g_window_pool) {
		h := handle_pool.slice(&g_window_pool)[0].handle
		if destroy_window(h) != .None {
			handle_pool.remove(&g_window_pool, h)
		}
	}
	handle_pool.destroy(&g_window_pool)

	win32.UnregisterClassW(CLASS_NAME, win32.HINSTANCE(win32.GetModuleHandleW(nil)))
}

// create_window creates a native window per `desc` (ZII ⇒ visible 1280×720 "odyne").
// The returned handle is the only name upper layers ever have for the window.
create_window :: proc(desc: Window_Desc) -> (h: Window_Handle, err: Window_Error) {
	title := len(desc.title) == 0 ? "odyne" : desc.title
	width := desc.width <= 0 ? 1280 : desc.width
	height := desc.height <= 0 ? 720 : desc.height

	window_state := Window_State {
		size = {width, height},
	}

	hp_err: handle_pool.Error
	h, hp_err = handle_pool.add(&g_window_pool, window_state)
	if hp_err != .None {
		err = .Create_Failed
		return
	}

	dpix, dpiy: win32.UINT
	win32.GetDpiForMonitor(
		win32.MonitorFromWindow(nil, .MONITOR_DEFAULTTOPRIMARY),
		{},
		&dpix,
		&dpiy,
	)

	initial_rect := win32.RECT{0, 0, i32(width), i32(height)}

	style :: win32.WS_OVERLAPPEDWINDOW
	win32.AdjustWindowRectExForDpi(&initial_rect, style, false, {}, dpix)

	hinstance := win32.HINSTANCE(win32.GetModuleHandleW(nil))
	hwnd := win32.CreateWindowExW(
		0,
		CLASS_NAME,
		win32.utf8_to_wstring(title),
		style,
		win32.CW_USEDEFAULT,
		win32.CW_USEDEFAULT,
		i32(initial_rect.right - initial_rect.left),
		i32(initial_rect.bottom - initial_rect.top),
		nil,
		nil,
		hinstance,
		rawptr(uintptr(h)),
	)
	if hwnd == nil {
		handle_pool.remove(&g_window_pool, h)
		h = 0
		err = .Create_Failed
		return
	}

	if !desc.hidden {
		win32.ShowWindow(hwnd, win32.SW_SHOWNORMAL)
	}

	ws_ptr, ws_ok := get_state(h)
	assert(ws_ok, "window state lookup shouldn't fail")
	ws_ptr.hwnd = hwnd

	return
}

// destroy_window closes the native window and stales the handle. This is the ONLY
// path that destroys a window — a user's close click merely sets should_close.
destroy_window :: proc(h: Window_Handle) -> Window_Error {
	window_state, ok := get_state(h)
	if !ok {
		return .Invalid_Handle
	}
	hwnd := window_state.hwnd

	if !win32.DestroyWindow(hwnd) {
		return .Destroy_Failed
	}

	if handle_pool.remove(&g_window_pool, h) != .None {
		return .Invalid_Handle
	}

	return .None
}

// poll_events drains this thread's message queue without blocking — call once per
// frame. All window state visible through the queries reflects the drained messages.
poll_events :: proc() {
	for &window_state in handle_pool.slice(&g_window_pool) {
		begin_input_frame(&window_state)
	}

	msg: win32.MSG
	for win32.PeekMessageW(&msg, nil, 0, 0, win32.PM_REMOVE) {
		win32.TranslateMessage(&msg)
		win32.DispatchMessageW(&msg)
	}
}

// is_open reports whether `h` names a live window. Garbage-safe.
is_open :: proc(h: Window_Handle) -> bool {
	return handle_pool.has(&g_window_pool, h)
}

// should_close reports whether the user has requested close (✕ / Alt+F4) since
// create. The window stays open until destroy_window. Invalid handle → false.
should_close :: proc(h: Window_Handle) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return window_state.close_requested
}

// has_focus reports whether `h` currently holds keyboard focus, as of the last
// poll_events (WM_SETFOCUS / WM_KILLFOCUS bookkeeping). Invalid handle → false.
has_focus :: proc(h: Window_Handle) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	return window_state.focused
}

set_should_close :: proc(h: Window_Handle, should_close: bool = true) -> bool {
	window_state, ok := get_state(h)
	if !ok {
		return false
	}
	window_state.close_requested = should_close
	return window_state.close_requested
}

set_window_title :: proc(h: Window_Handle, title: string) {
	window_state, ok := get_state(h)
	if !ok {
		return
	}

	win32.SetWindowTextW(window_state.hwnd, win32.utf8_to_wstring(title))
}

// client_size returns the window's current client area, or {0,0} on an invalid handle.
client_size :: proc(h: Window_Handle) -> [2]i32 {
	window_state, ok := get_state(h)
	if !ok {
		return {0, 0}
	}
	return window_state.size
}

@(private = "file")
register_class :: proc(instance: win32.HINSTANCE) -> win32.ATOM {
	brush := win32.HBRUSH(win32.GetStockObject(win32.BLACK_BRUSH))

	wcx := win32.WNDCLASSEXW {
		cbSize        = size_of(win32.WNDCLASSEXW),
		style         = win32.CS_HREDRAW | win32.CS_VREDRAW | win32.CS_OWNDC,
		hbrBackground = brush,
		lpfnWndProc   = wndproc,
		hInstance     = instance,
		lpszClassName = CLASS_NAME,
	}
	atom := win32.RegisterClassExW(&wcx)
	return atom
}

@(private = "file")
wndproc :: proc "system" (
	hwnd: win32.HWND,
	msg: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	context = runtime.default_context()
	switch msg {
	case win32.WM_CREATE:
		return wm_create(hwnd, lparam)
	case win32.WM_CLOSE:
		return wm_close(hwnd, msg, wparam, lparam)
	case win32.WM_SIZE:
		return wm_size(hwnd, msg, wparam, lparam)
	case win32.WM_KEYDOWN,
	     win32.WM_KEYUP,
	     win32.WM_SYSKEYDOWN,
	     win32.WM_SYSKEYUP,
	     win32.WM_MBUTTONDOWN,
	     win32.WM_MBUTTONUP,
	     win32.WM_RBUTTONDOWN,
	     win32.WM_RBUTTONUP,
	     win32.WM_LBUTTONDOWN,
	     win32.WM_LBUTTONUP,
	     win32.WM_XBUTTONDOWN,
	     win32.WM_XBUTTONUP,
	     win32.WM_MOUSEMOVE,
	     win32.WM_MOUSEWHEEL:
		return wm_input(hwnd, msg, wparam, lparam)
	case win32.WM_SETFOCUS:
		return wm_set_focus(hwnd, msg, wparam, lparam)
	case win32.WM_KILLFOCUS:
		return wm_kill_focus(hwnd, msg, wparam, lparam)
	case win32.WM_CAPTURECHANGED:
		return wm_capture_changed(hwnd, msg, wparam, lparam)
	case:
		return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
	}
}

@(private = "file")
wm_create :: proc(hwnd: win32.HWND, lparam: win32.LPARAM) -> win32.LRESULT {
	pcs := (^win32.CREATESTRUCTW)(rawptr(uintptr(lparam)))
	assert(pcs != nil, "pcs shouldn't be nil")

	wh := (Window_Handle)(uintptr(pcs.lpCreateParams))
	win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, win32.LONG_PTR(wh))

	return 0
}

@(private = "file")
wm_close :: proc(
	hwnd: win32.HWND,
	msg: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	window_state, ok := get_state_from_win(hwnd)
	if !ok {
		return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
	}

	window_state.close_requested = true
	return 0
}

@(private = "file")
wm_size :: proc(
	hwnd: win32.HWND,
	msg: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	window_state, ok := get_state_from_win(hwnd)
	if !ok {
		return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
	}

	window_state.size = {i32(win32.LOWORD(lparam)), i32(win32.HIWORD(lparam))}
	return 0
}

@(private = "file")
wm_input :: proc(
	hwnd: win32.HWND,
	msg: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	window_state, ok := get_state_from_win(hwnd)
	if !ok {
		return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
	}

	processed := handle_input_message(window_state, hwnd, msg, wparam, lparam)
	if msg == win32.WM_SYSKEYDOWN || msg == win32.WM_SYSKEYUP {
		return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
	}
	return processed == true ? 0 : win32.DefWindowProcW(hwnd, msg, wparam, lparam)
}

@(private = "file")
wm_set_focus :: proc(
	hwnd: win32.HWND,
	msg: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	window_state, ok := get_state_from_win(hwnd)
	if !ok {
		return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
	}

	window_state.focused = true

	return 0
}

@(private = "file")
wm_kill_focus :: proc(
	hwnd: win32.HWND,
	msg: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	window_state, ok := get_state_from_win(hwnd)
	if !ok {
		return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
	}

	if window_state.holds_capture {
		win32.ReleaseCapture()
	}
	clear_input_states(window_state)
	window_state.focused = false

	return 0
}

@(private = "file")
wm_capture_changed :: proc(
	hwnd: win32.HWND,
	msg: win32.UINT,
	wparam: win32.WPARAM,
	lparam: win32.LPARAM,
) -> win32.LRESULT {
	window_state, ok := get_state_from_win(hwnd)
	if !ok {
		return win32.DefWindowProcW(hwnd, msg, wparam, lparam)
	}

	if window_state.holds_capture {
		clear_buttons(window_state)
	}
	return 0
}

// get_state resolves a public handle to its pool state — the shared preamble of every
// per-window query and mutator. Invalid handle → (nil, false).
@(private)
get_state :: proc(h: Window_Handle) -> (^Window_State, bool) {
	window_state, err := handle_pool.get_ptr(&g_window_pool, h)
	return window_state, err == .None
}

@(private = "file")
get_state_from_win :: proc(hwnd: win32.HWND) -> (^Window_State, bool) {
	wh := Window_Handle(win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA))
	return get_state(wh)
}

