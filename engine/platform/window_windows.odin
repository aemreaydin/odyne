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
}

// shutdown destroys any remaining windows, then frees the window system's state.
// Every outstanding Window_Handle is dead afterwards.
shutdown :: proc() {
	slice := handle_pool.slice(&g_window_pool)
	for g_window_pool.count > 0 {
		destroy_window(slice[0].handle)
	}
	handle_pool.destroy(&g_window_pool)

	win32.UnregisterClassW(CLASS_NAME, win32.HINSTANCE(win32.GetModuleHandleW(nil)))
}

// create_window creates a native window per `desc` (ZII ⇒ visible 1280×720 "odyne").
// The returned handle is the only name upper layers ever have for the window.
create_window :: proc(desc: Window_Desc) -> (h: Window_Handle, err: Window_Error) {
	title := len(desc.title) == 0 ? "odyne" : desc.title
	width := desc.width == 0 ? 1280 : desc.width
	height := desc.height == 0 ? 720 : desc.height

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
		err = .Create_Failed
		return
	}

	if !desc.hidden {
		win32.ShowWindow(hwnd, win32.SW_SHOWNORMAL)
	}

	ws_ptr, ws_err := handle_pool.get_ptr(&g_window_pool, h)
	assert(ws_err == .None, "get_ptr shouldn't fail")
	ws_ptr.hwnd = hwnd

	return
}

// destroy_window closes the native window and stales the handle. This is the ONLY
// path that destroys a window — a user's close click merely sets should_close.
destroy_window :: proc(h: Window_Handle) -> Window_Error {
	window_state, err := handle_pool.get_ptr(&g_window_pool, h)
	if err != .None {
		return .Invalid_Handle
	}
	hwnd := window_state.hwnd

	if !win32.DestroyWindow(hwnd) {
		return .Destroy_Failed
	}

	err = handle_pool.remove(&g_window_pool, h)
	if err != .None {
		return .Invalid_Handle
	}

	return .None
}

// poll_events drains this thread's message queue without blocking — call once per
// frame. All window state visible through the queries reflects the drained messages.
poll_events :: proc() {
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
	window_state, err := handle_pool.get_ptr(&g_window_pool, h)
	if err != .None {
		return false
	}
	return window_state.close_requested
}

// client_size returns the window's current client area, or {0,0} on an invalid handle.
client_size :: proc(h: Window_Handle) -> [2]i32 {
	window_state, err := handle_pool.get_ptr(&g_window_pool, h)
	if err != .None {
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
	case win32.WM_DESTROY:
		return wm_destroy(hwnd)
	case win32.WM_SIZE:
		return wm_size(hwnd, msg, wparam, lparam)
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
wm_destroy :: proc(hwnd: win32.HWND) -> win32.LRESULT {
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
get_state_from_win :: proc(hwnd: win32.HWND) -> (window_state: ^Window_State, ok: bool) {
	wh := Window_Handle(win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA))

	err: handle_pool.Error
	window_state, err = handle_pool.get_ptr(&g_window_pool, wh)
	if err != .None {
		return
	}

	ok = true
	return
}

