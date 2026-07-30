package game

import "core:time"
import "engine:core/timing"
import "engine:platform"

DEFAULT_MAX_DT :: 100 * time.Millisecond
DEFAULT_TARGET_FPS :: 60
DEFAULT_SPIN_MARGIN :: 1 * time.Millisecond

/*
Everything the loop needs to start. The zero value is a working configuration — every
field's zero means "use the default". `run` resolves it once and keeps the resolved copy
on `App`, where `target_fps` and `unlimited` may be adjusted between frames.
*/
App_Config :: struct {
	// As requested at creation only; after a resize `platform.client_size` is the truth.
	initial_window: platform.Window_Desc,
	fixed_dt:       time.Duration, // 0 ⇒ timing.DEFAULT_FIXED_DT (50 Hz, exact in ns)
	max_dt:         time.Duration, // 0 ⇒ DEFAULT_MAX_DT — the clock's clamp threshold
	clamp_dt:       time.Duration, // 0 ⇒ fixed_dt — "pretend a hitch was one simulation step"
	target_fps:     int, // 0 ⇒ DEFAULT_TARGET_FPS
	unlimited:      bool, // true ⇒ no limiter; target_fps ignored
	spin_margin:    time.Duration, // 0 ⇒ DEFAULT_SPIN_MARGIN — the waiter's busy-wait tail
}

/*
The loop's whole state, and the view every callback receives. The clock and pacer are the
owners rather than flattened copies, so the game reads them through their own vocabulary —
`timing.history_average(&app.clock.history)`, `timing.sim_time(&app.pacer)`.

Odin has no per-field privacy, so a game CAN write `app.clock.origin` and corrupt real
time. The fields it is invited to write are `paused` and the live knobs in `cfg`.
*/
App :: struct {
	cfg:    App_Config, // resolved — no zeroes-mean-default left in it
	window: platform.Window_Handle,
	clock:  timing.Frame_Clock, // the real timeline
	pacer:  timing.Pacer, // the game timeline
	steps:  timing.Frame_Steps, // THIS frame's report; the pacer does not keep it
	paused: bool, // while set, no time is fed to the pacer; resuming does not replay it
}

@(private)
init :: proc(cfg: App_Config, window: platform.Window_Handle) -> (app: App) {
	app.cfg = cfg

	app.cfg.max_dt = app.cfg.max_dt != 0 ? app.cfg.max_dt : DEFAULT_MAX_DT
	app.cfg.fixed_dt = app.cfg.fixed_dt != 0 ? app.cfg.fixed_dt : timing.DEFAULT_FIXED_DT
	app.cfg.clamp_dt = app.cfg.clamp_dt != 0 ? app.cfg.clamp_dt : app.cfg.fixed_dt
	app.cfg.target_fps = app.cfg.target_fps != 0 ? app.cfg.target_fps : DEFAULT_TARGET_FPS
	app.cfg.spin_margin = app.cfg.spin_margin != 0 ? app.cfg.spin_margin : DEFAULT_SPIN_MARGIN

	assert(app.cfg.max_dt >= app.cfg.fixed_dt, "max_dt should be larger than fixed_dt")
	assert(app.cfg.target_fps > 0, "target_fps must be positive")
	app.window = window

	// The clock is deliberately not started here; `run` starts it once the application's init
	// callback has returned. Until then `app.clock` is zero — the timeline has not begun.
	timing.pacer_init(&app.pacer, app.cfg.fixed_dt)

	return app
}

/*
The application's per-frame work. Every field is optional; a zero value runs a loop that
pumps events and exits on close.

The call order is part of the contract:

	frame  — once per frame, after the event pump, before any step
	step   — 0..N times per frame, always with the fixed step as its delta
	render — once per frame, after the steps, with the frame's alpha

Input edges (`key_pressed` / `key_released`) may only be read in `frame`, which is the unit
they are retired in; latch them into game-owned intent for `step` to consume. An edge read
inside `step` is double-counted on a two-step frame and missed entirely on a zero-step one,
and at a 50 Hz step on a 60 fps display one frame in six takes no step.
*/
App_Callbacks :: struct {
	user:     rawptr, // opaque application state, handed back to every callback
	init:     proc(app: ^App, user: rawptr) -> bool, // false ⇒ .Init_Callback_Failed
	frame:    proc(app: ^App, user: rawptr),
	step:     proc(app: ^App, user: rawptr, dt: f32),
	render:   proc(app: ^App, user: rawptr, alpha: f32),
	shutdown: proc(app: ^App, user: rawptr),
}

