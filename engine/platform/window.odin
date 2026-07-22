package platform

// m10-01 — the platform window: portable surface (types only; all Win32 lives in
// window_windows.odin). The layering law's first OS boundary: no HWND, MSG, or
// core:sys/windows type appears below this comment or in any public signature.
//
// Agreed interface: openspec/changes/lesson-m10-01-win32-window/design.md
// Tests: odin test engine/platform -collection:engine=engine -define:ODIN_TEST_THREADS=1
// (single-threaded: Win32 message queues are per-thread; the window system is
// main-thread-only by contract)

Window_Handle :: distinct u64

// Window_Desc — creation config, ZII-friendly: the zero value yields a visible
// 1280×720 window titled "odyne". Tests pass hidden = true (fully functional
// window, no ShowWindow, nothing on screen).
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

