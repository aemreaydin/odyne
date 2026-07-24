#+private
package handle_pool

// Tutor-written conformance tests for the m03-03 graduated handle pool. They bind to the
// AMENDED agreed interface (design.md §Amended agreed interface) and trace to the
// core-containers spec delta. Written RED against the stub; the learner ports the kata
// until green.
//
// The m03-02 kata suite with the caller-typed $HT and embedded-handle item contract
// threaded through, plus three surface tests the graduation adds: add-sets-the-embedded-
// handle, the ready-made Handle, and two distinct handle types coexisting. Every test
// asserts at least one positive-path expectation, so the benign stub fails all of them.
//
// Run: odin test engine/core/containers/handle_pool -collection:engine=engine

import "core:testing"

// The tests' own boundary-crossing handle types — exactly what a system would declare.
Test_Handle :: distinct u64
Sprite_Handle :: distinct u64
Audio_Handle :: distinct u64

// Item types embedding their handles, per the where-clause contract.
Test_Item :: struct {
	handle: Test_Handle,
	value:  int,
}

// Craft a handle from parts — binds the documented bit layout
// (low 32 bits index, high 32 bits generation).
pack_test_handle :: proc(idx, gen: u32) -> Test_Handle {
	return Test_Handle(u64(gen) << 32 | u64(idx))
}

handle_idx :: proc(h: Test_Handle) -> u32 {
	return u32(u64(h) & 0xFFFF_FFFF)
}

handle_gen :: proc(h: Test_Handle) -> u32 {
	return u32(u64(h) >> 32)
}

@(test)
test_add_get_roundtrip :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 8)
	defer destroy(&p)

	ha, ea := add(&p, Test_Item{value = 10})
	hb, eb := add(&p, Test_Item{value = 20})
	hc, ec := add(&p, Test_Item{value = 30})
	testing.expect_value(t, ea, Error.None)
	testing.expect_value(t, eb, Error.None)
	testing.expect_value(t, ec, Error.None)
	testing.expect(t, ha != Test_Handle(0), "handle must not be the zero handle")
	testing.expect(t, ha != hb && hb != hc && ha != hc, "handles must be distinct")
	testing.expect_value(t, p.count, u32(3))

	va, gea := get(&p, ha)
	vb, geb := get(&p, hb)
	vc, gec := get(&p, hc)
	testing.expect_value(t, gea, Error.None)
	testing.expect_value(t, geb, Error.None)
	testing.expect_value(t, gec, Error.None)
	testing.expect_value(t, va.value, 10)
	testing.expect_value(t, vb.value, 20)
	testing.expect_value(t, vc.value, 30)
	testing.expect_value(t, len(slice(&p)), 3)
}

@(test)
test_add_sets_embedded_handle :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 4)
	defer destroy(&p)

	// Garbage in the caller's handle field — add must overwrite it with the issued handle.
	junk_field := pack_test_handle(1234, 999)
	h, e := add(&p, Test_Item{handle = junk_field, value = 1})
	testing.expect_value(t, e, Error.None)
	testing.expect(t, h != junk_field, "issued handle must not echo the caller's field")

	v, gerr := get(&p, h)
	testing.expect_value(t, gerr, Error.None)
	testing.expect_value(t, v.handle, h) // resolution yields a self-identifying item

	s := slice(&p)
	if !testing.expect_value(t, len(s), 1) {
		return
	}
	testing.expect_value(t, s[0].handle, h) // iteration yields self-identifying items
}

@(test)
test_get_ptr_is_live_get_is_copy :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 4)
	defer destroy(&p)

	h, _ := add(&p, Test_Item{value = 7})
	ptr, perr := get_ptr(&p, h)
	testing.expect_value(t, perr, Error.None)
	if !testing.expect(t, ptr != nil, "get_ptr must return a live pointer") {
		return
	}
	ptr.value = 99

	v, _ := get(&p, h)
	testing.expect_value(t, v.value, 99) // mutation through the loan is visible

	v.value = 1234 // mutating the copy...
	v2, _ := get(&p, h)
	testing.expect_value(t, v2.value, 99) // ...does not touch the pool
}

