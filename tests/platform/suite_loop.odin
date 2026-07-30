package main

// Tier 2 — the engine-owned frame loop (`game.run`), asserted through the PUBLIC API against a
// REAL window. Traces to the `game-loop` spec delta.
//
// WHY HERE AND NOT `odin test engine/game`
//
// `run` owns platform init and a window, and the `core:testing` runner dispatches every test onto
// a thread-pool worker, where SDL's video subsystem is main-thread-only on macOS. Same reason the
// window and input contracts live in this harness. Everything in the loop that is *arithmetic* —
// step counting, the interpolation phase, conservation of fed time — is tested where it belongs,
// in `odin test engine/core/timing`, with fabricated deltas and no window at all. What is left
// here is precisely what needs a real frame: the ORDERING of the callbacks, the fixed step
// actually reaching them, hitch absorption, pause, and the limiter.
//
// Every window is `hidden = true`, and every case stops itself by requesting close from the
// per-frame callback — a test that relies on a human closing a window is not a test.

import "core:testing"
import "core:time"
import "engine:core/timing"
import "engine:game"
import "engine:platform"

LOOP_TESTS := []Test_Case {
	{"loop/exits_on_close_request", test_exits_on_close_request},
	{"loop/callback_ordering", test_callback_ordering},
	{"loop/step_dt_is_always_the_fixed_step", test_step_dt_is_always_the_fixed_step},
	{"loop/hitch_is_absorbed", test_hitch_is_absorbed},
	{"loop/pause_freezes_sim_not_real", test_pause_freezes_sim_not_real},
	{"loop/limiter_is_never_faster_than_target", test_limiter_is_never_faster_than_target},
	{"loop/optional_callbacks_are_safe", test_optional_callbacks_are_safe},
	{"loop/limiter_can_be_re_enabled_mid_run", test_limiter_can_be_re_enabled_mid_run},
	{"loop/init_failure_aborts_the_loop", test_init_failure_aborts_the_loop},
}

// Probe — everything the callbacks record, so the assertions can be made after `run` returns.
// Callbacks are plain procs (Odin has no closures), so this travels through `user: rawptr`.
Probe :: struct {
	stop_after:                  u64, // request close once frame_index reaches this
	hitch_on_frame:              u64, // sleep 2 s inside `frame` on this frame (0 ⇒ never)
	hitch_for:                   time.Duration,
	pause_from:                  u64, // set app.paused while frame_index is in [pause_from, pause_until]
	pause_until:                 u64,
	sleep_per_frame:             time.Duration, // burn real time inside `frame`, to force steps to be owed
	init_calls:                  int,
	frame_calls:                 int,
	step_calls:                  int,
	render_calls:                int,
	shutdown_calls:              int,

	// per-frame ordering bookkeeping
	seen_frame:                  bool,
	seen_render:                 bool,
	steps_this_frame:            int,
	ordering_faults:             int,
	count_mismatches:            int,
	max_steps_in_a_frame:        int,
	frames_with_zero_steps:      int,
	step_dt_min:                 f32,
	step_dt_max:                 f32,

	// snapshots
	last_frame_index:            u64,
	last_elapsed:                time.Duration,
	last_sim_time:               time.Duration,
	max_raw_dt:                  time.Duration,
	steps_after_hitch:           int,
	sim_at_pause_start:          time.Duration,
	sim_at_pause_end:            time.Duration,
	elapsed_at_pause_start:      time.Duration,
	elapsed_at_pause_end:        time.Duration,
	steps_on_resume_frame:       int,
	steps_during_pause:          int,
	reported_steps_while_paused: int,
	unlimited_until:             u64, // run unpaced while frame_index <= this, then pace (0 => never)
	max_dt_after_pacing:         time.Duration,
}

probe_init :: proc(app: ^game.App, user: rawptr) -> bool {
	p := cast(^Probe)user
	p.init_calls += 1
	p.step_dt_min = 1e30
	p.step_dt_max = -1e30
	return true
}

