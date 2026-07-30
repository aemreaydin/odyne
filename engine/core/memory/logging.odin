package memory

import "core:fmt"
import "core:mem"

/*
Wraps another allocator and prints every operation it performs. It owns no memory and keeps
no records; it narrates each call and forwards it to `backing`. To detect leaks rather than
watch traffic, use `mem.Tracking_Allocator` instead.

Example:

	log: memory.Logging_Allocator
	memory.logging_allocator_init(&log, context.allocator, "frame")
	context.allocator = memory.logging_allocator(&log)
*/
Logging_Allocator :: struct {
	backing: mem.Allocator, // the real allocator every call is forwarded to
	label:   string, // printed on each line, to tell multiple loggers apart
}

// Wires the logger to forward to `backing`.
logging_allocator_init :: proc(l: ^Logging_Allocator, backing: mem.Allocator, label := "mem") {
	l.backing = backing
	l.label = label
}

// The allocator value to assign to `context.allocator`.
logging_allocator :: proc(l: ^Logging_Allocator) -> mem.Allocator {
	return mem.Allocator{procedure = logging_allocator_proc, data = l}
}

@(private)
logging_allocator_proc :: proc(
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
	l := (^Logging_Allocator)(allocator_data)
	result, err := l.backing.procedure(
		l.backing.data,
		mode,
		size,
		alignment,
		old_memory,
		old_size,
		location,
	)
	fmt.printfln(
		"[%s] %-16v size=%-4d align=%-2d len=%-4d  ptr=%-12p  err=%v  %v",
		l.label,
		mode,
		size,
		alignment,
		len(result),
		raw_data(result),
		err,
		location,
	)
	return result, err
}
