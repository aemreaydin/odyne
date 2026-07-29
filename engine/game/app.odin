package game

import "core:time"
import "engine:core/timing"
import "engine:platform"

// The main loop — engine-owned, application-driven-by-callback.
//
// WHY THE LOOP LIVES HERE AND NOT IN core
//
// The loop has to pump the platform, call the renderer, and call application code. `core` may
// import none of those: the layering law is core → platform → render → game, downward only, and
// a driver in `core` calling up into the application is exactly the violation. `game` is the top
// engine layer, so from here every one of those calls is downward and no dependency inversion,
// proc-pointer trickery or `rawptr` type erasure is needed to make it legal. The application
// (examples/testbed) sits above `game` and hands its work in as callbacks.
//
// The alternative — an app-owned `for` calling engine pieces — stays possible and costs nothing:
// `timing.Pacer` is public and knows nothing about this file, so a tool, a cooker or a test
// harness can write its own three-line loop. This is the convenience path, not the only path.
// SDL and sokol_app take the same inverted-control shape, and on some platforms (iOS, the
// browser) an app-owned infinite loop is not permitted to exist at all
// [SDL SDL_AppIterate], [SOKOL sokol_app.h].

DEFAULT_MAX_DT :: 100 * time.Millisecond
DEFAULT_TARGET_FPS :: 60
DEFAULT_SPIN_MARGIN :: 1 * time.Millisecond

// App_Config — everything the loop needs to start. Zero value is a working configuration: every
// field's zero means "use the default", so `run({}, cb)` runs a paced 50 Hz loop in a default
// window.
//
// `run` RESOLVES this once — every zero replaced by the default it stood for — and keeps the
// resolved copy on `App`, where the game reads it and adjusts the live knobs (`target_fps`,
// `unlimited`) between frames. One copy of every number, no publish step.
App_Config :: struct {
	// The window as REQUESTED, at creation time only. It does not track the window afterwards:
	// once the user resizes, `platform.client_size(handle)` is the truth and this is history.
	initial_window: platform.Window_Desc,
	fixed_dt:       time.Duration, // 0 ⇒ timing.DEFAULT_FIXED_DT (50 Hz, exact in ns)
	max_dt:         time.Duration, // 0 ⇒ DEFAULT_MAX_DT — the clock's clamp threshold
	clamp_dt:       time.Duration, // 0 ⇒ fixed_dt — "pretend a hitch was one simulation step"
	target_fps:     int, // 0 ⇒ DEFAULT_TARGET_FPS
	unlimited:      bool, // true ⇒ no limiter; target_fps ignored
	spin_margin:    time.Duration, // 0 ⇒ DEFAULT_SPIN_MARGIN — the waiter's busy-wait tail
}

// App — the loop's whole state, and the view every callback receives.
//
// Deliberately NOT a flattened copy of the clock and the pacer (design amendment 1). Copies mean
// two sources of truth and a publish step to forget every time `Frame_Clock` grows a field, and
// they make the loop recompute the history's min/max every frame — ~25 ns for numbers only a
// debug readout ever reads (m11-01 measured those scans at 12.5 ns each). The owners live here
// instead, so the game reads them through the vocabulary it already built:
//
//	app.clock.dt · app.clock.raw_dt · app.clock.elapsed · app.clock.frame_index
//	timing.history_average(&app.clock.history) · timing.history_min / _max
//	timing.sim_time(&app.pacer) · timing.step_seconds(&app.pacer)
//
// The cost of that trade, stated plainly: Odin has no `const` and no per-field privacy, so a game
// CAN write `app.clock.origin` and corrupt real time — this comment is the only thing stopping
// it. The fields the game is invited to write are `paused` and the live knobs in `cfg`.
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

	// NOTE: the clock is deliberately NOT started here -- `run` starts it after the application's
	// init callback returns (see below). Until then `app.clock` is zero-valued, which is the honest
	// state: the timeline has not begun.
	timing.pacer_init(&app.pacer, app.cfg.fixed_dt)

	return app
}

