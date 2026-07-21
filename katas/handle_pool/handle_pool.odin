package handle_pool

// Generational handle pool — lesson m03-02 kata.
//
// Packed + index-table layout (Bitsquid's second design): items live in a dense
// array [0:count); a sparse slot table maps handle index → {generation, dense
// position}; remove swap-with-lasts the dense array and patches the moved item's
// slot via dense_to_slot. Free slots are recycled through a FIFO freelist so
// reuse spreads across slots. Generations start at 1 (the ZII zero handle can
// never validate) and a slot whose counter wraps to 0 is retired, never reused.
//
// Ownership: the pool OWNS its three arrays, allocated from the allocator given
// to init and released by destroy. A ^T from get_ptr is a LOAN — it dies at the
// next remove/clear/destroy (any remove may relocate your item); add never
// invalidates (fixed capacity, no reallocation).
//
// Agreed interface: openspec/changes/lesson-m03-02-handle-pool/design.md
// Tests: odin test katas/handle_pool

import "base:intrinsics"
import "core:mem"

SENTINEL :: max(u32) // freelist "none"

// Handle — packed u64: low 32 bits slot index, high 32 bits generation.
// Generations start at 1, so Handle(0) — the ZII zero value — can never validate.
Handle :: distinct u64

Handle_Error :: enum {
	None,
	Full,           // no free slot (all live or retired)
	Invalid_Handle, // zero, stale, retired, or out-of-range
}

// Slot — sparse entry: which lifetime (gen), where the item lives (dense_idx),
// and the freelist link (next).
Slot :: struct {
	gen:       u32, // current generation; starts at 1; wraps-to-0 ⇒ slot retired
	dense_idx: u32, // position in items[] while live
	next:      u32, // next free slot in FIFO order, SENTINEL if none
}

Handle_Pool :: struct($T: typeid) {
	items:         []T,   // dense storage; [0:count) live — owned via `allocator`
	dense_to_slot: []u32, // dense position → owning slot (remove's patch-up map)
	slots:         []Slot,
	count:         u32,
	free_head:     u32,   // dequeue end (oldest freed slot) — FIFO per BITSQUID
	free_tail:     u32,   // enqueue end
	allocator:     mem.Allocator,
}

// init allocates the pool's three arrays (capacity each) from `allocator`,
// threads the FIFO freelist 0→capacity-1, and sets every slot's generation to 1.
// Asserts 0 < capacity < SENTINEL. The pool owns its arrays until destroy.
init :: proc(p: ^Handle_Pool($T), capacity: int, allocator := context.allocator) {
	assert(capacity > 0 && capacity < int(SENTINEL), "capacity must be greater than 0 and less than SENTINEL")

	p.items = make([]T, capacity, allocator)
	p.dense_to_slot = make([]u32, capacity, allocator)
	p.slots = make([]Slot, capacity, allocator)
	p.count = 0
	p.free_head = 0
	p.free_tail = u32(capacity - 1)
	for i in 0..<capacity {
		p.slots[i].gen = 1
		p.slots[i].dense_idx = u32(i)
		p.slots[i].next = u32(i + 1)
	}
	p.slots[capacity - 1].next = SENTINEL
	p.allocator = allocator
}

// destroy releases the pool's arrays via the allocator stored at init.
// The pool is unusable afterwards; every outstanding handle is dead.
destroy :: proc(p: ^Handle_Pool($T)) {
	delete(p.items, p.allocator)
	delete(p.dense_to_slot, p.allocator)
	delete(p.slots, p.allocator)
}

// clear empties the pool without releasing memory: every LIVE slot's generation
// is bumped, the freelist is rebuilt, and
// count returns to 0. Every previously issued handle is stale afterwards.
clear :: proc(p: ^Handle_Pool($T)) {
	p.free_head = 0
	p.free_tail = u32(len(p.slots) - 1)
	for i in 0..<p.count {
		slot_idx := p.dense_to_slot[i]
		increment_gen(&p.slots[slot_idx])
	}
	for &slot, idx in p.slots {
		slot.dense_idx = u32(idx)
		slot.next = u32(idx + 1)
	}
	p.slots[len(p.slots) - 1].next = SENTINEL
	p.count = 0
}

