package arena

// Failing tests for the m02-02 arena kata. They compile against the stubs in
// arena.odin and FAIL (the stubs return benign zero values). Implement the bodies
// until every test passes and the per-test leak check reports 0 leaks.
//
// Run:  odin test katas/arena
//
// Tests drive the Allocator_Proc contract directly (that procedure IS the deliverable)
// plus one context.allocator integration test. Backing buffers are stack arrays, so
// nothing here touches the heap — the leak check stays trivially clean.
//
// Each test asserts a size/offset that the empty stub cannot satisfy, so all start RED;
// writes into returned slices are length-guarded so the RED run fails cleanly instead
// of indexing an empty slice.

import "core:mem"
import "core:testing"

@(private = "file")
addr :: proc(p: rawptr) -> uintptr {return uintptr(p)}

// ── init ───────────────────────────────────────────────────────────────────

@(test)
test_init_is_empty_over_backing :: proc(t: ^testing.T) {
	backing: [128]byte
	a: Arena
	init(&a, backing[:])
	testing.expect_value(t, a.offset, 0)
	testing.expect_value(t, len(a.data), 128)
	testing.expect(
		t,
		addr(raw_data(a.data)) == addr(raw_data(backing[:])),
		"arena borrows the caller's buffer",
	)
}

// ── Alloc: bump, bounds, zeroing ─────────────────────────────────────────────

@(test)
test_alloc_returns_sized_slice :: proc(t: ^testing.T) {
	backing: [128]byte
	a: Arena
	init(&a, backing[:])
	bytes, err := allocator_proc(&a, .Alloc, 32, 8, nil, 0)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(bytes), 32)
	testing.expect(t, a.offset >= 32, "offset advanced past the allocation")
}

@(test)
test_alloc_zeroes :: proc(t: ^testing.T) {
	backing: [128]byte
	for i in 0 ..< len(backing) {backing[i] = 0xAA} 	// dirty the backing
	a: Arena
	init(&a, backing[:])
	bytes, err := allocator_proc(&a, .Alloc, 32, 8, nil, 0)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(bytes), 32)
	for v in bytes {testing.expect_value(t, v, u8(0))} 	// .Alloc must zero
}

@(test)
test_alloc_non_zeroed_does_not_zero :: proc(t: ^testing.T) {
	backing: [128]byte
	for i in 0 ..< len(backing) {backing[i] = 0xAA}
	a: Arena
	init(&a, backing[:])
	bytes, err := allocator_proc(&a, .Alloc_Non_Zeroed, 32, 8, nil, 0)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(bytes), 32)
	for v in bytes {testing.expect_value(t, v, u8(0xAA))} 	// returned as-is, not zeroed
}

@(test)
test_two_allocs_do_not_overlap :: proc(t: ^testing.T) {
	backing: [128]byte
	a: Arena
	init(&a, backing[:])
	b1, _ := allocator_proc(&a, .Alloc, 16, 8, nil, 0)
	b2, _ := allocator_proc(&a, .Alloc, 16, 8, nil, 0)
	testing.expect_value(t, len(b1), 16)
	testing.expect_value(t, len(b2), 16)
	// second block begins at or after the end of the first
	testing.expect(
		t,
		addr(raw_data(b2)) >= addr(raw_data(b1)) + 16,
		"allocations must not overlap",
	)
}

// ── Alignment: the returned address honors `alignment`, even off a misaligned base ──

@(test)
test_alignment_on_misaligned_backing :: proc(t: ^testing.T) {
	raw: [256]byte
	// Slice the backing so its base address is guaranteed NOT 64-aligned (≡ 1 mod 64).
	// A correct arena aligns the absolute address raw_data(data)+offset, not just the
	// offset — so it must skip padding to return a 64-aligned pointer here.
	base := addr(raw_data(raw[:]))
	k := int((65 - base % 64) % 64)
	backing := raw[k:]
	a: Arena
	init(&a, backing)
	bytes, err := allocator_proc(&a, .Alloc, 32, 64, nil, 0)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(bytes), 32)
	testing.expect(t, addr(raw_data(bytes)) % 64 == 0, "returned pointer must be 64-aligned")
}

// ── Out of memory: request larger than the remaining space ───────────────────

@(test)
test_out_of_memory :: proc(t: ^testing.T) {
	backing: [64]byte
	a: Arena
	init(&a, backing[:])
	bytes, err := allocator_proc(&a, .Alloc, 128, 8, nil, 0) // won't fit
	testing.expect_value(t, err, mem.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, len(bytes), 0)
}