@(test)
test_has_lifecycle :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 4)
	defer destroy(&p)

	h, _ := add(&p, Test_Item{value = 1})
	testing.expect(t, has(&p, h), "freshly added handle must resolve")

	rerr := remove(&p, h)
	testing.expect_value(t, rerr, Error.None)
	testing.expect(t, !has(&p, h), "removed handle must not resolve")
}

@(test)
test_zero_handle_invalid_everywhere :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 4)
	defer destroy(&p)

	_, ea := add(&p, Test_Item{value = 5}) // slot 0 occupied on its first generation
	testing.expect_value(t, ea, Error.None)

	zero: Test_Handle // ZII — the zero value of the caller's handle type
	testing.expect(t, !has(&p, zero), "zero handle must never resolve")

	v, gerr := get(&p, zero)
	testing.expect_value(t, gerr, Error.Invalid_Handle)
	testing.expect_value(t, v, Test_Item{}) // ZII value on error

	ptr, perr := get_ptr(&p, zero)
	testing.expect_value(t, perr, Error.Invalid_Handle)
	testing.expect(t, ptr == nil, "get_ptr on zero handle must return nil")

	testing.expect_value(t, remove(&p, zero), Error.Invalid_Handle)
}

@(test)
test_garbage_handle_safe :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 4)
	defer destroy(&p)

	h, ea := add(&p, Test_Item{value = 5})
	testing.expect_value(t, ea, Error.None)
	testing.expect(t, has(&p, h), "live handle must resolve")

	oor := pack_test_handle(9999, 1) // index far out of range — must not panic
	testing.expect(t, !has(&p, oor), "out-of-range index must not resolve")
	testing.expect_value(t, remove(&p, oor), Error.Invalid_Handle)

	junk := Test_Handle(0xDEAD_BEEF_F00D_CAFE)
	testing.expect(t, !has(&p, junk), "garbage bits must not resolve")

	wrong_gen := pack_test_handle(handle_idx(h), handle_gen(h) + 7)
	testing.expect(t, !has(&p, wrong_gen), "right slot, wrong generation must not resolve")
}

@(test)
test_stale_after_remove_and_double_remove :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 4)
	defer destroy(&p)

	h, _ := add(&p, Test_Item{value = 42})
	testing.expect_value(t, remove(&p, h), Error.None)

	v, gerr := get(&p, h)
	testing.expect_value(t, gerr, Error.Invalid_Handle)
	testing.expect_value(t, v, Test_Item{})
	testing.expect_value(t, remove(&p, h), Error.Invalid_Handle) // double remove
}

@(test)
test_slot_reuse_bumps_generation :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 2)
	defer destroy(&p)

	h1, _ := add(&p, Test_Item{value = 100})
	h2, _ := add(&p, Test_Item{value = 200}) // pool full — the only free slot after a remove is h1's
	testing.expect_value(t, remove(&p, h1), Error.None)

	h3, e3 := add(&p, Test_Item{value = 300})
	testing.expect_value(t, e3, Error.None)
	testing.expect_value(t, handle_idx(h3), handle_idx(h1)) // same slot reused...
	testing.expect_value(t, handle_gen(h3), handle_gen(h1) + 1) // ...next generation

	testing.expect(t, !has(&p, h1), "old handle to the reused slot must be stale")
	v3, _ := get(&p, h3)
	testing.expect_value(t, v3.value, 300)
	v2, _ := get(&p, h2)
	testing.expect_value(t, v2.value, 200)
}

