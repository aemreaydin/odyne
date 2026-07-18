package testbed

import "core:fmt"
import "core:mem"
import "engine:core/memory"
import "engine:game"

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
}
