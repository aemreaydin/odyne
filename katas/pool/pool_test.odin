package pool

// Failing tests for the m02-03 pool kata. They compile against the stubs in pool.odin
// and FAIL (the stubs return benign zero values). Implement the bodies until every test
// passes and the per-test leak check reports 0 leaks.
//
// Run:  odin test katas/pool
//
// Tests drive the Allocator_Proc contract directly plus one context.allocator integration
// test. Backing buffers are stack arrays, so nothing here touches the heap. Each test
// asserts a size/count the empty stub can't satisfy (so all start RED), and indexed reads
// are length-guarded so the RED run fails cleanly instead of indexing an empty slice.

import "core:mem"
import "core:testing"

@(private = "file")
addr :: proc(p: rawptr) -> uintptr {return uintptr(p)}

// ── init: carve + thread the free list ───────────────────────────────────────

@(test)
test_init_threads_free_list :: proc(t: ^testing.T) {
	backing: [256]byte
	p: Pool
	init(&p, backing[:], 32, 8) // stride 32 → 8 blocks
	testing.expect_value(t, p.block_size, 32)
	testing.expect_value(t, p.free_count, 8)
	testing.expect(
		t,
		addr(raw_data(p.data)) == addr(raw_data(backing[:])),
		"pool borrows the caller's buffer",
	)
}

@(test)
test_init_bumps_block_size_to_hold_link :: proc(t: ^testing.T) {
	// A 4-byte requested block can't hold an 8-byte free-list link: stride must be
	// bumped to >= size_of(rawptr) and kept a multiple of the alignment.
	backing: [256]byte
	p: Pool
	init(&p, backing[:], 4, 8)
	testing.expect(t, p.block_size >= size_of(rawptr), "block must fit the free-list link")
	testing.expect(t, p.block_size % 8 == 0, "stride must stay a multiple of alignment")
}

// ── alloc: size, zeroing, distinctness ───────────────────────────────────────

@(test)
test_alloc_returns_size_bytes :: proc(t: ^testing.T) {
	backing: [256]byte
	p: Pool
	init(&p, backing[:], 32, 8)
	b, err := allocator_proc(&p, .Alloc, 16, 8, nil, 0) // 16 <= block_size 32
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(b), 16) // exactly `size`, not the whole block
	testing.expect_value(t, p.free_count, 7) // one block consumed
}

@(test)
test_alloc_zeroes :: proc(t: ^testing.T) {
	backing: [256]byte
	for i in 0 ..< len(backing) {backing[i] = 0xAA}
	p: Pool
	init(&p, backing[:], 32, 8)
	b, err := allocator_proc(&p, .Alloc, 32, 8, nil, 0)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(b), 32)
	for v in b {testing.expect_value(t, v, u8(0))} 	// .Alloc zeroes the whole block, incl. the old link bytes
}

@(test)
test_alloc_non_zeroed_keeps_bytes :: proc(t: ^testing.T) {
	backing: [256]byte
	for i in 0 ..< len(backing) {backing[i] = 0xAA}
	p: Pool
	init(&p, backing[:], 32, 8)
	b, err := allocator_proc(&p, .Alloc_Non_Zeroed, 32, 8, nil, 0)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(b), 32)
	// init only wrote free-list links into the first size_of(rawptr) bytes of each block;
	// the rest is untouched, so a non-zeroed alloc hands it back as-is (still 0xAA).
	if len(b) == 32 {
		for i in size_of(rawptr) ..< 32 {testing.expect_value(t, b[i], u8(0xAA))}
	}
}

@(test)
test_alloc_distinct_blocks :: proc(t: ^testing.T) {
	backing: [256]byte
	p: Pool
	init(&p, backing[:], 32, 8)
	b1, _ := allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	b2, _ := allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	testing.expect_value(t, len(b1), 16)
	testing.expect_value(t, len(b2), 16)
	if len(b1) == 16 && len(b2) == 16 {
		testing.expect(
			t,
			addr(raw_data(b1)) != addr(raw_data(b2)),
			"two allocations are different blocks",
		)
	}
}

// ── exhaustion vs oversize: two distinct errors ──────────────────────────────

