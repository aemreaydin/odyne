package memory

// engine:core/memory — fixed-backing allocators (graduated from katas m02-02..m02-04):
//
//	Arena — linear bump allocator over a borrowed buffer; frees only all-at-once
//	Pool  — fixed-size block allocator with an intrusive free list over a borrowed buffer
//
// Both implement Odin's mem.Allocator contract through arena_allocator / pool_allocator;
// neither owns its backing memory — the caller's buffer must outlive the allocator.
// (Logging_Allocator, the debug wrapper, lives in logging.odin.)

import "base:intrinsics"
import "core:mem"

// ── arena (graduating from m02-02) ───────────────────────────────────────────

Arena :: struct {
	data:        []byte, // borrowed backing storage (not owned)
	offset:      int, // bytes used; the next allocation aligns up from here
	prev_offset: int, // start of the most recent allocation — enables the Resize fast path
	peak_used:   int, // high-water mark of `offset`, for the measurement task
}

arena_init :: proc(a: ^Arena, backing: []byte) {
	a.data = backing
	a.offset = 0
	a.prev_offset = 0
	a.peak_used = 0
}

arena_allocator :: proc(a: ^Arena) -> mem.Allocator {
	return mem.Allocator{procedure = arena_allocator_proc, data = rawptr(a)}
}

// allocator_proc is the arena's implementation of Odin's Allocator_Proc contract: one
// procedure that recovers the ^Arena from `allocator_data` and switches on `mode`. This
// is the core deliverable of the kata. Per-mode contract (see design.md for the table):
//
//	.Alloc             align the ABSOLUTE address raw_data(data)+offset up to `alignment`,
//	                   bump past it, update peak_used, ZERO the bytes; return (slice, .None)
//	.Alloc_Non_Zeroed  same, but do not zero
//	.Free              return (nil, .Mode_Not_Implemented) — an arena can't free one allocation
//	.Free_All          offset = 0; prev_offset = 0; return (nil, .None)
//	.Resize / .Resize_Non_Zeroed
//	                   if old_memory is the most-recent alloc (== raw_data(data)+prev_offset),
//	                   grow/shrink in place; otherwise alloc-new + copy the old bytes
//	.Query_Features    fill (^mem.Allocator_Mode_Set)(old_memory) with the modes you support
//	.Query_Info        return (nil, .Mode_Not_Implemented)
//
// A request that does not fit returns (nil, .Out_Of_Memory).
@(private)
arena_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	arena := (^Arena)(allocator_data)
	switch mode {
	case .Alloc:
		return arena_alloc(arena, size, alignment, true)
	case .Alloc_Non_Zeroed:
		return arena_alloc(arena, size, alignment, false)
	case .Free:
		return nil, .Mode_Not_Implemented
	case .Free_All:
		arena_free_all(arena)
		return nil, .None
	case .Resize:
		return arena_resize(arena, old_memory, old_size, size, alignment, true)
	case .Resize_Non_Zeroed:
		return arena_resize(arena, old_memory, old_size, size, alignment, false)
	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {
				.Alloc,
				.Alloc_Non_Zeroed,
				.Free_All,
				.Resize,
				.Resize_Non_Zeroed,
				.Query_Features,
			}
		}
		return nil, .None
	case .Query_Info:
		return nil, .Mode_Not_Implemented
	}
	return nil, .Mode_Not_Implemented
}

@(private = "file")
arena_align_forward :: proc(a: ^Arena, alignment: int) -> (int, bool) {
	assert(alignment > 0, "alignment must be positive")
	mask := uintptr(alignment - 1)
	assert(uintptr(alignment) & mask == 0, "alignment must be a power of two")

	base_ptr := uintptr(raw_data(a.data))
	curr_ptr := base_ptr + uintptr(a.offset)

	aligned_ptr, ok := arena_safe_add(curr_ptr, mask)
	if !ok {
		return 0, false
	}
	aligned_ptr &= ~mask
	return int(aligned_ptr - base_ptr), true
}

