#+build windows
package main

// The Windows system timer resolution, as a two-line seam so the bench body stays portable.
//
// `timeBeginPeriod` *"requests a minimum resolution for periodic timers"*, and its scope has
// changed twice: before Windows 10 2004 it was a global system setting, and since then it applies
// per-process to processes that call it, while *"For processes which have not called this function,
// Windows does not guarantee a higher resolution than the default system resolution"*
// [MS-TIMEPERIOD]. That is exactly why this bench measures three phases -- a process that never
// asks may be sitting on the coarse default, and a dependency may have asked on its behalf.
import win "core:sys/windows"

TIMER_RESOLUTION_AVAILABLE :: true

// TIMERR_NOERROR is 0; anything else means the requested resolution is out of range.
set_timer_resolution :: proc(ms: u32) -> bool {
	return win.timeBeginPeriod(win.UINT(ms)) == 0
}

clear_timer_resolution :: proc(ms: u32) {
	win.timeEndPeriod(win.UINT(ms))
}