// ── Free: an arena can't free one allocation ─────────────────────────────────

@(test)
test_free_is_mode_not_implemented :: proc(t: ^testing.T) {
	backing: [128]byte
	a: Arena
	init(&a, backing[:])
	bytes, _ := allocator_proc(&a, .Alloc, 16, 8, nil, 0)
	testing.expect_value(t, len(bytes), 16) // must-fail-at-RED anchor
	off_before := a.offset
	_, err := allocator_proc(&a, .Free, 0, 8, raw_data(bytes), 16)
	testing.expect_value(t, err, mem.Allocator_Error.Mode_Not_Implemented)
	testing.expect_value(t, a.offset, off_before) // Free reclaims nothing
}

// ── Free_All: bulk reset, then the region is reused and re-zeroed ─────────────

@(test)
test_free_all_resets_and_reuses :: proc(t: ^testing.T) {
	backing: [128]byte
	a: Arena
	init(&a, backing[:])
	b1, _ := allocator_proc(&a, .Alloc, 32, 8, nil, 0)
	testing.expect_value(t, len(b1), 32)
	if len(b1) == 32 {
		for i in 0 ..< 32 {b1[i] = 0xFF} 	// scribble
	}
	free_all(&a)
	testing.expect_value(t, a.offset, 0)
	b2, _ := allocator_proc(&a, .Alloc, 32, 8, nil, 0)
	testing.expect_value(t, len(b2), 32)
	if len(b2) == 32 {
		testing.expect(t, addr(raw_data(b2)) == addr(raw_data(b1)), "reset reuses the same memory")
		for v in b2 {testing.expect_value(t, v, u8(0))} 	// re-zeroed on re-alloc
	}
}

@(test)
test_free_all_mode_matches_helper :: proc(t: ^testing.T) {
	backing: [128]byte
	a: Arena
	init(&a, backing[:])
	_, _ = allocator_proc(&a, .Alloc, 32, 8, nil, 0)
	testing.expect(t, a.offset > 0, "alloc advanced the offset")
	_, err := allocator_proc(&a, .Free_All, 0, 0, nil, 0)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, a.offset, 0)
}

// ── Resize: general case relocates + copies; last-alloc case grows in place ──

@(test)
test_resize_general_copies :: proc(t: ^testing.T) {
	backing: [256]byte
	a: Arena
	init(&a, backing[:])
	b1, _ := allocator_proc(&a, .Alloc, 16, 8, nil, 0)
	testing.expect_value(t, len(b1), 16)
	if len(b1) == 16 {
		for i in 0 ..< 16 {b1[i] = u8(i + 1)}
	}
	_, _ = allocator_proc(&a, .Alloc, 16, 8, nil, 0) // b1 is no longer the last allocation
	b3, err := allocator_proc(&a, .Resize, 64, 8, raw_data(b1), 16)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(b3), 64)
	if len(b1) == 16 && len(b3) == 64 {
		testing.expect(
			t,
			addr(raw_data(b3)) != addr(raw_data(b1)),
			"a non-last block must relocate",
		)
		for i in 0 ..< 16 {testing.expect_value(t, b3[i], u8(i + 1))} 	// old contents preserved
	}
}

@(test)
test_resize_last_allocation_in_place :: proc(t: ^testing.T) {
	// prev_offset exists for this: growing the most-recent allocation reuses its slot.
	backing: [256]byte
	a: Arena
	init(&a, backing[:])
	b1, _ := allocator_proc(&a, .Alloc, 16, 8, nil, 0) // the last allocation
	testing.expect_value(t, len(b1), 16)
	b2, err := allocator_proc(&a, .Resize, 64, 8, raw_data(b1), 16)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(b2), 64)
	if len(b1) == 16 && len(b2) == 64 {
		testing.expect(
			t,
			addr(raw_data(b2)) == addr(raw_data(b1)),
			"the last allocation grows in place",
		)
	}
}

// ── Query_Features: report the supported mode set ────────────────────────────

@(test)
test_query_features :: proc(t: ^testing.T) {
	backing: [64]byte
	a: Arena
	init(&a, backing[:])
	set: mem.Allocator_Mode_Set
	_, err := allocator_proc(&a, .Query_Features, 0, 0, &set, 0)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	expected := mem.Allocator_Mode_Set {
		.Alloc,
		.Alloc_Non_Zeroed,
		.Free_All,
		.Resize,
		.Resize_Non_Zeroed,
		.Query_Features,
	}
	testing.expect(t, set == expected, "features must list exactly the supported modes")
}

