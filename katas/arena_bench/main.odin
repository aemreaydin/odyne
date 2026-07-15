package main

// Tutor-run measurement for lesson m02-02. Compares the learner's arena against the
// default heap allocator: ns/alloc for a fixed count of small allocations, and the
// cost of reclaiming them (arena free_all vs freeing each heap block individually).
//
// Run:  odin run katas/arena_bench -o:speed

import "core:fmt"
import "core:mem"
import "core:time"
import arena "../arena"

main :: proc() {
	N :: 100_000
	SZ :: 32
	ALIGN :: 8

	// ── arena: one big backing, N bump allocations ──────────────────────────
	backing := make([]byte, N * 64)
	defer delete(backing)
	ar: arena.Arena
	arena.init(&ar, backing)
	a_alloc := arena.allocator(&ar)

	checksum: uintptr
	arena_start := time.tick_now()
	for _ in 0 ..< N {
		b, _ := mem.alloc_bytes(SZ, ALIGN, a_alloc)
		checksum += uintptr(raw_data(b)) // keep the loop from being optimized away
	}
	arena_alloc_ns := f64(time.duration_nanoseconds(time.tick_since(arena_start))) / f64(N)

	freeall_start := time.tick_now()
	arena.free_all(&ar)
	arena_freeall_ns := f64(time.duration_nanoseconds(time.tick_since(freeall_start)))

	// ── heap: N allocations through the default allocator, freed individually ─
	ptrs := make([][]byte, N)
	defer delete(ptrs)

	heap_start := time.tick_now()
	for i in 0 ..< N {
		b, _ := mem.alloc_bytes(SZ, ALIGN) // context.allocator = default heap
		ptrs[i] = b
	}
	heap_alloc_ns := f64(time.duration_nanoseconds(time.tick_since(heap_start))) / f64(N)

	heapfree_start := time.tick_now()
	for i in 0 ..< N {
		mem.free_bytes(ptrs[i])
	}
	heap_free_ns := f64(time.duration_nanoseconds(time.tick_since(heapfree_start)))

	fmt.printfln("N=%d  size=%dB  align=%d  (checksum=%d)", N, SZ, ALIGN, checksum)
	fmt.printfln("arena alloc : %.2f ns/alloc", arena_alloc_ns)
	fmt.printfln("heap  alloc : %.2f ns/alloc", heap_alloc_ns)
	fmt.printfln("alloc speedup (heap/arena): %.1fx", heap_alloc_ns / arena_alloc_ns)
	fmt.printfln("arena free_all (all %d)   : %.0f ns total  (%.4f ns/obj)", N, arena_freeall_ns, arena_freeall_ns / f64(N))
	fmt.printfln("heap  free (%d individual): %.0f ns total  (%.2f ns/obj)", N, heap_free_ns, heap_free_ns / f64(N))
}
