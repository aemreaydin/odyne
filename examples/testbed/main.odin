package testbed

import "core:fmt"
import "core:mem"
import "engine:core/containers/handle_pool"
import "engine:core/memory"
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


	platform.init()
	wnd_handle, err := platform.create_window({hidden = false, title = "odyne"})
	defer platform.shutdown()
	if err != .None {
		return
	}

	last_key: platform.Key
	for !platform.should_close(wnd_handle) {
		platform.poll_events()

		if platform.key_down(wnd_handle, .Escape) {
			platform.set_should_close(wnd_handle, true)
		}

		buttons_string := ""
		for button in platform.Mouse_Button {
			if platform.mouse_down(wnd_handle, button) {
				buttons_string = fmt.tprintf("%s %v", buttons_string, button)
			}
		}

		for key in platform.Key {
			if platform.key_pressed(wnd_handle, key) {
				last_key = key
				break
			}
		}

		mouse_pos := platform.mouse_position(wnd_handle)
		title := fmt.tprintf(
			"Pos: (%d, %d) - Buttons: %s - Last_key: %v",
			mouse_pos.x,
			mouse_pos.y,
			buttons_string,
			last_key,
		)
		platform.set_window_title(wnd_handle, title)
		free_all(context.temp_allocator)
	}
}

