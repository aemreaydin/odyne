package memory

import "base:intrinsics"
import "core:mem"

/*
Linear bump allocator over a borrowed buffer. Frees only all at once; the buffer is not
owned and must outlive the arena.
*/
Arena :: struct {
	data:        []byte, // borrowed backing storage (not owned)
	offset:      int, // bytes used; the next allocation aligns up from here
	prev_offset: int, // start of the most recent allocation — enables the Resize fast path
	peak_used:   int, // high-water mark of `offset`
}

// Points the arena at `backing`, which it borrows and does not own.
arena_init :: proc(a: ^Arena, backing: []byte) {
	a.data = backing
	a.offset = 0
	a.prev_offset = 0
	a.peak_used = 0
}

// The allocator value to assign to `context.allocator` or pass to `make`.
arena_allocator :: proc(a: ^Arena) -> mem.Allocator {
	return mem.Allocator{procedure = arena_allocator_proc, data = rawptr(a)}
}

// `.Free` is unsupported — an arena cannot release one allocation. A request that does not
// fit returns `.Out_Of_Memory`.
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

/*
Bump-allocates from the arena.

Inputs:
- size: bytes requested; must be non-negative, and the arena does not grow
- alignment: must be a power of two
- zero: whether the returned bytes are zeroed

Returns:
- data: the allocation, or nil
- err: `.Out_Of_Memory` if the request does not fit
*/
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

/*
Grows or shrinks an allocation. Resizing the most recent allocation is done in place;
anything older is reallocated and copied, leaving the original bytes stranded.

Inputs:
- old_memory: the allocation to resize; nil allocates fresh
- old_size: its current size, used to bound the copy
- size: the requested new size
- alignment: must be a power of two
- zero: whether bytes beyond `old_size` are zeroed

Returns:
- data: the resized allocation, or nil
- err: `.Out_Of_Memory` if the request does not fit
*/
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

// Rewinds the arena to empty. Every outstanding allocation is invalid afterwards.
arena_free_all :: proc(a: ^Arena) {
	a.offset = 0
	a.prev_offset = 0
	a.peak_used = 0
}


/*
Fixed-size block allocator over a borrowed buffer, which is not owned and must outlive the
pool. Free blocks are tracked by an intrusive list living inside the free blocks
themselves, so the pool needs no side storage. A block is valid until it is freed or
`pool_free_all` is called.
*/
Pool :: struct {
	data:       []byte, // borrowed backing storage (not owned)
	block_size: int, // effective slot stride: align_up(max(requested, size_of(rawptr)), alignment)
	alignment:  int,
	head:       ^Free_Node, // first free block, or nil when the pool is exhausted
	free_count: int, // free blocks remaining (stats/debug)
}

// Overlays the first bytes of a free block; once allocated those bytes are the caller's.
// This is why a block must be at least `size_of(rawptr)`.
@(private = "file")
Free_Node :: struct {
	next: ^Free_Node,
}

/*
Carves `backing` into fixed-size blocks and threads them into the free list. The buffer is
borrowed, not owned.

Inputs:
- backing: storage to carve; must fit at least one aligned block
- block_size: bytes per block, rounded up to `size_of(rawptr)` and to `alignment`
- alignment: must be a power of two; the first block starts at the next aligned address
*/
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

// The allocator value to assign to `context.allocator` or pass to `make`.
pool_allocator :: proc(p: ^Pool) -> mem.Allocator {
	return mem.Allocator{procedure = pool_allocator_proc, data = p}
}

// Resize is unsupported — blocks are fixed size. A request larger than one block is
// `.Invalid_Argument` (a caller bug); an exhausted free list is `.Out_Of_Memory`.
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

// Pops one free block and returns its first `size` bytes, which must be in `1..=block_size`.
// Zeroing overwrites the stale free-list link the block still carries.
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

// Returns a block this pool handed out to the free list, in O(1). Freeing a foreign or
// already-freed pointer corrupts the list.
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

// Returns every block to the free list. Every outstanding block is invalid afterwards.
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
