package testbed

import "core:fmt"
import "core:mem"
import "core:time"
import "engine:core/containers/handle_pool"
import "engine:core/memory"
import "engine:core/timing"
import "engine:game"
import "engine:platform"

main :: proc() {
	fmt.println(game.boot())
	{
		arena: memory.Arena
		arena_backing: [128]byte
		memory.arena_init(&arena, arena_backing[:])
		arena_allocator := memory.arena_allocator(&arena)
		tracking_allocator: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking_allocator, arena_allocator)
		context.allocator = mem.tracking_allocator(&tracking_allocator)
		defer {
			for _, e in tracking_allocator.allocation_map {
				fmt.printfln("leak: %d bytes @ %v  (%v)", e.size, e.memory, e.location)
			}
			for b in tracking_allocator.bad_free_array {
				fmt.printfln("bad free @ %v  (%v)", b.memory, b.location)
			}
			mem.tracking_allocator_destroy(&tracking_allocator)
		}

		bytes := make([]byte, 32)
		for i in 0 ..< len(bytes) {bytes[i] = 0xBB}
		fmt.println("Bytes: ", bytes)
		free_all(context.allocator)
		fmt.println("Bytes: ", bytes)
	}

	{
		logging_allocator: memory.Logging_Allocator
		pool: memory.Pool
		pool_backing: [128]byte
		memory.pool_init(&pool, pool_backing[:], 32, 8)
		pool_allocator := memory.pool_allocator(&pool)
		memory.logging_allocator_init(&logging_allocator, pool_allocator, "pool")
		context.allocator = memory.logging_allocator(&logging_allocator)
		bytes := make([]byte, 32)
		for i in 0 ..< len(bytes) {bytes[i] = 0xAA}
		bytes = make([]byte, 32)
		for i in 0 ..< len(bytes) {bytes[i] = 0xCC}
		free(raw_data(bytes))
	}

	Texture :: struct {
		handle: TextureHandle,
		path:   string,
	}
	TextureHandle :: distinct handle_pool.Handle

	tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, context.allocator)
	context.allocator = mem.tracking_allocator(&tracking_allocator)
	defer {
		for _, e in tracking_allocator.allocation_map {
			fmt.printfln("leak: %d bytes @ %v  (%v)", e.size, e.memory, e.location)
		}
		for b in tracking_allocator.bad_free_array {
			fmt.printfln("bad free @ %v  (%v)", b.memory, b.location)
		}
		mem.tracking_allocator_destroy(&tracking_allocator)
	}

	hp: handle_pool.Handle_Pool(Texture, TextureHandle)
	handle_pool.init(&hp, 10)
	defer handle_pool.destroy(&hp)

	ha, ha_err := handle_pool.add(&hp, Texture{path = "path/a"})
	hb, _ := handle_pool.add(&hp, Texture{path = "path/b"})

	a, _ := handle_pool.get(&hp, ha)
	fmt.println(a.path)
	b, _ := handle_pool.get(&hp, hb)
	fmt.println(b.path)
	b_ptr, _ := handle_pool.get_ptr(&hp, hb)
	b_ptr.path = "path/b_ptr"
	fmt.println(b_ptr.path)

	for &item in handle_pool.slice(&hp) {
		fmt.println(item.path)
	}

	_ = handle_pool.remove(&hp, ha)
	a, ha_err = handle_pool.get(&hp, ha)
	fmt.println(ha_err)

	handle_pool.clear(&hp)

	g := Game{}
	cfg := game.App_Config {
		initial_window = {title = "Testbed"},
		target_fps = 60,
	}
	cb := game.App_Callbacks {
		user     = rawptr(&g),
		init     = game_init,
		frame    = game_frame,
		step     = game_step,
		render   = game_render,
		shutdown = game_shutdown,
	}

	game.run(cfg, cb)
}

Game :: struct {
	x:    f32,
	prev: f32,
}

game_init :: proc(app: ^game.App, user: rawptr) -> bool {
	return true
}

game_frame :: proc(app: ^game.App, user: rawptr) {
	if platform.key_pressed(app.window, .Escape) {
		platform.set_should_close(app.window, true)
	}

	if platform.key_pressed(app.window, .P) {
		app.paused = !app.paused
	}

	if platform.key_down(app.window, .H) {
		time.sleep(2 * time.Second)
	}

	if platform.key_pressed(app.window, .L) {
		app.cfg.unlimited = !app.cfg.unlimited
	}

	// fps comes from the SMOOTHED average, never from this frame's dt: a per-frame reciprocal
	// jitters far too much to read. The measured dt is for the simulation, the average is for the
	// human -- the split m11-01 settled. Guarded because an empty history reports 0.
	avg := timing.history_average(&app.clock.history)
	fps := avg > 0 ? 1.0 / time.duration_seconds(avg) : 0

	// P and L are otherwise invisible: pausing looks like a stopped sim clock, and toggling the
	// limiter only shows up as a change in fps. Say so out loud instead.
	state := ""
	if app.paused {state = " [PAUSED]"}
	if app.cfg.unlimited {state = fmt.tprintf("%s [UNCAPPED]", state)}

	// sim vs real in seconds, two decimals: the pair is here to be WATCHED DIVERGING under a hitch
	// or a pause, and a divergence of tens of milliseconds is invisible at lower precision.
	title := fmt.tprintf(
		"f %d | %.1f fps | frame avg %v (min %v max %v) | steps %d | a %.3f | sim %.2fs real %.2fs%s",
		app.clock.frame_index,
		fps,
		avg,
		timing.history_min(&app.clock.history),
		timing.history_max(&app.clock.history),
		app.steps.count,
		app.steps.alpha,
		time.duration_seconds(timing.sim_time(&app.pacer)),
		time.duration_seconds(app.clock.elapsed),
		state,
	)
	platform.set_window_title(app.window, title)
}

game_step :: proc(app: ^game.App, user: rawptr, dt: f32) {
	g := cast(^Game)(user)
	g.prev = g.x
	g.x += 10 * dt
}

game_render :: proc(app: ^game.App, user: rawptr, alpha: f32) {
}

game_shutdown :: proc(app: ^game.App, user: rawptr) {
}
