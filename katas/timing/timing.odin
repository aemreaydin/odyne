package timing

import "core:thread"
import "core:time"

// Ring capacity: ~1.7 s of history at 60 fps. [100]Duration is 800 B inline — the clock
// never allocates, before or after init.
HISTORY_CAPACITY :: 100

// Frame_History — fixed-capacity ring of REAL (pre-clamp) frame durations.
//
// `sum` is maintained on write (add the new sample, subtract the evicted one) and is exact
// forever, because the samples are integer nanoseconds; the same trick on f32 samples would
// drift. min/max are NOT maintained: a sliding window that evicts its own extreme cannot
// recover the next one from a scalar, so they are scanned on read.
Frame_History :: struct {
	samples: [HISTORY_CAPACITY]time.Duration,
	next:    int, // write cursor
	count:   int, // valid samples, saturating at HISTORY_CAPACITY
	sum:     i64, // sum of samples[0:count], in nanoseconds
}

// Frame_Clock — the real timeline.
//
// Invariant: elapsed == prev - origin. Once a frame is clamped, the sum of dts no longer
// equals elapsed; that is correct, not a bug. A pausable/scalable GAME timeline is a second
// clock fed the real dt, and is deliberately out of scope here (GEA §8.4).
Frame_Clock :: struct {
	origin:      time.Tick, // set once by clock_init; never written again
	prev:        time.Tick, // timestamp at which the current frame started
	dt:          time.Duration, // delta of the frame that just ended, AFTER clamp policy
	raw_dt:      time.Duration, // that delta before clamping — the hitch, kept observable
	elapsed:     time.Duration, // prev - origin: real time since init
	frame_index: u64, // 0 for the frame clock_init started; +1 per frame_start
	max_dt:      time.Duration, // clamp threshold; 0 disables clamping
	clamp_dt:    time.Duration, // value substituted when raw_dt exceeds max_dt
	history:     Frame_History,
}

// clock_init — start frame 0. `now` is the caller's clock read (time.tick_now()).
// Sets origin = prev = now, zeroes the deltas and elapsed, empties the history, and stores
// the clamp policy.
clock_init :: proc(
	clock: ^Frame_Clock,
	now: time.Tick,
	max_dt: time.Duration = 100 * time.Millisecond,
	clamp_dt: time.Duration = time.Second / 60,
) {
	clock.origin = now
	clock.prev = now

	clock.dt = 0
	clock.raw_dt = 0
	clock.elapsed = 0
	clock.frame_index = 0

	clock.max_dt = max_dt
	clock.clamp_dt = clamp_dt

	clock.history = {}
}

// frame_start — end the current frame and begin the next. Exactly one call per frame.
//
// raw_dt = now - prev; dt = clamp policy applied to raw_dt; elapsed = now - origin;
// frame_index += 1; prev = now; the RAW delta is pushed to the history (the overlay wants
// real frame times, including the hitches). Returns the clamped dt.
frame_start :: proc(clock: ^Frame_Clock, now: time.Tick) -> (dt: time.Duration) {
	clock.raw_dt = time.tick_diff(clock.prev, now)
	assert(clock.raw_dt >= 0, "should be positive")
	if clock.max_dt <= 0 {
		clock.dt = clock.raw_dt
	} else {
		clock.dt = clock.raw_dt > clock.max_dt ? clock.clamp_dt : clock.raw_dt
	}

	clock.prev = now
	clock.elapsed = time.tick_diff(clock.origin, now)
	clock.frame_index += 1

	history_push(&clock.history, clock.raw_dt)
	dt = clock.dt
	return
}

// dt_seconds — the measured (clamped) delta in seconds, for simulation. NEVER smoothed:
// a smoothed dt makes sim time diverge from real time permanently. f32 because gameplay
// math and core:math/linalg are f32, and 16.7 ms in f32 carries a ~2 ns ULP.
dt_seconds :: proc(clock: ^Frame_Clock) -> f32 {
	return f32(time.duration_seconds(clock.dt))
}

// elapsed_seconds — real time since init, in seconds. f64: this is the one place f32 fails
// (~1 ms ULP after 2.8 hours of uptime).
elapsed_seconds :: proc(clock: ^Frame_Clock) -> f64 {
	return time.duration_seconds(clock.elapsed)
}