// App_Callbacks — the application's per-frame work. Every field is optional; a zero value runs a
// loop that pumps events and exits on close.
//
// THE ORDERING IS THE CONTRACT, and the reason there are two update callbacks instead of one:
//
//	frame  — EXACTLY once per frame, after the event pump, before any step. The only place input
//	         EDGES (key_pressed / key_released) may be read, because "one frame" is the unit they
//	         are retired in. Edges are latched here into game-owned intent.
//	step   — 0..N times per frame, always with `fixed_dt` seconds. Reads level state (key_down)
//	         and latched intent; the first step to act on an intent clears it.
//	render — exactly once per frame, after the steps, with the frame's alpha.
//
// Read an edge inside `step` instead and both failure modes are live: a frame that runs two steps
// double-counts the press, and a frame that runs zero steps never sees it at all — and at a 50 Hz
// step on a 60 fps display, one frame in six runs zero steps. The latch is the only shape that
// survives both, and it cannot live below `frame`, because a 0-step frame has no step to put it
// in. This is why Unity has both Update and FixedUpdate [UNITY-TIME fixed-updates].
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

// run — own the frame loop until the window asks to close.
//
// Owns: platform init/shutdown, one window, the frame clock, the pacer, the frame limiter, and
// the per-frame temp-allocator reset. Tears the window and platform down on every exit path.
//
// One frame, in order:
//
//	frame_start(clock, now) → poll_events → cb.frame → pacer_advance(dt) → cb.step × count
//	→ cb.render(alpha) → free_all(temp) → wait_until(frame_deadline)
//
// `wait_until` returns the timestamp it reached, and that timestamp is the next frame's `now` —
// so the limiter and the clock share a single clock read and "one read per frame" survives the
// loop rather than being a rule someone has to remember.
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

	// The timeline starts HERE, once the application's own initialization is done. `clock_init` IS
	// the start of frame 0 (m11-01), so everything before this point -- platform init, window
	// creation, and the game loading assets or, from m20-03, building a device and a swapchain --
	// sits deliberately outside it. Start the clock any earlier and frame 1 reports the whole
	// startup as a hitch, which then sits in the history's max for the next HISTORY_CAPACITY frames.
	//
	// ONE clock read feeds both the origin and the first frame_start, so frame 1's dt is exactly 0.
	// That is legal by contract and is precisely why m11-01 needed no first-frame special case.
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
			// A paused frame owes no steps -- but the PHASE must not move. `App.steps` is this
			// frame's report, so it has to be written on every frame, including this one: leaving
			// the previous frame's value in place makes every readout built from it lie for the
			// duration of the pause. Zeroing the whole struct is the tempting mistake, because
			// alpha is what the renderer interpolates with, and snapping it to 0 would jerk the
			// picture back a whole step the moment the game is paused. The accumulator does not
			// move while paused, so the pacer's current phase IS the frozen phase.
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
			// The deadline is anchored on THIS FRAME'S START (`clock.prev`, set by frame_start),
			// not on the clock's origin. `timing.frame_deadline` offers the origin-anchored grid
			// instead, and it is the better answer whenever pacing is uninterrupted, because a
			// frame that overshoots is absorbed by the next one rather than pushing the schedule
			// out. But the grid is only meaningful if EVERY frame has been paced to it: frames
			// that skip the wait -- limiter toggled off, target rate changed, machine suspended --
			// advance frame_index without spending wall time, so the grid ends up far ahead of
			// reality and the first paced frame afterwards waits for the whole difference. 20
			// free-running frames measured a 353 ms stall at a 16.67 ms target.
			//
			// A one-frame-old anchor cannot go stale: nothing older than this frame is remembered.
			// The price is that overshoot is never corrected, so the loop settles marginally BELOW
			// the target rate instead of holding an exact schedule -- the trade Handmade Hero
			// makes with targetSecondsPerFrame [HMH day 18]. For a limiter that exists only until
			// the swapchain arrives, a rate that is 0.1% slow beats a stall that looks like a
			// crash. Task 6.1(b) measures what that costs on Windows.
			period := time.Second / time.Duration(app.cfg.target_fps)
			deadline := time.tick_add(app.clock.prev, period)
			now = timing.wait_until(deadline, app.cfg.spin_margin)
		}

		free_all(context.temp_allocator)
	}

	return .None
}
