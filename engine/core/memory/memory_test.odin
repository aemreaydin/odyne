#+private
package memory

// m02-04 graduate — conformance tests for the core-memory capability. These trace to the
// openspec core-memory spec scenarios (arena, pool, allocator-interface conformance) rather
// than re-testing every kata edge — the exhaustive suites lived in the katas. They compile
// against the RED stub and fail until you port the arena/pool bodies (task 4.1).
//
// Run:  odin test engine/core/memory -collection:engine=engine

import "core:mem"
import "core:testing"

@(private = "file")
addr :: proc(p: rawptr) -> uintptr {return uintptr(p)}

// ── Arena: allocation advances + zeroes; bulk reset; exhaustion ──────────────

@(test)
test_arena_alloc_zeroes :: proc(t: ^testing.T) {
	backing: [128]byte
	for i in 0 ..< len(backing) {backing[i] = 0xAA}
	a: Arena
	arena_init(&a, backing[:])
	b, err := arena_allocator_proc(&a, .Alloc, 32, 8, nil, 0)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(b), 32)
	for v in b {testing.expect_value(t, v, u8(0))}
}

@(test)
test_arena_free_all_reclaims :: proc(t: ^testing.T) {
	backing: [128]byte
	a: Arena
	arena_init(&a, backing[:])
	b1, _ := arena_allocator_proc(&a, .Alloc, 64, 8, nil, 0)
	testing.expect_value(t, len(b1), 64)
	arena_free_all(&a)
	testing.expect_value(t, a.offset, 0)
	b2, _ := arena_allocator_proc(&a, .Alloc, 64, 8, nil, 0)
	if len(b1) == 64 && len(b2) == 64 {
		testing.expect(t, addr(raw_data(b2)) == addr(raw_data(b1)), "reset reuses the region")
	}
}

@(test)
test_arena_out_of_memory :: proc(t: ^testing.T) {
	backing: [64]byte
	a: Arena
	arena_init(&a, backing[:])
	b, err := arena_allocator_proc(&a, .Alloc, 128, 8, nil, 0)
	testing.expect_value(t, err, mem.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, len(b), 0)
}

// ── Pool: alloc/free/reuse; exhaustion vs oversize; bulk reset ───────────────

@(test)
test_pool_alloc_free_reuse :: proc(t: ^testing.T) {
	backing: [256]byte
	p: Pool
	pool_init(&p, backing[:], 32, 8)
	b1, _ := pool_allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	testing.expect_value(t, len(b1), 16)
	_, ferr := pool_allocator_proc(&p, .Free, 0, 8, raw_data(b1), 16)
	testing.expect_value(t, ferr, mem.Allocator_Error.None)
	b2, _ := pool_allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	if len(b1) == 16 && len(b2) == 16 {
		testing.expect(t, addr(raw_data(b2)) == addr(raw_data(b1)), "freed block is reused")
	}
}

@(test)
test_pool_exhaustion_ooms :: proc(t: ^testing.T) {
	backing: [64]byte
	p: Pool
	pool_init(&p, backing[:], 32, 8) // 2 blocks
	_, _ = pool_allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	_, _ = pool_allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	b, err := pool_allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	testing.expect_value(t, err, mem.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, len(b), 0)
}

@(test)
test_pool_oversize_invalid_argument :: proc(t: ^testing.T) {
	backing: [256]byte
	p: Pool
	pool_init(&p, backing[:], 32, 8)
	b, err := pool_allocator_proc(&p, .Alloc, 64, 8, nil, 0) // > block_size
	testing.expect_value(t, err, mem.Allocator_Error.Invalid_Argument)
	testing.expect_value(t, len(b), 0)
}

@(test)
test_pool_free_all_returns_all :: proc(t: ^testing.T) {
	backing: [64]byte
	p: Pool
	pool_init(&p, backing[:], 32, 8) // 2 blocks
	_, _ = pool_allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	_, _ = pool_allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	pool_free_all(&p)
	testing.expect_value(t, p.free_count, 2)
}

// ── Allocator interface conformance: new/make route through a core allocator ──

@(test)
test_arena_context_allocator :: proc(t: ^testing.T) {
	backing: [1024]byte
	a: Arena
	arena_init(&a, backing[:])
	context.allocator = arena_allocator(&a)
	p1, _ := new(int)
	testing.expect(t, p1 != nil, "new routed through the core arena")
	if p1 != nil {
		p1^ = 7
		testing.expect_value(t, p1^, 7)
	}
	s, _ := make([]int, 8)
	testing.expect_value(t, len(s), 8)
	lo := addr(raw_data(backing[:]))
	hi := lo + uintptr(len(backing))
	if p1 != nil {
		testing.expect(t, addr(p1) >= lo && addr(p1) < hi, "allocation came from the backing")
	}
}

// ── Logging allocator: transparent wrapper that forwards faithfully ──────────

@(test)
test_logging_allocator_forwards :: proc(t: ^testing.T) {
	backing: [256]byte
	a: Arena
	arena_init(&a, backing[:])
	log: Logging_Allocator
	logging_allocator_init(&log, arena_allocator(&a), "test")
	b, err := mem.alloc_bytes(32, 8, logging_allocator(&log))
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(b), 32)
	// the wrapped allocation really came from the backing arena, and advanced its state
	lo := addr(raw_data(backing[:]))
	hi := lo + uintptr(len(backing))
	if len(b) == 32 {
		testing.expect(
			t,
			addr(raw_data(b)) >= lo && addr(raw_data(b)) < hi,
			"logger forwards to the backing",
		)
	}
	testing.expect(t, a.offset >= 32, "backing arena saw the allocation")
}

@(test)
test_pool_context_allocator :: proc(t: ^testing.T) {
	backing: [256]byte
	p: Pool
	pool_init(&p, backing[:], 32, 8)
	context.allocator = pool_allocator(&p)
	a, _ := new(int) // 8 <= block_size 32
	testing.expect(t, a != nil, "new routed through the core pool")
	b, _ := new(int)
	if a != nil && b != nil {
		testing.expect(t, a != b, "distinct objects get distinct blocks")
	}
}
