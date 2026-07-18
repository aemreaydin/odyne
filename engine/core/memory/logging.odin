package memory

import "core:fmt"
import "core:mem"

// Logging_Allocator wraps another allocator and prints every operation it performs — a
// drop-in debug lens over any allocator (heap, arena, pool):
//
//	log: memory.Logging_Allocator
//	memory.logging_allocator_init(&log, context.allocator, "frame")
//	context.allocator = memory.logging_allocator(&log)
//	// ... every new/make/free now prints mode, size, alignment, caller, result ...
//
// It owns no memory and keeps no allocation records of its own; it observes each call and
// forwards it to `backing`. (Contrast the Tracking_Allocator, which records live allocations
// to detect leaks — this one just narrates, in real time, with the caller location.)
Logging_Allocator :: struct {
	backing: mem.Allocator, // the real allocator every call is forwarded to
	label:   string, // printed on each line so you can tell multiple loggers apart
}

// logging_allocator_init wires the logger to forward to `backing`.
logging_allocator_init :: proc(l: ^Logging_Allocator, backing: mem.Allocator, label := "mem") {
	l.backing = backing
	l.label = label
}

// logging_allocator returns the Allocator value to assign to context.allocator.
logging_allocator :: proc(l: ^Logging_Allocator) -> mem.Allocator {
	return mem.Allocator{procedure = logging_allocator_proc, data = l}
}

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
		"[%s] %-16v size=%-4s align=%-2s len=%-4s  ptr=%-12s  err=%v  %v",
		l.label,
		mode,
		fmt.tprintf("%d", size),
		fmt.tprintf("%d", alignment),
		fmt.tprintf("%d", len(result)),
		fmt.tprintf("%p", raw_data(result)),
		err,
		location,
	)
	return result, err
}
