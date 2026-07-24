package handle_pool

import "base:intrinsics"
import "core:mem"

SENTINEL :: max(u32)

Handle :: distinct u64

Error :: enum {
	None,
	Full, // no free slot (all live or retired)
	Invalid_Handle, // zero, stale, retired, or out-of-range
}

// Slot — sparse entry: which lifetime (gen), where the item lives (dense_idx), and the
// freelist link (next).
Slot :: struct {
	gen:       u32, // current generation; starts at 1; wraps-to-0 ⇒ slot retired
	dense_idx: u32, // position in items[] while live
	next:      u32, // next free slot in FIFO order, SENTINEL if none
}

Handle_Pool :: struct($T: typeid, $HT: typeid) where size_of(HT) == size_of(u64),
	intrinsics.type_is_unsigned(HT),
	intrinsics.type_has_field(T, "handle"),
	intrinsics.type_field_type(T, "handle") == HT {
	items:     []T, // dense storage; [0:count) live — owned via `allocator`; items know their handles
	slots:     []Slot,
	count:     u32,
	free_head: u32, // dequeue end (oldest freed slot) — FIFO per BITSQUID
	free_tail: u32, // enqueue end
	allocator: mem.Allocator,
}

init :: proc(p: ^Handle_Pool($T, $HT), capacity: int, allocator := context.allocator) {
	assert(
		capacity > 0 && capacity < int(SENTINEL),
		"capacity must be greater than 0 and less than SENTINEL",
	)

	err: mem.Allocator_Error
	p.items, err = make([]T, capacity, allocator)
	assert(err == .None, "items allocation shouldn't fail")
	p.slots, err = make([]Slot, capacity, allocator)
	assert(err == .None, "slots allocation shouldn't fail")
	p.count = 0
	p.free_head = 0
	p.free_tail = u32(capacity - 1)
	for i in 0 ..< capacity {
		p.slots[i].gen = 1
		p.slots[i].dense_idx = u32(i)
		p.slots[i].next = u32(i + 1)
	}
	p.slots[capacity - 1].next = SENTINEL
	p.allocator = allocator
}

// destroy releases the pool's arrays via the allocator stored at init. The pool is unusable
// afterwards; every outstanding handle is dead.
destroy :: proc(p: ^Handle_Pool($T, $HT)) {
	delete(p.items, p.allocator)
	delete(p.slots, p.allocator)
}

// clear empties the pool without releasing memory: every LIVE slot's generation is bumped
// (retire-on-wrap) via each live item's embedded handle, the freelist is rebuilt over all
// non-retired slots, and count returns to 0. Every previously issued handle is stale
// afterwards. Retired slots (gen 0) stay retired — a fully retired pool remains .Full.
clear :: proc(p: ^Handle_Pool($T, $HT)) {
	for i in 0 ..< p.count {
		item := p.items[i]
		idx, _ := unpack_handle(item.handle)
		increment_gen(&p.slots[idx])
	}

	p.free_head = SENTINEL
	p.free_tail = SENTINEL
	for &slot, idx in p.slots {
		slot.dense_idx = u32(idx)
		if slot.gen == 0 {
			slot.next = SENTINEL
			continue
		}
		enqueue_free_slot(p, u32(idx))
	}
	p.count = 0
}

// add stores `item` and returns its handle (packed slot+generation, transmuted to HT). The
// stored copy's `handle` field is OVERWRITTEN with the issued handle — the caller's value
// there is ignored. Freelist empty (all slots live or retired) → (zero HT, .Full).
add :: proc(p: ^Handle_Pool($T, $HT), item: T) -> (h: HT, err: Error) {
	if p.free_head == SENTINEL {
		return 0, .Full
	}

	slot_idx := p.free_head
	slot := &p.slots[slot_idx]

	ht := HT(pack_handle(HT, slot_idx, slot.gen))
	p.items[p.count] = item
	p.items[p.count].handle = ht
	slot.dense_idx = p.count
	p.free_head = slot.next
	p.count += 1
	return ht, .None
}

is_empty :: proc(p: ^Handle_Pool($T, $HT)) -> bool {
	return p.count == 0
}