probe_frame :: proc(app: ^game.App, user: rawptr) {
	p := cast(^Probe)user

	// Close the previous frame's books: exactly one render must have happened in it.
	if p.frame_calls > 0 {
		if !p.seen_render {
			p.ordering_faults += 1
		}
		if p.steps_this_frame == 0 {
			p.frames_with_zero_steps += 1
		}
		p.max_steps_in_a_frame = max(p.max_steps_in_a_frame, p.steps_this_frame)
	}

	p.frame_calls += 1
	p.seen_frame = true
	p.seen_render = false
	p.steps_this_frame = 0

	p.last_frame_index = app.clock.frame_index
	p.last_elapsed = app.clock.elapsed
	p.last_sim_time = timing.sim_time(&app.pacer)
	p.max_raw_dt = max(p.max_raw_dt, app.clock.raw_dt)

	if p.pause_from != 0 {
		if app.clock.frame_index == p.pause_from {
			p.sim_at_pause_start = timing.sim_time(&app.pacer)
			p.elapsed_at_pause_start = app.clock.elapsed
		}
		if app.clock.frame_index == p.pause_until + 1 {
			p.sim_at_pause_end = timing.sim_time(&app.pacer)
			p.elapsed_at_pause_end = app.clock.elapsed
		}
		app.paused =
			app.clock.frame_index >= p.pause_from && app.clock.frame_index <= p.pause_until
	}

	if p.unlimited_until != 0 {
		app.cfg.unlimited = app.clock.frame_index <= p.unlimited_until
		// Frame N+1 is the first whose delta reflects a paced wait, because the switch happens
		// inside frame N's callback and is acted on at the END of frame N.
		if app.clock.frame_index > p.unlimited_until + 1 {
			p.max_dt_after_pacing = max(p.max_dt_after_pacing, app.clock.raw_dt)
		}
	}

	if p.sleep_per_frame > 0 {
		time.sleep(p.sleep_per_frame)
	}
	if p.hitch_on_frame != 0 && app.clock.frame_index == p.hitch_on_frame {
		time.sleep(p.hitch_for)
	}
	if app.clock.frame_index >= p.stop_after {
		platform.set_should_close(app.window, true)
	}
}

probe_step :: proc(app: ^game.App, user: rawptr, dt: f32) {
	p := cast(^Probe)user
	if !p.seen_frame || p.seen_render {
		p.ordering_faults += 1 // a step outside its frame's [frame … render) window
	}
	p.step_calls += 1
	p.steps_this_frame += 1
	p.step_dt_min = min(p.step_dt_min, dt)
	p.step_dt_max = max(p.step_dt_max, dt)

	if p.hitch_on_frame != 0 && app.clock.frame_index == p.hitch_on_frame + 1 {
		p.steps_after_hitch += 1
	}
	if p.pause_from != 0 {
		if app.clock.frame_index >= p.pause_from && app.clock.frame_index <= p.pause_until {
			p.steps_during_pause += 1
		}
		if app.clock.frame_index == p.pause_until + 1 {
			p.steps_on_resume_frame += 1
		}
	}
}

probe_render :: proc(app: ^game.App, user: rawptr, alpha: f32) {
	p := cast(^Probe)user
	if !p.seen_frame || p.seen_render {
		p.ordering_faults += 1 // no per-frame callback yet, or a second render in one frame
	}
	if app.steps.count != p.steps_this_frame {
		p.count_mismatches += 1 // the reported count must equal the callbacks actually made
	}
	if app.paused {
		// A paused frame runs no steps, so the frame's REPORT must say so. If `App.steps` is only
		// assigned on unpaused frames it keeps the last unpaused frame's count, and every readout
		// built from it lies for the duration of the pause.
		p.reported_steps_while_paused += app.steps.count
	}
	if alpha < 0 || alpha >= 1 {
		p.ordering_faults += 1
	}
	p.render_calls += 1
	p.seen_render = true
}

probe_shutdown :: proc(app: ^game.App, user: rawptr) {
	p := cast(^Probe)user
	p.shutdown_calls += 1
}

probe_callbacks :: proc(p: ^Probe) -> game.App_Callbacks {
	return {
		user = p,
		init = probe_init,
		frame = probe_frame,
		step = probe_step,
		render = probe_render,
		shutdown = probe_shutdown,
	}
}

hidden :: proc(cfg: game.App_Config) -> game.App_Config {
	out := cfg
	out.initial_window.hidden = true
	out.initial_window.title = "odyne-loop-test"
	return out
}

// ── the cases ──────────────────────────────────────────────────────────────────────────────

test_exits_on_close_request :: proc(t: ^testing.T) {
	probe := Probe {
		stop_after = 8,
	}
	err := game.run(hidden({unlimited = true}), probe_callbacks(&probe))

	testing.expect_value(t, err, game.App_Error.None)
	testing.expect_value(t, probe.init_calls, 1)
	testing.expect_value(t, probe.shutdown_calls, 1)
	testing.expectf(
		t,
		probe.frame_calls == 8,
		"expected 8 per-frame callbacks before the close took effect, got %d",
		probe.frame_calls,
	)
	testing.expect_value(t, probe.render_calls, probe.frame_calls)
	testing.expectf(
		t,
		probe.last_frame_index == 8,
		"frame_index must count from 1 and reach 8, got %d",
		probe.last_frame_index,
	)
	testing.expect(t, probe.last_elapsed > 0, "real elapsed time must advance across frames")
}

