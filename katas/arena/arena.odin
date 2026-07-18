package arena

import "base:intrinsics"
import "core:mem"

Arena :: struct {
	data:        []byte, // borrowed backing storage (not owned)
	offset:      int,    // bytes used; the next allocation aligns up from here
	prev_offset: int,    // start of the most recent allocation — enables the Resize fast path
	peak_used:   int,    // high-water mark of `offset`, for the measurement task
}

init :: proc(a: ^Arena, backing: []byte) {
	a.data = backing
	a.offset = 0
	a.prev_offset = 0
	a.peak_used = 0
}

allocator :: proc(a: ^Arena) -> mem.Allocator {
	return mem.Allocator{procedure = allocator_proc, data = rawptr(a)}
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
	arena := (^Arena)(allocator_data)
	switch mode {
	case .Alloc:
		return alloc(arena, size, alignment, true)
	case .Alloc_Non_Zeroed:
		return alloc(arena, size, alignment, false)
	case .Free:
		return nil, .Mode_Not_Implemented
	case .Free_All:
		free_all(arena)
		return nil, .None
	case .Resize:
		return resize(arena, old_memory, old_size, size, alignment, true)
	case .Resize_Non_Zeroed:
		return resize(arena, old_memory, old_size, size, alignment, false)
	case .Query_Features:
		set := (^mem.Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {.Alloc, .Alloc_Non_Zeroed, .Free_All, .Resize, .Resize_Non_Zeroed, .Query_Features}
		}
		return nil, .None
	case .Query_Info:
		return nil, .Mode_Not_Implemented
	}
	return nil, .Mode_Not_Implemented
}

@(private = "file")
align_forward :: proc(a: ^Arena, alignment: int) -> (int, bool) {
	assert(alignment > 0, "alignment must be positive")
	mask := uintptr(alignment - 1)
	assert(uintptr(alignment) & mask == 0, "alignment must be a power of two")

	base_ptr := uintptr(raw_data(a.data))
	curr_ptr := base_ptr + uintptr(a.offset)

	aligned_ptr, ok := safe_add(curr_ptr, mask)
	if !ok {
		return 0, false
	}
	aligned_ptr &= ~mask
	return int(aligned_ptr - base_ptr), true
}

@(private = "file", require_results)
safe_add :: #force_inline proc "contextless" (a, b: $T) -> (T, bool) {
	val, overflowed := intrinsics.overflow_add(a, b)
	return val, !overflowed
}

alloc :: proc(a: ^Arena, size: int, alignment: int, zero: bool) -> (data: []byte, err: mem.Allocator_Error) {
	assert(size >= 0, "size must be non-negative")

	aligned_offset, ok := align_forward(a, alignment)
	if !ok {
		err = .Out_Of_Memory
		return
	}

	offset, offset_ok := safe_add(aligned_offset, size)
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

resize :: proc(a: ^Arena, old_memory: rawptr, old_size: int, size: int, alignment: int, zero: bool) -> (data: []byte, err: mem.Allocator_Error) {
	old_data := ([^]byte)(old_memory)

	if old_data == nil {
		return alloc(a, size, alignment, zero)
	}

	if uintptr(old_data) == uintptr(raw_data(a.data)) + uintptr(a.prev_offset) {
		offset, ok := safe_add(a.prev_offset, size)
		if !ok ||offset > len(a.data) {
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

	new_memory := alloc(a, size, alignment, zero) or_return
	copy(new_memory, old_data[:old_size])
	return new_memory, nil
}

free_all :: proc(a: ^Arena) {
	a.offset = 0
	a.prev_offset = 0
	a.peak_used = 0
}