@(test)
test_full_when_exhausted_and_recovers :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 2)
	defer destroy(&p)

	_, e1 := add(&p, Test_Item{value = 1})
	h2, e2 := add(&p, Test_Item{value = 2})
	testing.expect_value(t, e1, Error.None)
	testing.expect_value(t, e2, Error.None)

	h3, e3 := add(&p, Test_Item{value = 3})
	testing.expect_value(t, e3, Error.Full)
	testing.expect_value(t, h3, Test_Handle(0)) // Full returns the zero handle

	testing.expect_value(t, remove(&p, h2), Error.None) // free one → capacity again
	_, e4 := add(&p, Test_Item{value = 4})
	testing.expect_value(t, e4, Error.None)
}

@(test)
test_remove_swaps_last_and_patches :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 8)
	defer destroy(&p)

	ha, _ := add(&p, Test_Item{value = 10}) // dense 0
	hb, _ := add(&p, Test_Item{value = 20}) // dense 1
	hc, _ := add(&p, Test_Item{value = 30}) // dense 2 (last)

	testing.expect_value(t, remove(&p, ha), Error.None) // 30 must move into dense 0
	testing.expect_value(t, p.count, u32(2))

	vc, ec := get(&p, hc) // THE patch test: the moved item's handle still resolves
	testing.expect_value(t, ec, Error.None)
	testing.expect_value(t, vc.value, 30)
	vb, _ := get(&p, hb)
	testing.expect_value(t, vb.value, 20)

	s := slice(&p) // swap-with-last is the contract: dense is now [30, 20]
	if !testing.expect_value(t, len(s), 2) {
		return
	}
	testing.expect_value(t, s[0].value, 30)
	testing.expect_value(t, s[0].handle, hc) // the moved item carried its identity with it
	testing.expect_value(t, s[1].value, 20)

	testing.expect_value(t, remove(&p, hb), Error.None) // removing the LAST dense item (self-swap)
	testing.expect_value(t, p.count, u32(1))
	vc2, _ := get(&p, hc)
	testing.expect_value(t, vc2.value, 30)
}

@(test)
test_fifo_reuse_order :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 3)
	defer destroy(&p)

	h0, e0 := add(&p, Test_Item{value = 0}) // freelist threaded 0→cap-1: adds take slots 0,1,2 in order
	h1, _ := add(&p, Test_Item{value = 1})
	_, _ = add(&p, Test_Item{value = 2})
	testing.expect_value(t, e0, Error.None)
	testing.expect_value(t, handle_idx(h0), u32(0))
	testing.expect_value(t, handle_idx(h1), u32(1))

	testing.expect_value(t, remove(&p, h0), Error.None) // freed order: 0 then 1
	testing.expect_value(t, remove(&p, h1), Error.None)

	r0, _ := add(&p, Test_Item{value = 10}) // FIFO: oldest freed slot (0) is reused first...
	r1, _ := add(&p, Test_Item{value = 11}) // ...then 1 — LIFO would give 1 then 0
	testing.expect_value(t, handle_idx(r0), u32(0))
	testing.expect_value(t, handle_idx(r1), u32(1))
}

@(test)
test_clear_invalidates_all :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 4)
	defer destroy(&p)

	h1, e1 := add(&p, Test_Item{value = 1})
	h2, _ := add(&p, Test_Item{value = 2})
	h3, _ := add(&p, Test_Item{value = 3})
	testing.expect_value(t, e1, Error.None)

	clear(&p)
	testing.expect_value(t, p.count, u32(0))
	testing.expect_value(t, len(slice(&p)), 0)
	testing.expect(t, !has(&p, h1), "clear must stale handle 1")
	testing.expect(t, !has(&p, h2), "clear must stale handle 2")
	testing.expect(t, !has(&p, h3), "clear must stale handle 3")

	h4, e4 := add(&p, Test_Item{value = 4}) // pool must be fully usable again
	testing.expect_value(t, e4, Error.None)
	testing.expect(t, has(&p, h4), "post-clear add must resolve")
}