test_callback_ordering :: proc(t: ^testing.T) {
	// 1 ms step plus 3 ms of work per frame, so most frames owe several steps and the ordering
	// under test is actually exercised rather than skipped.
	probe := Probe {
		stop_after      = 12,
		sleep_per_frame = 3 * time.Millisecond,
	}
	err := game.run(
		hidden({fixed_dt = time.Millisecond, unlimited = true}),
		probe_callbacks(&probe),
	)

	testing.expect_value(t, err, game.App_Error.None)
	testing.expectf(t, probe.ordering_faults == 0, "%d ordering faults", probe.ordering_faults)
	testing.expectf(
		t,
		probe.count_mismatches == 0,
		"%d frames where app.steps.count disagreed with the step callbacks made",
		probe.count_mismatches,
	)
	testing.expect_value(t, probe.frame_calls, 12)
	testing.expect_value(t, probe.render_calls, 12)
	testing.expect(t, probe.step_calls > 0, "a 1 ms step with 3 ms frames must take steps")
	testing.expectf(
		t,
		probe.max_steps_in_a_frame >= 2,
		"expected at least one multi-step frame, max was %d",
		probe.max_steps_in_a_frame,
	)
}

test_step_dt_is_always_the_fixed_step :: proc(t: ^testing.T) {
	// Two runs, one configuration difference. The measured frame delta must never reach the
	// simulation: what varies with frame time is the NUMBER of calls, never the delta passed.
	fast := Probe {
		stop_after      = 10,
		sleep_per_frame = 4 * time.Millisecond,
	}
	testing.expect_value(
		t,
		game.run(hidden({fixed_dt = time.Millisecond, unlimited = true}), probe_callbacks(&fast)),
		game.App_Error.None,
	)
	testing.expect(t, fast.step_calls > 0, "1 ms step with 4 ms frames must take steps")
	testing.expectf(
		t,
		fast.step_dt_min == fast.step_dt_max,
		"step dt varied: %v .. %v",
		fast.step_dt_min,
		fast.step_dt_max,
	)
	want := f32(0.001)
	delta := fast.step_dt_min - want
	if delta < 0 {delta = -delta}
	testing.expectf(t, delta <= 1e-9, "step dt %v, want %v", fast.step_dt_min, want)

	// A 50 ms step: no frame of a hidden, unlimited loop is 50 ms long, so every frame here owes
	// zero steps — the case that any "at least one step per frame" assumption breaks on.
	//
	// It was a 1-second step until the loop's `max_dt >= fixed_dt` assertion caught it: with
	// max_dt defaulting to 100 ms, a 1 s step is exactly the degenerate configuration that
	// assertion exists to reject, and the test was asking for it. 50 ms stays inside the default
	// clamp and still guarantees zero-step frames.
	slow := Probe {
		stop_after = 10,
	}
	testing.expect_value(
		t,
		game.run(
			hidden({fixed_dt = 50 * time.Millisecond, unlimited = true}),
			probe_callbacks(&slow),
		),
		game.App_Error.None,
	)
	testing.expect_value(t, slow.step_calls, 0)
	testing.expect_value(t, slow.render_calls, 10)
	testing.expectf(
		t,
		slow.frames_with_zero_steps >= 9,
		"expected ~every frame to take zero steps, got %d of 10",
		slow.frames_with_zero_steps,
	)
}

