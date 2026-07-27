package main

// odyne platform test harness — tier 2.
//
// WHY THIS EXISTS AND NOT `odin test`
//
// `core:testing` runs every test on a `thread.Pool` worker (core/testing/runner.odin:393).
// SDL's video subsystem is main-thread-only on macOS — AppKit refuses to instantiate an
// NSWindow off the main thread — so no `@(test)` procedure can ever hold a real window
// there. That is a property of the RUNNER, not of macOS —
// and it is why GLFW's `tests/` and SDL's `test/testautomation.c` are both plain `main()`
// programs rather than unit-test suites [[GLFW]](https://github.com/glfw/glfw/tree/master/tests)
// [[SDL]](https://github.com/libsdl-org/SDL/blob/main/test/testautomation.c).
//
// So: this is a `main()`. Everything here runs on the main thread, with real windows, on
// both platforms. `testing.expect*` works verbatim outside the runner — those procedures
// only call `log.error` and return a bool (core/testing/testing.odin:110-134); `error_count`
// is incremented by the LOGGER (core/testing/logging.odin:51). The runner below replaces
// `core:testing`'s, and test bodies are byte-identical to what `@(test)` procedures contain.
//
// WHAT THIS DELIBERATELY CANNOT DO
//
// This package is `main`, not `platform`. It sees the PUBLIC surface only — no
// `Window_State`, no `g_window_pool`, no `record_key`, no `get_state`. That is the point:
// a test that cannot reach the representation can only assert the contract. Anything needing
// package internals (the `Button_State` edge algebra, the `kVK`/scancode decode tables) is
// pure logic that needs no window, and belongs in `odin test engine/platform` — tier 1.
//
// ISOLATION
//
// By default each case runs in its own CHILD PROCESS (the harness re-executes itself with
// `--case=`), so a segfault in a half-written backend costs one case instead of the run —
// stronger isolation than `odin test`'s threads, which share an address space. Pass
// `--in-process` for one process and a faster run once things are green.
//
//   odin build tests/platform -collection:engine=engine -out:build/platform-tests
//   ./build/platform-tests                    # all cases, isolated
//   ./build/platform-tests close resize       # substring filters
//   ./build/platform-tests --in-process       # one process, no isolation
//   ./build/platform-tests --case=window/lifecycle
//
// Exit code is non-zero if any case failed, so this is CI-usable.

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

Test_Case :: struct {
	name: string,
	run:  proc(t: ^testing.T),
}

all_cases :: proc(allocator := context.allocator) -> [dynamic]Test_Case {
	cases := make([dynamic]Test_Case, allocator)
	append(&cases, ..PORTABLE_WINDOW_TESTS)
	append(&cases, ..PORTABLE_INPUT_TESTS)
	append(&cases, ..WIRING_TESTS)
	return cases
}

// counting_logger_proc is the whole reason test bodies need no edits: it is the piece
// `core:testing` normally supplies, reduced to the part that matters.
counting_logger_proc :: proc(
	data: rawptr,
	level: runtime.Logger_Level,
	text: string,
	options: runtime.Logger_Options,
	location := #caller_location,
) {
	t := cast(^testing.T)data
	if level < .Error {
		return
	}
	t.error_count += 1
	file := location.file_path
	if idx := strings.last_index_any(file, "/\\"); idx >= 0 {
		file = file[idx + 1:]
	}
	fmt.printfln("        %s(%d) %s", file, location.line, text)
}

// run_case executes one case in THIS process and reports whether it failed.
run_case :: proc(tc: Test_Case, base_allocator: mem.Allocator) -> (failed: bool) {
	// Per-case leak tracking, mirroring what the real runner gives us. Without this the
	// harness would silently lose the check that caught init()'s pool leak.
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, base_allocator)
	defer mem.tracking_allocator_destroy(&track)

	t: testing.T
	context.allocator = mem.tracking_allocator(&track)
	context.logger = log.Logger {
		procedure    = counting_logger_proc,
		data         = &t,
		lowest_level = .Debug,
		options      = {},
	}

	tc.run(&t)

	for _, entry in track.allocation_map {
		fmt.printfln("        LEAK %v bytes @ %v", entry.size, entry.location)
	}
	for entry in track.bad_free_array {
		fmt.printfln("        BAD FREE @ %v", entry.location)
	}

	return t.error_count != 0 ||
		len(track.allocation_map) != 0 ||
		len(track.bad_free_array) != 0
}

// run_case_isolated re-executes this binary for a single case, so a crash is contained.
// Returns the child's verdict; a signal death is reported as a failure with its code.
run_case_isolated :: proc(tc: Test_Case) -> (failed: bool) {
	state, stdout, stderr, err := os.process_exec(
		{command = {os.args[0], fmt.tprintf("--case=%s", tc.name)}},
		context.allocator,
	)
	defer delete(stdout)
	defer delete(stderr)

	if err != nil {
		fmt.printfln("        HARNESS: could not spawn a child for this case: %v", err)
		return true
	}

	os.write(os.stdout, stdout)
	os.write(os.stderr, stderr)

	if !state.success && state.exit_code > 1 {
		// 139 = SIGSEGV, 134 = SIGABRT (an uncaught NSException lands here).
		fmt.printfln("        CRASHED (exit %v) — the backend faulted inside this case", state.exit_code)
		return true
	}
	return state.exit_code != 0
}

report :: proc(name: string, failed: bool) {
	fmt.printfln("  %-52s %s", name, failed ? "FAIL" : "ok")
}

main :: proc() {
	os.exit(run() == 0 ? 0 : 1)
}

// run is separated from main so its defers are reachable — `os.exit` diverges, and Odin
// rejects a defer that can never fire.
run :: proc() -> (failures: int) {
	base_allocator := context.allocator

	cases := all_cases()
	defer delete(cases)

	// Child mode: run exactly one case and let the exit code carry the verdict.
	for arg in os.args[1:] {
		if !strings.has_prefix(arg, "--case=") {
			continue
		}
		want := arg[len("--case="):]
		for tc in cases {
			if tc.name == want {
				fmt.printfln("  %s", tc.name)
				failed := run_case(tc, base_allocator)
				report(tc.name, failed)
				return failed ? 1 : 0
			}
		}
		fmt.printfln("no such case: %s", want)
		return 1
	}

	in_process := false
	filters := make([dynamic]string)
	defer delete(filters)
	for arg in os.args[1:] {
		if arg == "--in-process" {
			in_process = true
			continue
		}
		append(&filters, arg)
	}

	selected := make([dynamic]Test_Case)
	defer delete(selected)
	for tc in cases {
		if len(filters) == 0 {
			append(&selected, tc)
			continue
		}
		for f in filters {
			if strings.contains(tc.name, f) {
				append(&selected, tc)
				break
			}
		}
	}

	fmt.printfln(
		"odyne platform tests — %d case%s on %v, main thread, real windows (%s)",
		len(selected),
		len(selected) == 1 ? "" : "s",
		ODIN_OS,
		in_process ? "one process" : "process per case",
	)

	for tc in selected {
		failed: bool
		if in_process {
			fmt.printfln("  %s", tc.name)
			failed = run_case(tc, base_allocator)
			report(tc.name, failed)
		} else {
			failed = run_case_isolated(tc)
		}
		if failed {
			failures += 1
		}
	}

	fmt.printfln("\n%d/%d passed, %d failed", len(selected) - failures, len(selected), failures)
	return
}
