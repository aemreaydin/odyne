package pool

import "core:mem"

// Pool is a fixed-size block allocator over a borrowed, fixed backing buffer. It owns
// none of `data`: the caller's buffer must outlive the pool. Free blocks are tracked by
// an intrusive singly-linked list whose links live inside the free blocks themselves
// (`Free_Node` overlaid on each free block). A block is valid until it is freed or
// free_all is called.
Pool :: struct {
	data:       []byte,     // borrowed backing storage (not owned)
	block_size: int,        // effective slot stride: align_up(max(requested, size_of(rawptr)), alignment)
	alignment: int,
	head:       ^Free_Node, // first free block, or nil when the pool is exhausted
	free_count: int,        // free blocks remaining (stats/debug)
}

// Free_Node overlays the first bytes of a *free* block; when the block is allocated,
// those same bytes are the caller's. This is why a block must be >= size_of(rawptr).
@(private = "file")
Free_Node :: struct {
	next: ^Free_Node,
}

init :: proc(p: ^Pool, backing: []byte, block_size: int, alignment: int) {
	aligned := mem.align_forward_uintptr(uintptr(raw_data(backing)), uintptr(alignment))
	pad := int(aligned - uintptr(raw_data(backing)))
	stride := mem.align_forward_int(max(block_size, size_of(rawptr)), alignment)
	assert(pad + stride <= len(backing), "pool data is too small to fit the block size")

	p.data = backing[pad:]
	p.block_size = stride
	p.alignment = alignment
	thread_free_list(p)
}

allocator :: proc(p: ^Pool) -> mem.Allocator {
	return mem.Allocator{procedure = allocator_proc, data = p}
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
allocator_proc :: proc(
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
		return alloc(p, size, alignment, true)
	case .Alloc_Non_Zeroed:
		return alloc(p, size, alignment, false)
	case .Free:
		free_block(p, old_memory)
		return nil, .None
	case .Free_All:
		free_all(p)
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
alloc :: proc(p: ^Pool, size: int, alignment: int, zero: bool) -> (data: []byte, err: mem.Allocator_Error) {
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
free_block :: proc(p: ^Pool, block: rawptr) {
	assert(uintptr(block) >= uintptr(raw_data(p.data)) && uintptr(block) < uintptr(raw_data(p.data)) + uintptr(len(p.data)), "block must be within the pool's data")
	assert((uintptr(block) - uintptr(raw_data(p.data))) % uintptr(p.block_size) == 0, "block must be aligned to the block size")
	block := (^Free_Node)(block)
	block.next = p.head
	p.head = block
	p.free_count += 1
}

free_all :: proc(p: ^Pool) {
	thread_free_list(p)
}

@(private = "file")
thread_free_list :: proc(p: ^Pool) {
	p.free_count = len(p.data) / p.block_size
	p.head = nil

	for i in 0..<p.free_count {
		block := (^Free_Node)(&p.data[i * p.block_size])
		block.next = p.head
		p.head = block
	}
}