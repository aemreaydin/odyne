package timing

import "base:intrinsics"
import "core:time"

// ~1.7 s of history at 60 fps, 800 B held inline: the clock never allocates.
HISTORY_CAPACITY :: 100

/*
Fixed-capacity ring of real, pre-clamp frame durations. The mean is O(1); min and max are
O(n) scans, because a sliding window that evicts its own extreme cannot recover the next
one from a running scalar.
*/
Frame_History :: struct {
	samples: [HISTORY_CAPACITY]time.Duration,
	next:    int, // write cursor
	count:   int, // valid samples, saturating at HISTORY_CAPACITY
	sum:     i64, // nanoseconds; exact forever, being an integer sum
}

/*
The real timeline; `elapsed` is always `prev - origin`. Once any frame has been clamped the
sum of reported deltas no longer equals elapsed — that is correct, not drift. The game
timeline is a separate concern; see `Pacer`.
*/
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

// Starts frame 0 at the caller-supplied timestamp. A `max_dt` of 0 disables clamping.
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

// Ends the current frame and begins the next; call exactly once per frame. Returns the
// clamped delta. The history records the raw delta, hitches included.
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

// The clamped delta in seconds. Never smoothed — a smoothed delta makes simulated time
// diverge from real time permanently.
dt_seconds :: proc(clock: ^Frame_Clock) -> f32 {
	return f32(time.duration_seconds(clock.dt))
}

// Real time since init. f64 because f32 reaches a ~1 ms ULP after 2.8 hours of uptime.
elapsed_seconds :: proc(clock: ^Frame_Clock) -> f64 {
	return time.duration_seconds(clock.elapsed)
}

/*
The current frame's deadline on an origin-anchored grid, `origin + (frame_index+1)*period`.
Overshoot is corrected rather than accumulated, but the grid is only meaningful while every
frame has been paced to it — the engine's own loop anchors on the frame start instead, and
does not call this.

`period` must be a small duration in nanoseconds. A period near `MAX_DURATION`, or one in
platform ticks rather than nanoseconds, overflows the multiply.
*/
frame_deadline :: proc(clock: ^Frame_Clock, period: time.Duration) -> time.Tick {
	return time.tick_add(clock.origin, time.Duration(clock.frame_index + 1) * period)
}

// Records one frame duration. Called by `frame_start`; public so the history stands alone.
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

// Mean of the samples present, not of the capacity. 0 when empty.
history_average :: proc(h: ^Frame_History) -> time.Duration {
	if h.count == 0 {
		return 0
	}
	return time.Duration(h.sum / i64(h.count))
}

// Smallest sample present; an O(n) scan. 0 when empty.
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

// Largest sample present; an O(n) scan. 0 when empty.
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

// Sleep is issued in chunks rather than one long call because OS sleep overshoot scales
// with sleep length — on darwin `time.sleep` returns 27–50% late — so a single long sleep
// blows past the deadline before the spin tail gets a turn. On Windows the chunk cannot go
// below the system timer resolution, so a limiter there wants a larger spin_margin instead.
SLEEP_CHUNK :: 1 * time.Millisecond

/*
Blocks until `deadline` and returns the timestamp actually reached, which the caller can use
as its next frame timestamp instead of reading the clock again. Never returns early; a
deadline already passed returns immediately.

Sleeps while more than `spin_margin` remains, then busy-waits the tail, because OS sleep is
a lower bound rather than a promise. `spin_margin` of 0 is pure sleep; a margin at or above
the remaining time is pure spin, which burns a core for that whole span.
*/

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
			// A CPU hint, not `thread.yield()`: yielding can cost a whole timeslice on a busy
			// machine, which is the opposite of what a precision tail wants.
			intrinsics.cpu_relax()
		}
	}
}