test_hitch_is_absorbed :: proc(t: ^testing.T) {
	// A 2 s stall inside frame 3. The frame after it measures ~2 s, which the clock clamps to one
	// step's worth — so the simulation advances by one step, not by a hundred, and the loop keeps
	// running. The unclamped delta must still be observable: a hitch you cannot see is a hitch you
	// cannot profile.
	probe := Probe {
		stop_after     = 10,
		hitch_on_frame = 3,
		hitch_for      = 2 * time.Second,
	}
	err := game.run(hidden({unlimited = true}), probe_callbacks(&probe))

	testing.expect_value(t, err, game.App_Error.None)
	testing.expect_value(t, probe.frame_calls, 10)
	// Exactly one, not "at most one": clamp_dt defaults to fixed_dt, so a hitch is worth precisely
	// one simulation step. `<= 1` would also be satisfied by ZERO, which is what you get if
	// clamp_dt resolves to 0 — the clock then reports dt == 0 for the hitch and the simulation
	// stands still instead of advancing one step. Same bug class, opposite direction, and a
	// tolerance-shaped assertion would hide it.
	testing.expectf(
		t,
		probe.steps_after_hitch == 1,
		"the frame after a 2 s hitch took %d steps, want exactly 1 (clamp_dt == fixed_dt)",
		probe.steps_after_hitch,
	)
	testing.expectf(
		t,
		probe.max_steps_in_a_frame <= 5,
		"no frame may exceed the documented catch-up bound of 5 steps, saw %d",
		probe.max_steps_in_a_frame,
	)
	testing.expect(
		t,
		probe.max_raw_dt >= time.Second,
		"the pre-clamp delta must stay observable through App.raw_dt",
	)
	testing.expectf(
		t,
		probe.last_sim_time <= 200 * time.Millisecond,
		"2 s of stall must not become 2 s of simulation; sim_time reached %v",
		probe.last_sim_time,
	)
}

test_pause_freezes_sim_not_real :: proc(t: ^testing.T) {
	// 1 ms step, 3 ms of work per frame: unpaused, every frame owes ~3 steps. Paused, it owes
	// none — while frames, real time, pumping and rendering all continue.
	probe := Probe {
		stop_after      = 20,
		pause_from      = 5,
		pause_until     = 14,
		sleep_per_frame = 3 * time.Millisecond,
	}
	err := game.run(
		hidden({fixed_dt = time.Millisecond, unlimited = true}),
		probe_callbacks(&probe),
	)

	testing.expect_value(t, err, game.App_Error.None)
	testing.expect_value(t, probe.frame_calls, 20)
	testing.expect_value(t, probe.render_calls, 20)
	testing.expectf(
		t,
		probe.sim_at_pause_end == probe.sim_at_pause_start,
		"simulated time moved during the pause: %v -> %v",
		probe.sim_at_pause_start,
		probe.sim_at_pause_end,
	)
	testing.expect(
		t,
		probe.elapsed_at_pause_end - probe.elapsed_at_pause_start >= 25 * time.Millisecond,
		"real time must keep advancing while the simulation is paused",
	)
	testing.expectf(
		t,
		probe.steps_during_pause == 0,
		"%d simulation steps ran while paused; none may",
		probe.steps_during_pause,
	)
	testing.expectf(
		t,
		probe.reported_steps_while_paused == 0,
		"App.steps.count reported %d steps across the paused frames; a paused frame's report must read 0",
		probe.reported_steps_while_paused,
	)

	// The resume frame is allowed its OWN duration - a 3 ms frame at a 1 ms step legitimately owes
	// 3 steps, so "zero" would be wrong. What it may not do is credit the whole paused interval:
	// 10 paused frames x 3 ms is ~30 ms, so a replay shows up as ~30 steps here, against ~3 for a
	// normal frame. The bound below sits far from both numbers on purpose.
	//
	// This is also the reason the pause has to be short in real time: pause for 30 s instead and a
	// replayed delta exceeds max_dt, so the clamp turns it into a single step and hides the bug.
	// The failure only shows up for pauses UNDER the clamp threshold.
	testing.expectf(
		t,
		probe.steps_on_resume_frame <= 8,
		"the resume frame took %d steps; a paused interval of ~30 ms must not be replayed (a normal frame owes ~3)",
		probe.steps_on_resume_frame,
	)
	testing.expect(t, probe.last_sim_time > 0, "the simulation must have run before the pause")
}