@(private = "file", require_results)
arena_safe_add :: #force_inline proc "contextless" (a, b: $T) -> (T, bool) {
	val, overflowed := intrinsics.overflow_add(a, b)
	return val, !overflowed
}

arena_alloc :: proc(
	a: ^Arena,
	size: int,
	alignment: int,
	zero: bool,
) -> (
	data: []byte,
	err: mem.Allocator_Error,
) {
	assert(size >= 0, "size must be non-negative")

	aligned_offset, ok := arena_align_forward(a, alignment)
	if !ok {
		err = .Out_Of_Memory
		return
	}

	offset, offset_ok := arena_safe_add(aligned_offset, size)
	if !offset_ok || offset > len(a.data) {
		err = .Out_Of_Memory
		return
	}

	a.prev_offset = aligned_offset
	a.offset = offset
	a.peak_used = max(a.peak_used, offset)

	data = a.data[aligned_offset:offset]
	if zero {
		mem.zero_slice(data)
	}
	return
}

arena_resize :: proc(
	a: ^Arena,
	old_memory: rawptr,
	old_size: int,
	size: int,
	alignment: int,
	zero: bool,
) -> (
	data: []byte,
	err: mem.Allocator_Error,
) {
	old_data := ([^]byte)(old_memory)

	if old_data == nil {
		return arena_alloc(a, size, alignment, zero)
	}

	if uintptr(old_data) == uintptr(raw_data(a.data)) + uintptr(a.prev_offset) {
		offset, ok := arena_safe_add(a.prev_offset, size)
		if !ok || offset > len(a.data) {
			err = .Out_Of_Memory
			return
		}

		a.offset = offset
		a.peak_used = max(a.peak_used, offset)
		data = a.data[a.prev_offset:a.offset]
		if zero {
			mem.zero_slice(data[min(old_size, size):])
		}
		return
	}

	new_memory := arena_alloc(a, size, alignment, zero) or_return
	copy(new_memory, old_data[:old_size])
	return new_memory, nil
}

arena_free_all :: proc(a: ^Arena) {
	a.offset = 0
	a.prev_offset = 0
	a.peak_used = 0
}


// ── pool (graduating from m02-03) ────────────────────────────────────────────

// Pool is a fixed-size block allocator over a borrowed, fixed backing buffer. It owns
// none of `data`: the caller's buffer must outlive the pool. Free blocks are tracked by
// an intrusive singly-linked list whose links live inside the free blocks themselves
// (`Free_Node` overlaid on each free block). A block is valid until it is freed or
// free_all is called.
Pool :: struct {
	data:       []byte, // borrowed backing storage (not owned)
	block_size: int, // effective slot stride: align_up(max(requested, size_of(rawptr)), alignment)
	alignment:  int,
	head:       ^Free_Node, // first free block, or nil when the pool is exhausted
	free_count: int, // free blocks remaining (stats/debug)
}

// Free_Node overlays the first bytes of a *free* block; when the block is allocated,
// those same bytes are the caller's. This is why a block must be >= size_of(rawptr).
@(private = "file")
Free_Node :: struct {
	next: ^Free_Node,
}

pool_init :: proc(p: ^Pool, backing: []byte, block_size: int, alignment: int) {
	aligned := mem.align_forward_uintptr(uintptr(raw_data(backing)), uintptr(alignment))
	pad := int(aligned - uintptr(raw_data(backing)))
	stride := mem.align_forward_int(max(block_size, size_of(rawptr)), alignment)
	assert(pad + stride <= len(backing), "pool data is too small to fit the block size")

	p.data = backing[pad:]
	p.block_size = stride
	p.alignment = alignment
	pool_thread_free_list(p)
}

pool_allocator :: proc(p: ^Pool) -> mem.Allocator {
	return mem.Allocator{procedure = pool_allocator_proc, data = p}
}