App_Error :: enum {
	None,
	Init_Failed, // the platform layer failed to initialize
	Window_Failed, // the window could not be created
	Init_Callback_Failed, // the application's init callback returned false
}

/*
Owns the frame loop until the window asks to close: platform init and shutdown, one window,
the frame clock, the pacer, the frame limiter, and the per-frame temp-allocator reset. The
window and platform are torn down on every exit path.

One frame, in order:

	frame_start → poll_events → cb.frame → pacer_advance → cb.step × count
	→ cb.render(alpha) → free_all(temp) → wait for the frame's deadline

The waiter returns the timestamp it reached and that becomes the next frame's `now`, so the
loop reads the clock exactly once per frame.
*/
run :: proc(cfg: App_Config, cb: App_Callbacks) -> App_Error {
	if platform.init() != .None {
		return .Init_Failed
	}
	defer platform.shutdown()

	wnd_handle, wnd_err := platform.create_window(cfg.initial_window)
	if wnd_err != .None {
		return .Window_Failed
	}

	app := init(cfg, wnd_handle)
	if cb.init != nil && !cb.init(&app, cb.user) {
		return .Init_Callback_Failed
	}
	defer if cb.shutdown != nil {
		cb.shutdown(&app, cb.user)
	}

	// The timeline starts here, after application init, so asset loading and device creation
	// sit outside it. Started any earlier, frame 1 reports the whole startup as a hitch and it
	// stays in the history's max for HISTORY_CAPACITY frames. One clock read feeds both the
	// origin and the first frame_start, so frame 1's dt is exactly 0.
	now := time.tick_now()
	timing.clock_init(&app.clock, now, app.cfg.max_dt, app.cfg.clamp_dt)

	for {
		if platform.should_close(wnd_handle) {
			break
		}

		dt := timing.frame_start(&app.clock, now)
		platform.poll_events()
		if cb.frame != nil {
			cb.frame(&app, cb.user)
		}

		if app.paused {
			// A paused frame owes no steps, but the phase must not move: alpha is what the
			// renderer interpolates with, so zeroing it would jerk the picture back a whole step
			// on pause. The accumulator is frozen, so the pacer's current phase is the right one.
			app.steps = {
				count = 0,
				alpha = timing.pacer_alpha(&app.pacer),
			}
		} else {
			app.steps = timing.pacer_advance(&app.pacer, dt)
			// Loop-invariant: the step never changes while the pacer is running.
			step_dt := timing.step_seconds(&app.pacer)
			for _ in 0 ..< app.steps.count {
				if cb.step != nil {
					cb.step(&app, cb.user, step_dt)
				}
			}
		}

		if cb.render != nil {
			cb.render(&app, cb.user, app.steps.alpha)
		}

		if app.cfg.unlimited {
			now = time.tick_now()
		} else {
			// Anchored on this frame's start, not on the clock's origin: an origin-anchored grid
			// goes stale as soon as a frame skips the wait (limiter toggled, rate changed, machine
			// suspended), and the next paced frame then waits off the whole difference — measured
			// at a 353 ms stall after 20 free-running frames at a 16.67 ms target. The price of the
			// one-frame anchor is that overshoot is never corrected, so the rate settles marginally
			// below target.
			period := time.Second / time.Duration(app.cfg.target_fps)
			deadline := time.tick_add(app.clock.prev, period)
			now = timing.wait_until(deadline, app.cfg.spin_margin)
		}

		free_all(context.temp_allocator)
	}

	return .None
}