// add stores `item` and returns its handle.
// Freelist empty (all slots live or retired) → (0, .Full).
add :: proc(p: ^Handle_Pool($T), item: T) -> (Handle, Handle_Error) {
	if p.free_head == SENTINEL {
		return 0, .Full
	}
	
	slot_idx := p.free_head
	slot := &p.slots[slot_idx]
	p.items[p.count] = item
	slot.dense_idx = p.count
	p.dense_to_slot[p.count] = slot_idx
	p.free_head = slot.next
	p.count += 1
	return pack_handle(slot_idx, slot.gen), .None
}

// remove deletes the item `h` refers to: the last dense item is swapped into
// the gap and its slot is patched via dense_to_slot; the freed slot's
// generation is bumped (wrap-to-0 ⇒ retired, else FIFO-enqueued).
// Invalid/stale/zero/garbage handle → .Invalid_Handle (never panics).
remove :: proc(p: ^Handle_Pool($T), h: Handle) -> Handle_Error {
	hole_idx, ok := resolve(p, h)
	if !ok {
		return .Invalid_Handle
	}

	slot_idx, _ := unpack_handle(h)
	last_idx := p.count - 1

	if hole_idx != last_idx {
		moved_slot := p.dense_to_slot[last_idx]
		p.items[hole_idx] = p.items[last_idx]
		p.slots[moved_slot].dense_idx = hole_idx
		p.dense_to_slot[hole_idx] = moved_slot
	}

	p.count -= 1
	overflow := increment_gen(&p.slots[slot_idx])
	if !overflow {
		p.slots[slot_idx].next = SENTINEL
		if p.free_head == SENTINEL {
			p.free_head = slot_idx
			p.free_tail = slot_idx
		} else {
			p.slots[p.free_tail].next = slot_idx
			p.free_tail = slot_idx
		}
	}

	return .None
}

// get returns a COPY of the item `h` refers to, or (T{}, .Invalid_Handle).
get :: proc(p: ^Handle_Pool($T), h: Handle) -> (item: T, error: Handle_Error) {
	dense_idx, ok := resolve(p, h)
	if !ok {
		error = .Invalid_Handle
		return
	}
	item = p.items[dense_idx]
	return
}

// get_ptr returns a pointer to the live item — a LOAN, valid only until the
// next remove/clear/destroy. Invalid handle → (nil, .Invalid_Handle).
get_ptr :: proc(p: ^Handle_Pool($T), h: Handle) -> (item: ^T, error: Handle_Error) {
	dense_idx, ok := resolve(p, h)
	if !ok {
		error = .Invalid_Handle
		return
	}
	item = &p.items[dense_idx]
	return
}

// has reports whether `h` currently resolves (in range, non-zero generation,
// generation matches). Garbage-safe.
has :: proc(p: ^Handle_Pool($T), h: Handle) -> bool {
	_, ok := resolve(p, h)
	return ok
}

// slice returns the live items, items[0:count] — dense iteration is a plain
// slice walk. Order is unspecified beyond the swap-with-last contract; the
// slice is invalidated by remove/clear/destroy.
slice :: proc(p: ^Handle_Pool($T)) -> []T {
	return p.items[:p.count]
}

@(private="file")
increment_gen :: proc(slot: ^Slot) -> (overflow: bool) {
	slot.gen, overflow = intrinsics.overflow_add(slot.gen, 1)
	if overflow {
		slot.gen = 0
	}
	return
}

@(private="file")
pack_handle :: proc(idx, gen: u32) -> Handle {
	return Handle(u64(gen) << 32 | u64(idx))
}

@(private="file")
unpack_handle :: proc(h: Handle) -> (idx, gen: u32) {
	idx = u32(h & 0xFFFF_FFFF)
	gen = u32(h >> 32)
	return
}

@(private="file")
resolve :: proc(p: ^Handle_Pool($T), h: Handle) -> (dense_idx: u32, ok: bool) {
	slot_idx, gen := unpack_handle(h)
	if int(slot_idx) >= len(p.items) || gen == 0 || gen != p.slots[slot_idx].gen {
		ok = false
		return
	}
	return p.slots[slot_idx].dense_idx, true
}