test_limiter_is_never_faster_than_target :: proc(t: ^testing.T) {
	// The limiter's hard guarantee is one-sided: a frame may end late, never early. 12 frames at
	// 60 fps is ~183 ms of real waiting, so this case is deliberately the slow one.
	FRAMES :: 12
	TARGET :: 60
	period := time.Second / TARGET

	// Measured on the LOOP's own clock (`elapsed` at the last frame), not with a stopwatch around
	// `run` — that would fold ~100 ms of SDL init and window creation into both numbers and make
	// the comparison below mostly a measurement of startup.
	paced := Probe {
		stop_after = FRAMES,
	}
	err := game.run(hidden({target_fps = TARGET}), probe_callbacks(&paced))

	testing.expect_value(t, err, game.App_Error.None)
	testing.expect_value(t, paced.frame_calls, FRAMES)
	testing.expectf(
		t,
		paced.last_elapsed >= (FRAMES - 1) * period,
		"%d frames at %d fps reached only %v of elapsed time; the limiter should have held it to at least %v",
		FRAMES,
		TARGET,
		paced.last_elapsed,
		(FRAMES - 1) * period,
	)

	// And with the limiter off, the same frame count must be dramatically cheaper — otherwise the
	// "paced" run above proves nothing about the limiter and everything about a slow machine.
	free_running := Probe {
		stop_after = FRAMES,
	}
	testing.expect_value(
		t,
		game.run(hidden({unlimited = true}), probe_callbacks(&free_running)),
		game.App_Error.None,
	)

	testing.expectf(
		t,
		free_running.last_elapsed < paced.last_elapsed / 2,
		"unlimited run reached %v vs paced %v - pacing is not doing anything",
		free_running.last_elapsed,
		paced.last_elapsed,
	)
}

test_optional_callbacks_are_safe :: proc(t: ^testing.T) {
	// Only the per-frame callback is supplied — and only because something has to request close;
	// nothing else may be required. A loop that dereferences a missing callback crashes here.
	probe := Probe {
		stop_after = 4,
	}
	err := game.run(hidden({unlimited = true}), {user = &probe, frame = probe_frame})

	testing.expect_value(t, err, game.App_Error.None)
	testing.expect_value(t, probe.frame_calls, 4)
	testing.expect_value(t, probe.step_calls, 0)
	testing.expect_value(t, probe.render_calls, 0)
	testing.expect_value(t, probe.init_calls, 0)
	testing.expect_value(t, probe.shutdown_calls, 0)
}

test_limiter_can_be_re_enabled_mid_run :: proc(t: ^testing.T) {
	// Turning pacing OFF and back ON must not stall the app.
	//
	// The hazard is an origin-anchored deadline grid:
	// `origin + (frame_index + 1) * period`, which is only meaningful while every frame has
	// actually been paced to that period. Unpaced frames still increment frame_index without
	// consuming their grid slot, so after a burst of free-running frames the grid sits far in the
	// FUTURE - and the first paced frame afterwards waits for the whole accumulated difference.
	// A few seconds unpaced is minutes of deadline.
	//
	// The mirror-image case is a live `target_fps` change: the grid respaces every PAST frame
	// retroactively, so raising the rate puts the deadline far in the past and pacing stops until
	// real time catches up.
	FRAMES :: 30
	UNPACED :: 20
	TARGET :: 60
	period := time.Second / TARGET

	probe := Probe {
		stop_after      = FRAMES,
		unlimited_until = UNPACED,
	}
	err := game.run(hidden({target_fps = TARGET}), probe_callbacks(&probe))

	testing.expect_value(t, err, game.App_Error.None)
	testing.expect_value(t, probe.frame_calls, FRAMES)
	testing.expectf(
		t,
		probe.max_dt_after_pacing <= 5 * period,
		"after re-enabling the limiter a frame took %v; the target period is %v, so pacing must resume within a few periods, not stall",
		probe.max_dt_after_pacing,
		period,
	)
}

probe_init_fails :: proc(app: ^game.App, user: rawptr) -> bool {
	p := cast(^Probe)user
	p.init_calls += 1
	return false
}

test_init_failure_aborts_the_loop :: proc(t: ^testing.T) {
	// Pins two decisions that were made deliberately and had nothing holding them in place.
	//
	// First, an application init that reports failure is distinguishable from a platform or window
	// failure, so the caller can tell whose fault it was.
	//
	// Second, `shutdown` pairs with a SUCCESSFUL init and therefore does NOT run here: an init that
	// returns false owns whatever it half-built, the same reasoning as a constructor that throws.
	// Nothing enforced that before this test, so moving the `defer` above the init check would have
	// silently changed the contract.
	//
	// This one is GREEN on arrival rather than red - it documents existing agreed behaviour instead
	// of driving new work.
	probe := Probe {
		stop_after = 5,
	}
	cb := probe_callbacks(&probe)
	cb.init = probe_init_fails

	err := game.run(hidden({unlimited = true}), cb)

	testing.expect_value(t, err, game.App_Error.Init_Callback_Failed)
	testing.expect_value(t, probe.init_calls, 1)
	testing.expect_value(t, probe.frame_calls, 0)
	testing.expect_value(t, probe.step_calls, 0)
	testing.expect_value(t, probe.render_calls, 0)
	testing.expect_value(t, probe.shutdown_calls, 0)
}
