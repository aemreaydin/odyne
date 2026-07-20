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
	// TODO(you) — m03-02
	_ = p
	_ = capacity
	_ = allocator
}

// destroy releases the pool's arrays via the allocator stored at init.
// The pool is unusable afterwards; every outstanding handle is dead.
destroy :: proc(p: ^Handle_Pool($T)) {
	// TODO(you) — m03-02
	_ = p
}

// clear empties the pool without releasing memory: every LIVE slot's generation
// is bumped (same retire-on-wrap rule as remove), the freelist is rebuilt, and
// count returns to 0. Every previously issued handle is stale afterwards.
clear :: proc(p: ^Handle_Pool($T)) {
	// TODO(you) — m03-02
	_ = p
}

// add stores `item` and returns its handle.
// Freelist empty (all slots live or retired) → (0, .Full).
add :: proc(p: ^Handle_Pool($T), item: T) -> (Handle, Handle_Error) {
	// TODO(you) — m03-02
	_ = p
	_ = item
	return 0, .None
}

// remove deletes the item `h` refers to: the last dense item is swapped into
// the gap and its slot is patched via dense_to_slot; the freed slot's
// generation is bumped (wrap-to-0 ⇒ retired, else FIFO-enqueued).
// Invalid/stale/zero/garbage handle → .Invalid_Handle (never panics).
remove :: proc(p: ^Handle_Pool($T), h: Handle) -> Handle_Error {
	// TODO(you) — m03-02
	_ = p
	_ = h
	return .None
}

// get returns a COPY of the item `h` refers to, or (T{}, .Invalid_Handle).
get :: proc(p: ^Handle_Pool($T), h: Handle) -> (T, Handle_Error) {
	// TODO(you) — m03-02
	_ = p
	_ = h
	return {}, .None
}

// get_ptr returns a pointer to the live item — a LOAN, valid only until the
// next remove/clear/destroy. Invalid handle → (nil, .Invalid_Handle).
get_ptr :: proc(p: ^Handle_Pool($T), h: Handle) -> (^T, Handle_Error) {
	// TODO(you) — m03-02
	_ = p
	_ = h
	return nil, .None
}

// has reports whether `h` currently resolves (in range, non-zero generation,
// generation matches). Garbage-safe.
has :: proc(p: ^Handle_Pool($T), h: Handle) -> bool {
	// TODO(you) — m03-02
	_ = p
	_ = h
	return false
}

// slice returns the live items, items[0:count] — dense iteration is a plain
// slice walk. Order is unspecified beyond the swap-with-last contract; the
// slice is invalidated by remove/clear/destroy.
slice :: proc(p: ^Handle_Pool($T)) -> []T {
	// TODO(you) — m03-02
	_ = p
	return nil
}