// remove deletes the item `h` refers to: the last dense item is swapped into the gap and its
// slot is patched via the moved item's embedded handle; the freed slot's generation is bumped
// (wrap-to-0 ⇒ retired, else FIFO-enqueued). Invalid/stale/zero/garbage handle →
// .Invalid_Handle (never panics).
remove :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> Error {
	hole_idx, ok := resolve_dense_idx(p, h)
	if !ok {
		return .Invalid_Handle
	}

	slot_idx, _ := unpack_handle(h)
	last_idx := p.count - 1

	if hole_idx != last_idx {
		moved_slot_idx, _ := unpack_handle(p.items[last_idx].handle)
		p.items[hole_idx] = p.items[last_idx]
		p.slots[moved_slot_idx].dense_idx = hole_idx
	}

	p.count -= 1
	overflow := increment_gen(&p.slots[slot_idx])
	if !overflow {
		enqueue_free_slot(p, slot_idx)
	}

	return .None
}

// get returns a COPY of the item `h` refers to (embedded handle included), or
// (T{}, .Invalid_Handle).
get :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> (item: T, err: Error) {
	dense_idx, ok := resolve_dense_idx(p, h)
	if !ok {
		err = .Invalid_Handle
		return
	}
	item = p.items[dense_idx]
	return
}

// get_ptr returns a pointer to the live item — a LOAN, valid only until the next
// remove/clear/destroy. Invalid handle → (nil, .Invalid_Handle).
//
// The item's `handle` field is POOL-OWNED: never write it through the loan. remove's
// swap patch and clear's sweep trust it to locate the owning slot — a scribbled field
// mispatches another live slot (wrong-item resolution) or indexes out of range.
get_ptr :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> (item: ^T, err: Error) {
	dense_idx, ok := resolve_dense_idx(p, h)
	if !ok {
		err = .Invalid_Handle
		return
	}
	item = &p.items[dense_idx]
	return
}

// has reports whether `h` currently resolves (in range, non-zero generation, generation
// matches, and the dense item embeds this exact handle). Garbage- and forgery-safe.
has :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> bool {
	_, ok := resolve_dense_idx(p, h)
	return ok
}

// slice returns the live items, items[0:count] — dense iteration is a plain slice walk over
// self-identifying items. Order is unspecified beyond the swap-with-last contract; the slice
// is invalidated by remove/clear/destroy — to remove while iterating, collect handles during
// the walk and remove after.
slice :: proc(p: ^Handle_Pool($T, $HT)) -> []T {
	return p.items[:p.count]
}

@(private = "file")
increment_gen :: proc(slot: ^Slot) -> (overflow: bool) {
	slot.gen, overflow = intrinsics.overflow_add(slot.gen, 1)
	if overflow {
		slot.gen = 0
	}
	return
}

// enqueue_free_slot appends the slot to the freelist's tail (FIFO). The caller guarantees
// the slot is neither retired nor already enqueued — remove and clear both share this so
// their freelist policies cannot drift apart.
@(private = "file")
enqueue_free_slot :: proc(p: ^Handle_Pool($T, $HT), slot_idx: u32) {
	p.slots[slot_idx].next = SENTINEL
	if p.free_head == SENTINEL {
		p.free_head = slot_idx
		p.free_tail = slot_idx
	} else {
		p.slots[p.free_tail].next = slot_idx
		p.free_tail = slot_idx
	}
}

@(private = "file")
pack_handle :: proc($HT: typeid, idx, gen: u32) -> HT {
	return HT(u64(gen) << 32 | u64(idx))
}

@(private = "file")
unpack_handle :: proc(h: $HT) -> (idx, gen: u32) {
	idx = u32(h & 0xFFFF_FFFF)
	gen = u32(h >> 32)
	return
}

// resolve_dense_idx maps a handle to its dense index. The sparse checks reject
// out-of-range, zero-gen, and gen-mismatched handles; the dense check then requires the
// resolved item to embed this exact handle. That last comparison kills FORGED handles
// that happen to match a free slot's current generation — without it they'd resolve
// through the free slot's stale dense_idx to another live item, and a remove through one
// would double-enqueue the free slot and corrupt the freelist.
@(private = "file")
resolve_dense_idx :: proc(p: ^Handle_Pool($T, $HT), ht: HT) -> (dense_idx: u32, ok: bool) {
	slot_idx, gen := unpack_handle(ht)
	if int(slot_idx) >= len(p.items) || gen == 0 || gen != p.slots[slot_idx].gen {
		return 0, false
	}
	dense_idx = p.slots[slot_idx].dense_idx
	if dense_idx >= p.count || p.items[dense_idx].handle != ht {
		return 0, false
	}
	return dense_idx, true
}