@(test)
test_clear_bumps_only_live_slots :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 4)
	defer destroy(&p)

	// One live item in a cap-4 pool: the three trailing items[] entries are ZII —
	// their handle field is 0, and unpacking 0 yields slot INDEX 0. A clear that
	// walks the whole items array (not just [0:count)) would bump slot 0 once for
	// the live item and once per ZII entry. The contract says: bump every LIVE
	// slot's generation — exactly once.
	h, e := add(&p, Test_Item{value = 1})
	testing.expect_value(t, e, Error.None)

	clear(&p)

	h2, e2 := add(&p, Test_Item{value = 2}) // FIFO: slot 0 again, next generation
	testing.expect_value(t, e2, Error.None)
	testing.expect_value(t, handle_idx(h2), handle_idx(h))
	testing.expect_value(t, handle_gen(h2), handle_gen(h) + 1) // exactly one bump
}

@(test)
test_retire_at_max_generation :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 1) // a single slot, so retirement is observable as .Full
	defer destroy(&p)

	h, _ := add(&p, Test_Item{value = 5})
	if !testing.expect(t, len(p.slots) == 1, "whitebox: expected one slot after init") {
		return
	}

	// Whitebox: age the slot to the end of its generation space, then remove via a handle
	// crafted at that generation. The stored item's embedded handle must be aged in step —
	// remove's patch path and clear's sweep read it. The bump wraps 0xFFFFFFFF → 0, which
	// must RETIRE the slot (never re-enqueue it), not recycle it.
	p.slots[0].gen = max(u32)
	aged := pack_test_handle(handle_idx(h), max(u32))
	p.items[0].handle = aged
	testing.expect_value(t, remove(&p, aged), Error.None)

	testing.expect(t, !has(&p, aged), "wrapped slot must not resolve")
	_, e := add(&p, Test_Item{value = 6})
	testing.expect_value(t, e, Error.Full) // the only slot is retired → pool is Full
}

@(test)
test_clear_rebuilds_full_freelist :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 4)
	defer destroy(&p)

	// Diverge slot-space from dense-space: fill, then remove two non-last items
	// (each remove relocates the last item via swap-with-last), so the surviving
	// live slots are scattered and two slots are already free before the clear.
	h: [4]Test_Handle
	for i in 0 ..< 4 {
		h[i], _ = add(&p, Test_Item{value = i})
	}
	testing.expect_value(t, remove(&p, h[0]), Error.None)
	testing.expect_value(t, remove(&p, h[1]), Error.None)

	clear(&p)
	testing.expect_value(t, p.count, u32(0))

	// An emptied pool must hand back ALL `capacity` slots again — clear has to
	// rethread the freelist over every slot, not just the ones that were live.
	for i in 0 ..< 4 {
		_, e := add(&p, Test_Item{value = 100 + i})
		if !testing.expect_value(t, e, Error.None) {
			return
		}
	}
	_, efull := add(&p, Test_Item{value = 999})
	testing.expect_value(t, efull, Error.Full)
}

@(test)
test_ready_made_handle :: proc(t: ^testing.T) {
	// Pools that never cross a package boundary use the package's own Handle —
	// no distinct type ceremony required.
	Plain_Item :: struct {
		handle: Handle,
		value:  int,
	}
	p: Handle_Pool(Plain_Item, Handle)
	init(&p, 4)
	defer destroy(&p)

	h, e := add(&p, Plain_Item{value = 77})
	testing.expect_value(t, e, Error.None)
	testing.expect(t, h != Handle(0), "handle must not be the zero handle")

	v, gerr := get(&p, h)
	testing.expect_value(t, gerr, Error.None)
	testing.expect_value(t, v.value, 77)
	testing.expect_value(t, v.handle, h)
}