// ── Integration: the arena plugs into context.allocator ──────────────────────

@(test)
test_context_allocator_integration :: proc(t: ^testing.T) {
	backing: [1024]byte
	a: Arena
	init(&a, backing[:])
	context.allocator = allocator(&a) // everything below allocates from the arena
	// two-return forms + guards: at RED the stub can't allocate, so these come back
	// nil/empty — the guards keep the test failing cleanly instead of dereferencing nil.
	p, _ := new(int)
	testing.expect(t, p != nil, "new routed through the arena")
	if p != nil {
		p^ = 42
		testing.expect_value(t, p^, 42)
	}
	s, _ := make([]int, 8)
	testing.expect_value(t, len(s), 8)
	if len(s) == 8 {
		testing.expect_value(t, s[0], 0) // make zeroes via .Alloc
	}
	// the object lives inside the backing buffer
	lo := addr(raw_data(backing[:]))
	hi := lo + uintptr(len(backing))
	if p != nil {
		testing.expect(t, addr(p) >= lo && addr(p) < hi, "allocation came from the backing buffer")
	}
}

// ── Resize regression tests (added at review — cover the in-place gaps) ───────

@(test)
test_resize_shrink_returns_block :: proc(t: ^testing.T) {
	backing: [128]byte
	a: Arena
	init(&a, backing[:])
	b1, _ := allocator_proc(&a, .Alloc, 32, 8, nil, 0) // last allocation
	b2, err := allocator_proc(&a, .Resize, 16, 8, raw_data(b1), 32) // shrink 32 -> 16
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(b2), 16) // shrink must return the block, not nil
	if len(b2) == 16 {
		testing.expect(t, addr(raw_data(b2)) == addr(raw_data(b1)), "shrink stays in place")
	}
}

@(test)
test_resize_same_size_returns_block :: proc(t: ^testing.T) {
	backing: [128]byte
	a: Arena
	init(&a, backing[:])
	b1, _ := allocator_proc(&a, .Alloc, 32, 8, nil, 0)
	b2, err := allocator_proc(&a, .Resize, 32, 8, raw_data(b1), 32) // same size
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(b2), 32) // must return the block, not nil
}

@(test)
test_resize_in_place_grow_beyond_capacity_ooms :: proc(t: ^testing.T) {
	backing: [64]byte
	a: Arena
	init(&a, backing[:])
	b1, _ := allocator_proc(&a, .Alloc, 16, 8, nil, 0) // last allocation
	// grow the last block past the end of the backing: must OOM, not slice OOB
	b2, err := allocator_proc(&a, .Resize, 128, 8, raw_data(b1), 16)
	testing.expect_value(t, err, mem.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, len(b2), 0)
}

@(test)
test_resize_grow_zeroes_tail :: proc(t: ^testing.T) {
	backing: [128]byte
	for i in 0 ..< len(backing) {backing[i] = 0xAA} 	// dirty the backing
	a: Arena
	init(&a, backing[:])
	b1, _ := allocator_proc(&a, .Alloc, 16, 8, nil, 0) // .Alloc zeroes [0,16); last block
	b2, err := allocator_proc(&a, .Resize, 48, 8, raw_data(b1), 16) // .Resize (zeroed) grow
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(b2), 48)
	if len(b2) == 48 {
		for i in 16 ..< 48 {testing.expect_value(t, b2[i], u8(0))} 	// grown tail must be zeroed
	}
}

@(test)
test_resize_in_place_grow_preserves_old :: proc(t: ^testing.T) {
	backing: [128]byte
	a: Arena
	init(&a, backing[:])
	b1, _ := allocator_proc(&a, .Alloc_Non_Zeroed, 16, 8, nil, 0) // last block
	testing.expect_value(t, len(b1), 16)
	if len(b1) == 16 {
		for i in 0 ..< 16 {b1[i] = u8(i + 1)} 	// pattern 1..16
	}
	b2, err := allocator_proc(&a, .Resize, 32, 8, raw_data(b1), 16) // .Resize grow in place
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect_value(t, len(b2), 32)
	if len(b2) == 32 {
		for i in 0 ..< 16 {testing.expect_value(t, b2[i], u8(i + 1))} 	// OLD bytes must survive
		for i in 16 ..< 32 {testing.expect_value(t, b2[i], u8(0))} 	// only the new tail is zeroed
	}
}