// allocator_proc is the pool's implementation of Odin's Allocator_Proc contract: recover
// the ^Pool from `allocator_data` and switch on `mode`. Per-mode contract (see design.md):
//
//	.Alloc             pop the head block; zero it; return `size` bytes, .None
//	.Alloc_Non_Zeroed  pop the head block, no zeroing; return `size` bytes, .None
//	                   size > block_size → (nil, .Invalid_Argument)   [caller bug]
//	                   free list empty   → (nil, .Out_Of_Memory)      [transient]
//	.Free              push old_memory's block onto the free list; return (nil, .None)
//	.Free_All          re-thread the whole buffer into a fresh free list; (nil, .None)
//	.Resize / .Resize_Non_Zeroed  not supported → (nil, .Mode_Not_Implemented)
//	.Query_Features    fill (^mem.Allocator_Mode_Set)(old_memory) with
//	                   {.Alloc, .Alloc_Non_Zeroed, .Free, .Free_All, .Query_Features}
//	.Query_Info        (nil, .Mode_Not_Implemented)
@(private)
pool_allocator_proc :: proc(
	allocator_data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	p := (^Pool)(allocator_data)
	#partial switch mode {
	case .Alloc:
		return pool_alloc(p, size, alignment, true)
	case .Alloc_Non_Zeroed:
		return pool_alloc(p, size, alignment, false)
	case .Free:
		pool_free_block(p, old_memory)
		return nil, .None
	case .Free_All:
		pool_free_all(p)
		return nil, .None
	case .Resize:
		return nil, .Mode_Not_Implemented
	case .Resize_Non_Zeroed:
		return nil, .Mode_Not_Implemented
	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Free_All, .Query_Features}
		}
		return nil, .None
	case .Query_Info:
		return nil, .Mode_Not_Implemented
	}
	return nil, .Mode_Not_Implemented
}

// alloc pops one free block and returns its first `size` bytes. `.Alloc` zeroes them
// (overwriting the stale free-list link left in the block); `.Alloc_Non_Zeroed` does not.
// `size` must be in 1..=block_size — a larger request is .Invalid_Argument, and an empty
// pool is .Out_Of_Memory.
pool_alloc :: proc(
	p: ^Pool,
	size: int,
	alignment: int,
	zero: bool,
) -> (
	data: []byte,
	err: mem.Allocator_Error,
) {
	if size == 0 {
		return
	}
	if size < 0 || size > p.block_size {
		err = .Invalid_Argument
		return
	}
	if alignment <= 0 || alignment > p.alignment {
		err = .Invalid_Argument
		return
	}

	if p.free_count == 0 {
		err = .Out_Of_Memory
		return
	}

	block := p.head
	p.head = block.next
	p.free_count -= 1

	data = mem.byte_slice(block, size)
	if zero {
		mem.zero_slice(data)
	}
	return
}

// free_block returns `block` (a pointer this pool handed out) to the free list in O(1).
// The address must lie inside the pool's backing; freeing a foreign or already-freed
// pointer corrupts the list. This is the allocator's .Free path.
pool_free_block :: proc(p: ^Pool, block: rawptr) {
	assert(
		uintptr(block) >= uintptr(raw_data(p.data)) &&
		uintptr(block) < uintptr(raw_data(p.data)) + uintptr(len(p.data)),
		"block must be within the pool's data",
	)
	assert(
		(uintptr(block) - uintptr(raw_data(p.data))) % uintptr(p.block_size) == 0,
		"block must be aligned to the block size",
	)
	block := (^Free_Node)(block)
	block.next = p.head
	p.head = block
	p.free_count += 1
}

pool_free_all :: proc(p: ^Pool) {
	pool_thread_free_list(p)
}

@(private = "file")
pool_thread_free_list :: proc(p: ^Pool) {
	p.free_count = len(p.data) / p.block_size
	p.head = nil

	for i in 0 ..< p.free_count {
		block := (^Free_Node)(&p.data[i * p.block_size])
		block.next = p.head
		p.head = block
	}
}
