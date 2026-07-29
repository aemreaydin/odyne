#+build !windows
package main

// No equivalent knob elsewhere: `timeBeginPeriod` is Windows-only. On darwin `time.sleep` is
// `nanosleep`, whose granularity is not a process-wide setting anyone can request
// [ODIN-TIME accurate_sleep], so the third measurement phase simply reports as unavailable.

TIMER_RESOLUTION_AVAILABLE :: false

set_timer_resolution :: proc(ms: u32) -> bool {
	return false
}

clear_timer_resolution :: proc(ms: u32) {
}
