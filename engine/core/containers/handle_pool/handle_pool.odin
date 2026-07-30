package handle_pool

import "base:intrinsics"
import "core:mem"

// Freelist terminator: no next free slot.
SENTINEL :: max(u32)

// Slot index in the low 32 bits, generation in the high 32. Generations start at 1, so a
// zero handle never validates.
Handle :: distinct u64

Error :: enum {
	None,
	Full, // no free slot (all live or retired)
	Invalid_Handle, // zero, stale, retired, or out-of-range
}

// Sparse entry: which lifetime, where the item currently lives, and the freelist link.
Slot :: struct {
	gen:       u32, // starts at 1; generation 0 means retired, and the slot is never reused
	dense_idx: u32,
	next:      u32, // next free slot, or SENTINEL
}

Handle_Pool :: struct($T: typeid, $HT: typeid) where size_of(HT) == size_of(u64),
	intrinsics.type_is_unsigned(HT),
	intrinsics.type_has_field(T, "handle"),
	intrinsics.type_field_type(T, "handle") == HT {
	items:     []T, // live items are `items[:count]`; owned via `allocator`
	slots:     []Slot,
	count:     u32,
	free_head: u32,
	free_tail: u32,
	allocator: mem.Allocator,
}

// Prepares `p` to hold up to `capacity` live items, which it owns until `destroy`. Panics
// unless `0 < capacity < SENTINEL`.
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

// Releases the pool's storage through the allocator given at `init`. Every outstanding
// handle is dead afterwards.
destroy :: proc(p: ^Handle_Pool($T, $HT)) {
	delete(p.items, p.allocator)
	delete(p.slots, p.allocator)
}

/*
Empties the pool without releasing its storage. Every handle issued before the call is stale
afterwards. Retired slots stay retired, so a fully retired pool still reports `.Full`.
*/
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

/*
Stores `item` and returns its handle. The stored copy's `handle` field is overwritten with
the issued handle, so whatever the caller put there is ignored. Returns `.Full` when no slot
is available.
*/
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

/*
Removes the item `h` refers to. Remaining items may be reordered, invalidating pointers from
`get_ptr` and slices from `slice`. An invalid handle returns `.Invalid_Handle` rather than
panicking.
*/
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

// Returns a copy of the item `h` refers to, or `(T{}, .Invalid_Handle)`.
get :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> (item: T, err: Error) {
	dense_idx, ok := resolve_dense_idx(p, h)
	if !ok {
		err = .Invalid_Handle
		return
	}
	item = p.items[dense_idx]
	return
}

/*
Returns a pointer to the live item, or `(nil, .Invalid_Handle)`. The pointer is a loan:
`remove`, `clear`, and `destroy` may invalidate it.

The item's `handle` field is pool-owned — never write it through the loan. `remove` and
`clear` trust it to locate the owning slot, so a scribbled field resolves to the wrong item
or indexes out of range.
*/
get_ptr :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> (item: ^T, err: Error) {
	dense_idx, ok := resolve_dense_idx(p, h)
	if !ok {
		err = .Invalid_Handle
		return
	}
	item = &p.items[dense_idx]
	return
}

// Whether `h` currently resolves. Safe against garbage and forged handles.
has :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> bool {
	_, ok := resolve_dense_idx(p, h)
	return ok
}

/*
Returns the live items. Order is unspecified, and `remove`, `clear`, and `destroy` invalidate
the slice — to remove while iterating, collect handles during the walk and remove afterwards.
*/
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

// Appends a slot to the freelist tail. The caller guarantees it is neither retired nor
// already enqueued; `remove` and `clear` share this so their policies cannot drift apart.
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