@(test)
test_exhaustion_ooms :: proc(t: ^testing.T) {
	backing: [64]byte
	p: Pool
	init(&p, backing[:], 32, 8) // 2 blocks
	_, _ = allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	_, _ = allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	b3, err := allocator_proc(&p, .Alloc, 16, 8, nil, 0) // pool empty
	testing.expect_value(t, err, mem.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, len(b3), 0)
}

@(test)
test_oversize_is_invalid_argument :: proc(t: ^testing.T) {
	backing: [256]byte
	p: Pool
	init(&p, backing[:], 32, 8)
	b, err := allocator_proc(&p, .Alloc, 64, 8, nil, 0) // 64 > block_size 32
	testing.expect_value(t, err, mem.Allocator_Error.Invalid_Argument)
	testing.expect_value(t, len(b), 0)
}

// ── free: the pool's headline — individual O(1) free + reuse ─────────────────

@(test)
test_free_and_reuse :: proc(t: ^testing.T) {
	backing: [256]byte
	p: Pool
	init(&p, backing[:], 32, 8)
	b1, _ := allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	testing.expect_value(t, len(b1), 16)
	fc := p.free_count
	_, ferr := allocator_proc(&p, .Free, 0, 8, raw_data(b1), 16)
	testing.expect_value(t, ferr, mem.Allocator_Error.None)
	testing.expect_value(t, p.free_count, fc + 1) // free returns a slot
	b2, _ := allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	testing.expect_value(t, len(b2), 16)
	if len(b1) == 16 && len(b2) == 16 {
		testing.expect(
			t,
			addr(raw_data(b2)) == addr(raw_data(b1)),
			"LIFO free reuses the same block",
		)
	}
}

@(test)
test_free_all_rethreads :: proc(t: ^testing.T) {
	backing: [64]byte
	p: Pool
	init(&p, backing[:], 32, 8) // 2 blocks
	_, _ = allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	_, _ = allocator_proc(&p, .Alloc, 16, 8, nil, 0) // exhausted
	free_all(&p)
	testing.expect_value(t, p.free_count, 2) // everything free again
	b, err := allocator_proc(&p, .Alloc, 16, 8, nil, 0)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(b), 16)
}

// ── alignment: blocks aligned even off a misaligned backing ──────────────────

@(test)
test_alignment_on_misaligned_backing :: proc(t: ^testing.T) {
	raw: [256]byte
	base := addr(raw_data(raw[:]))
	k := int((65 - base % 64) % 64) // force the backing base to ≡ 1 (mod 64)
	backing := raw[k:]
	p: Pool
	init(&p, backing, 32, 64) // pool aligned to 64
	b, err := allocator_proc(&p, .Alloc, 32, 8, nil, 0)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(b), 32)
	if len(b) == 32 {
		testing.expect(t, addr(raw_data(b)) % 64 == 0, "blocks must honor the pool's alignment")
	}
}

// ── Query_Features: includes .Free (unlike the arena) ────────────────────────

@(test)
test_query_features :: proc(t: ^testing.T) {
	backing: [64]byte
	p: Pool
	init(&p, backing[:], 32, 8)
	set: mem.Allocator_Mode_Set
	_, err := allocator_proc(&p, .Query_Features, 0, 0, &set, 0)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	expected := mem.Allocator_Mode_Set {
		.Alloc,
		.Alloc_Non_Zeroed,
		.Free,
		.Free_All,
		.Query_Features,
	}
	testing.expect(
		t,
		set == expected,
		"features must list exactly the supported modes (incl .Free)",
	)
}

// ── Integration: the pool plugs into context.allocator ───────────────────────

@(test)
test_context_allocator_integration :: proc(t: ^testing.T) {
	backing: [256]byte
	p: Pool
	init(&p, backing[:], 32, 8)
	context.allocator = allocator(&p)
	p1, _ := new(int) // 8 bytes <= block_size 32
	testing.expect(t, p1 != nil, "new routed through the pool")
	if p1 != nil {
		p1^ = 42
		testing.expect_value(t, p1^, 42)
	}
	p2, _ := new(int)
	testing.expect(t, p2 != nil, "second new")
	if p1 != nil && p2 != nil {
		testing.expect(t, p1 != p2, "distinct objects get distinct blocks")
	}
	// free through the allocator, then re-alloc reuses the block (LIFO)
	if p1 != nil {
		free(p1)
		p3, _ := new(int)
		testing.expect(t, rawptr(p3) == rawptr(p1), "a freed block is recycled")
	}
}
