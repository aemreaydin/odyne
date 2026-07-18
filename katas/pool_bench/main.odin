package main

// Tutor-run measurement for lesson m02-03. Compares the learner's pool against the
// default heap: ns per alloc, ns per free, and an alloc→free churn cycle — the workload
// the arena literally could not run (it had no per-object free).
//
// Run:  odin run katas/pool_bench -o:speed

import "core:fmt"
import "core:mem"
import "core:time"
import pool "../pool"

main :: proc() {
	N :: 100_000
	SZ :: 32 // block size / request size
	ALIGN :: 8

	backing := make([]byte, (N + 16) * SZ)
	defer delete(backing)
	p: pool.Pool
	pool.init(&p, backing, SZ, ALIGN)
	pa := pool.allocator(&p)

	checksum: uintptr

	// ── (1) alloc→free churn: 1 block live at a time, N cycles ───────────────
	churn_start := time.tick_now()
	for _ in 0 ..< N {
		b, _ := mem.alloc_bytes(SZ, ALIGN, pa)
		checksum += uintptr(raw_data(b))
		mem.free_bytes(b, pa)
	}
	pool_churn_ns := f64(time.duration_nanoseconds(time.tick_since(churn_start))) / f64(N)

	// ── (2) fill (N allocs) then drain (N frees) — clean per-op numbers ───────
	pool.free_all(&p)
	ptrs := make([][]byte, N)
	defer delete(ptrs)

	fill_start := time.tick_now()
	for i in 0 ..< N {
		b, _ := mem.alloc_bytes(SZ, ALIGN, pa)
		ptrs[i] = b
	}
	pool_alloc_ns := f64(time.duration_nanoseconds(time.tick_since(fill_start))) / f64(N)

	drain_start := time.tick_now()
	for i in 0 ..< N {
		mem.free_bytes(ptrs[i], pa)
	}
	pool_free_ns := f64(time.duration_nanoseconds(time.tick_since(drain_start))) / f64(N)

	// ── (3) heap new/free churn of the same size ─────────────────────────────
	heap_start := time.tick_now()
	for _ in 0 ..< N {
		b, _ := mem.alloc_bytes(SZ, ALIGN) // default heap allocator
		checksum += uintptr(raw_data(b))
		mem.free_bytes(b)
	}
	heap_churn_ns := f64(time.duration_nanoseconds(time.tick_since(heap_start))) / f64(N)

	fmt.printfln("N=%d  block=%dB  align=%d  (checksum=%d)", N, SZ, ALIGN, checksum)
	fmt.printfln("pool alloc      : %.2f ns/op", pool_alloc_ns)
	fmt.printfln("pool free       : %.2f ns/op", pool_free_ns)
	fmt.printfln("pool alloc+free : %.2f ns/cycle", pool_churn_ns)
	fmt.printfln("heap alloc+free : %.2f ns/cycle", heap_churn_ns)
	fmt.printfln("churn speedup (heap/pool): %.1fx", heap_churn_ns / pool_churn_ns)
}