@(test)
test_distinct_handle_types_coexist :: proc(t: ^testing.T) {
	// The point of $HT: each system instantiates the pool with its own distinct
	// handle type, and cross-system mixups are COMPILE errors, e.g.:
	//   get(&sounds, sh)  // Sprite_Handle where Audio_Handle expected — does not compile
	Sprite :: struct {
		handle: Sprite_Handle,
		scale:  f32,
	}
	Sound :: struct {
		handle: Audio_Handle,
		volume: int,
	}
	sprites: Handle_Pool(Sprite, Sprite_Handle)
	sounds: Handle_Pool(Sound, Audio_Handle)
	init(&sprites, 4)
	init(&sounds, 4)
	defer destroy(&sprites)
	defer destroy(&sounds)

	sh, se := add(&sprites, Sprite{scale = 1.5})
	oh, oe := add(&sounds, Sound{volume = 42})
	testing.expect_value(t, se, Error.None)
	testing.expect_value(t, oe, Error.None)

	sv, sgerr := get(&sprites, sh)
	testing.expect_value(t, sgerr, Error.None)
	testing.expect_value(t, sv.scale, f32(1.5))
	ov, ogerr := get(&sounds, oh)
	testing.expect_value(t, ogerr, Error.None)
	testing.expect_value(t, ov.volume, 42)
}

@(test)
test_forged_handle_matching_free_slot_gen_rejected :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 2)
	defer destroy(&p)

	ha, _ := add(&p, Test_Item{value = 1})
	hb, _ := add(&p, Test_Item{value = 2})
	testing.expect_value(t, remove(&p, ha), Error.None) // frees A's slot at gen+1; B swaps to dense 0

	// Forge a handle for the FREE slot at its CURRENT generation: every sparse check
	// passes (in range, gen ≠ 0, gen matches) and the free slot's stale dense_idx points
	// at live item B. Only the dense-side check (items[d].handle == h) can reject it —
	// without it, get would return B and remove would corrupt the freelist.
	forged := pack_test_handle(handle_idx(ha), handle_gen(ha) + 1)
	testing.expect(t, !has(&p, forged), "forged handle must not resolve")
	_, gerr := get(&p, forged)
	testing.expect_value(t, gerr, Error.Invalid_Handle)
	testing.expect_value(t, remove(&p, forged), Error.Invalid_Handle)

	// The live item is untouched and still resolves.
	v, err := get(&p, hb)
	testing.expect_value(t, err, Error.None)
	testing.expect_value(t, v.value, 2)
}

@(test)
test_clear_keeps_retired_slots_retired :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 1)
	defer destroy(&p)

	// Retire the only slot: age it to the last generation and remove (wrap ⇒ retired),
	// exactly as test_retire_at_max_generation establishes.
	h, _ := add(&p, Test_Item{value = 5})
	p.slots[0].gen = max(u32)
	aged := pack_test_handle(handle_idx(h), max(u32))
	p.items[0].handle = aged
	testing.expect_value(t, remove(&p, aged), Error.None)

	clear(&p)

	// clear rebuilds the freelist, but a retired slot must STAY retired: gen 0 can never
	// back a resolvable handle, so re-enqueueing the slot would make add() hand out a
	// handle that is dead on arrival — and a dense item that can never be removed.
	h2, e := add(&p, Test_Item{value = 6})
	testing.expect_value(t, e, Error.Full)
	testing.expect(t, !has(&p, h2), "a handle from a retired slot must never resolve")
}

@(test)
test_clear_retires_live_slot_at_max_generation :: proc(t: ^testing.T) {
	p: Handle_Pool(Test_Item, Test_Handle)
	init(&p, 1)
	defer destroy(&p)

	// A LIVE item whose slot sits at the last generation: clear's own bump wraps it to 0,
	// which must retire the slot exactly like remove's wrap path does.
	h, _ := add(&p, Test_Item{value = 5})
	p.slots[0].gen = max(u32)
	p.items[0].handle = pack_test_handle(handle_idx(h), max(u32))

	clear(&p)

	_, e := add(&p, Test_Item{value = 6})
	testing.expect_value(t, e, Error.Full)
}

