package handle_pool

// Tutor-written conformance tests for the m03-02 generational handle pool.
// They bind to the agreed interface in design.md (per-operation contract table).
// Written RED against the stubs; the learner implements until green.
//
// Run: odin test katas/handle_pool

import "core:testing"

// Craft a handle from parts — binds the documented bit layout
// (low 32 bits index, high 32 bits generation).
pack_handle :: proc(idx, gen: u32) -> Handle {
	return Handle(u64(gen) << 32 | u64(idx))
}

handle_idx :: proc(h: Handle) -> u32 {
	return u32(u64(h) & 0xFFFF_FFFF)
}

handle_gen :: proc(h: Handle) -> u32 {
	return u32(u64(h) >> 32)
}

@(test)
test_add_get_roundtrip :: proc(t: ^testing.T) {
	p: Handle_Pool(int)
	init(&p, 8)
	defer destroy(&p)

	ha, ea := add(&p, 10)
	hb, eb := add(&p, 20)
	hc, ec := add(&p, 30)
	testing.expect_value(t, ea, Handle_Error.None)
	testing.expect_value(t, eb, Handle_Error.None)
	testing.expect_value(t, ec, Handle_Error.None)
	testing.expect(t, ha != 0, "handle must not be the zero handle")
	testing.expect(t, ha != hb && hb != hc && ha != hc, "handles must be distinct")
	testing.expect_value(t, p.count, u32(3))

	va, gea := get(&p, ha)
	vb, geb := get(&p, hb)
	vc, gec := get(&p, hc)
	testing.expect_value(t, gea, Handle_Error.None)
	testing.expect_value(t, geb, Handle_Error.None)
	testing.expect_value(t, gec, Handle_Error.None)
	testing.expect_value(t, va, 10)
	testing.expect_value(t, vb, 20)
	testing.expect_value(t, vc, 30)
	testing.expect_value(t, len(slice(&p)), 3)
}

@(test)
test_get_ptr_is_live_get_is_copy :: proc(t: ^testing.T) {
	p: Handle_Pool(int)
	init(&p, 4)
	defer destroy(&p)

	h, _ := add(&p, 7)
	ptr, perr := get_ptr(&p, h)
	testing.expect_value(t, perr, Handle_Error.None)
	if !testing.expect(t, ptr != nil, "get_ptr must return a live pointer") {
		return
	}
	ptr^ = 99

	v, _ := get(&p, h)
	testing.expect_value(t, v, 99) // mutation through the loan is visible

	v = 1234 // mutating the copy...
	v2, _ := get(&p, h)
	testing.expect_value(t, v2, 99) // ...does not touch the pool
}

@(test)
test_has_lifecycle :: proc(t: ^testing.T) {
	p: Handle_Pool(int)
	init(&p, 4)
	defer destroy(&p)

	h, _ := add(&p, 1)
	testing.expect(t, has(&p, h), "freshly added handle must resolve")

	rerr := remove(&p, h)
	testing.expect_value(t, rerr, Handle_Error.None)
	testing.expect(t, !has(&p, h), "removed handle must not resolve")
}

@(test)
test_zero_handle_invalid_everywhere :: proc(t: ^testing.T) {
	p: Handle_Pool(int)
	init(&p, 4)
	defer destroy(&p)

	_, _ = add(&p, 5) // slot 0 occupied on its first generation

	zero: Handle // ZII — this is Handle(0)
	testing.expect(t, !has(&p, zero), "zero handle must never resolve")

	v, gerr := get(&p, zero)
	testing.expect_value(t, gerr, Handle_Error.Invalid_Handle)
	testing.expect_value(t, v, 0) // ZII value on error

	ptr, perr := get_ptr(&p, zero)
	testing.expect_value(t, perr, Handle_Error.Invalid_Handle)
	testing.expect(t, ptr == nil, "get_ptr on zero handle must return nil")

	testing.expect_value(t, remove(&p, zero), Handle_Error.Invalid_Handle)
}

@(test)
test_garbage_handle_safe :: proc(t: ^testing.T) {
	p: Handle_Pool(int)
	init(&p, 4)
	defer destroy(&p)

	h, _ := add(&p, 5)

	oor := pack_handle(9999, 1) // index far out of range — must not panic
	testing.expect(t, !has(&p, oor), "out-of-range index must not resolve")
	testing.expect_value(t, remove(&p, oor), Handle_Error.Invalid_Handle)

	junk := Handle(0xDEAD_BEEF_F00D_CAFE)
	testing.expect(t, !has(&p, junk), "garbage bits must not resolve")

	wrong_gen := pack_handle(handle_idx(h), handle_gen(h) + 7)
	testing.expect(t, !has(&p, wrong_gen), "right slot, wrong generation must not resolve")
}

@(test)
test_stale_after_remove_and_double_remove :: proc(t: ^testing.T) {
	p: Handle_Pool(int)
	init(&p, 4)
	defer destroy(&p)

	h, _ := add(&p, 42)
	testing.expect_value(t, remove(&p, h), Handle_Error.None)

	v, gerr := get(&p, h)
	testing.expect_value(t, gerr, Handle_Error.Invalid_Handle)
	testing.expect_value(t, v, 0)
	testing.expect_value(t, remove(&p, h), Handle_Error.Invalid_Handle) // double remove
}