// frame_deadline — when the CURRENT frame should end, for a target period.
//
// Derived from origin, not from "now": origin + (frame_index+1)*period. A deadline computed
// from a fixed origin cannot drift, so sleep overshoot is corrected instead of accumulated.
// After an overrun the deadline is already in the past — wait_until then returns at once.
//
// Overflow: the multiply is safe because BOTH operands are bounded by design. At a 16.67 ms
// period, (frame_index+1)*period needs ~5.5e11 frames — ~290 years at 60 fps, ~29 at 1000 fps
// — to overflow i64 nanoseconds, and frame_index can only reach that by counting real frames.
// It stops being safe in two reachable ways: a `period` that isn't small (MAX_DURATION as a
// "wait forever" idiom), or a `period` that isn't in nanoseconds. The latter is the [MS-QPC]
// trap proper — raw platform ticks fed into `ticks * 1e9` overflow after ~15 minutes of
// uptime at a 10 MHz counter, and after ~9 SECONDS on an Arm 1 GHz system counter.
frame_deadline :: proc(clock: ^Frame_Clock, period: time.Duration) -> time.Tick {
	return time.tick_add(clock.origin, time.Duration(clock.frame_index + 1) * period)
}

// history_push — record one frame duration. Called by frame_start; public so the history
// can be tested (and reused) on its own.
history_push :: proc(h: ^Frame_History, d: time.Duration) {
	size := len(h.samples)

	if h.count >= size {
		h.sum -= i64(h.samples[h.next])
	}

	h.samples[h.next] = d
	h.next = (h.next + 1) % size
	h.sum = h.sum + i64(d)
	h.count = min(h.count + 1, size)
}

// history_average — mean of the samples currently in the window (divides by count, not by
// capacity). 0 when the history is empty.
history_average :: proc(h: ^Frame_History) -> time.Duration {
	if h.count == 0 {
		return 0
	}
	return time.Duration(h.sum / i64(h.count))
}

// history_min — smallest sample in the window (scans samples[0:count]). 0 when empty.
history_min :: proc(h: ^Frame_History) -> time.Duration {
	if h.count == 0 {
		return 0
	}
	min_val := time.MAX_DURATION
	for idx in 0 ..< h.count {
		min_val = min(h.samples[idx], min_val)
	}
	return min_val
}

// history_max — largest sample in the window (scans samples[0:count]). 0 when empty.
history_max :: proc(h: ^Frame_History) -> time.Duration {
	if h.count == 0 {
		return 0
	}
	max_val := time.MIN_DURATION
	for idx in 0 ..< h.count {
		max_val = max(h.samples[idx], max_val)
	}
	return max_val
}

// wait_until — block until `deadline`, then return the timestamp actually reached.
//
// The only proc here that touches the real clock. Sleeps while more than `spin_margin`
// remains, then busy-waits the tail: OS sleep is a lower bound, not a promise
// ([SDL SDL_DelayNS], [ODIN-TIME accurate_sleep]). Never returns before `deadline`.
// A deadline already in the past returns immediately without sleeping; spin_margin == 0 is
// pure sleep; spin_margin >= the remaining time is pure spin.
//
// The returned tick is the caller's next frame_start timestamp — so a frame limiter costs
// no extra clock read.
//
// One loop, one exit: the ONLY `return` is under `remaining <= 0`, which is what makes
// "never returns before the deadline" structural instead of a check to remember. Every
// iteration re-reads the clock, so a sleep that undershoots (Windows `Sleep` truncates to
// whole milliseconds) is simply slept again rather than trusted.
//
// Sleeps are CHUNKED at SLEEP_CHUNK rather than issued as one big sleep, because sleep
// overshoot is proportional to sleep length, not a constant: measured on darwin
// (`clock_gettime`/`nanosleep`), `time.sleep` returns 27–50% late — +0.5 ms on a 1 ms request,
// +4.5 ms on a 16.7 ms one. One big sleep therefore blows past the deadline before the spin
// phase ever gets a turn (measured: +4.9 ms mean at a 16.7 ms wait), while chunking bounds the
// over-commitment to one chunk and lets the loop re-decide (measured: +0.1 us). The chunk is
// the floor on precision here: on Windows it cannot go below the system timer resolution, so a
// limiter there wants a larger spin_margin instead.
SLEEP_CHUNK :: 1 * time.Millisecond

wait_until :: proc(
	deadline: time.Tick,
	spin_margin: time.Duration = 1 * time.Millisecond,
) -> (
	now: time.Tick,
) {
	for {
		now = time.tick_now()
		remaining := time.tick_diff(now, deadline)
		if remaining <= 0 {
			return
		}
		if remaining > spin_margin {
			time.sleep(min(remaining - spin_margin, SLEEP_CHUNK))
		} else {
			thread.yield()
		}
	}
}