@(test)
test_slot_reuse_bumps_generation :: proc(t: ^testing.T) {
	p: Handle_Pool(int)
	init(&p, 2)
	defer destroy(&p)

	h1, _ := add(&p, 100)
	h2, _ := add(&p, 200) // pool full — the only free slot after a remove is h1's
	testing.expect_value(t, remove(&p, h1), Handle_Error.None)

	h3, e3 := add(&p, 300)
	testing.expect_value(t, e3, Handle_Error.None)
	testing.expect_value(t, handle_idx(h3), handle_idx(h1)) // same slot reused...
	testing.expect_value(t, handle_gen(h3), handle_gen(h1) + 1) // ...next generation

	testing.expect(t, !has(&p, h1), "old handle to the reused slot must be stale")
	v3, _ := get(&p, h3)
	testing.expect_value(t, v3, 300)
	v2, _ := get(&p, h2)
	testing.expect_value(t, v2, 200)
}

@(test)
test_full_when_exhausted_and_recovers :: proc(t: ^testing.T) {
	p: Handle_Pool(int)
	init(&p, 2)
	defer destroy(&p)

	_, e1 := add(&p, 1)
	h2, e2 := add(&p, 2)
	testing.expect_value(t, e1, Handle_Error.None)
	testing.expect_value(t, e2, Handle_Error.None)

	h3, e3 := add(&p, 3)
	testing.expect_value(t, e3, Handle_Error.Full)
	testing.expect_value(t, h3, Handle(0)) // Full returns the zero handle

	testing.expect_value(t, remove(&p, h2), Handle_Error.None) // free one → capacity again
	_, e4 := add(&p, 4)
	testing.expect_value(t, e4, Handle_Error.None)
}

@(test)
test_remove_swaps_last_and_patches :: proc(t: ^testing.T) {
	p: Handle_Pool(int)
	init(&p, 8)
	defer destroy(&p)

	ha, _ := add(&p, 10) // dense 0
	hb, _ := add(&p, 20) // dense 1
	hc, _ := add(&p, 30) // dense 2 (last)

	testing.expect_value(t, remove(&p, ha), Handle_Error.None) // 30 must move into dense 0
	testing.expect_value(t, p.count, u32(2))

	vc, ec := get(&p, hc) // THE patch test: the moved item's handle still resolves
	testing.expect_value(t, ec, Handle_Error.None)
	testing.expect_value(t, vc, 30)
	vb, _ := get(&p, hb)
	testing.expect_value(t, vb, 20)

	s := slice(&p) // swap-with-last is the contract: dense is now [30, 20]
	if !testing.expect_value(t, len(s), 2) {
		return
	}
	testing.expect_value(t, s[0], 30)
	testing.expect_value(t, s[1], 20)

	testing.expect_value(t, remove(&p, hb), Handle_Error.None) // removing the LAST dense item (self-swap)
	testing.expect_value(t, p.count, u32(1))
	vc2, _ := get(&p, hc)
	testing.expect_value(t, vc2, 30)
}

@(test)
test_fifo_reuse_order :: proc(t: ^testing.T) {
	p: Handle_Pool(int)
	init(&p, 3)
	defer destroy(&p)

	h0, _ := add(&p, 0) // freelist threaded 0→cap-1: adds take slots 0,1,2 in order
	h1, _ := add(&p, 1)
	_, _ = add(&p, 2)
	testing.expect_value(t, handle_idx(h0), u32(0))
	testing.expect_value(t, handle_idx(h1), u32(1))

	testing.expect_value(t, remove(&p, h0), Handle_Error.None) // freed order: 0 then 1
	testing.expect_value(t, remove(&p, h1), Handle_Error.None)

	r0, _ := add(&p, 10) // FIFO: oldest freed slot (0) is reused first...
	r1, _ := add(&p, 11) // ...then 1 — LIFO would give 1 then 0
	testing.expect_value(t, handle_idx(r0), u32(0))
	testing.expect_value(t, handle_idx(r1), u32(1))
}

@(test)
test_clear_invalidates_all :: proc(t: ^testing.T) {
	p: Handle_Pool(int)
	init(&p, 4)
	defer destroy(&p)

	h1, _ := add(&p, 1)
	h2, _ := add(&p, 2)
	h3, _ := add(&p, 3)

	clear(&p)
	testing.expect_value(t, p.count, u32(0))
	testing.expect_value(t, len(slice(&p)), 0)
	testing.expect(t, !has(&p, h1), "clear must stale handle 1")
	testing.expect(t, !has(&p, h2), "clear must stale handle 2")
	testing.expect(t, !has(&p, h3), "clear must stale handle 3")

	h4, e4 := add(&p, 4) // pool must be fully usable again
	testing.expect_value(t, e4, Handle_Error.None)
	testing.expect(t, has(&p, h4), "post-clear add must resolve")
}

@(test)
test_retire_at_max_generation :: proc(t: ^testing.T) {
	p: Handle_Pool(int)
	init(&p, 1) // a single slot, so retirement is observable as .Full
	defer destroy(&p)

	h, _ := add(&p, 5)
	if !testing.expect(t, len(p.slots) == 1, "whitebox: expected one slot after init") {
		return
	}

	// Whitebox: age the slot to the end of its generation space, then remove
	// via a handle crafted at that generation. The bump wraps 0xFFFFFFFF → 0,
	// which must RETIRE the slot (never re-enqueue it), not recycle it.
	p.slots[0].gen = max(u32)
	aged := pack_handle(handle_idx(h), max(u32))
	testing.expect_value(t, remove(&p, aged), Handle_Error.None)

	testing.expect(t, !has(&p, aged), "wrapped slot must not resolve")
	_, e := add(&p, 6)
	testing.expect_value(t, e, Handle_Error.Full) // the only slot is retired → pool is Full
}
