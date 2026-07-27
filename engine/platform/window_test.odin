#+private file
package platform

// Tier 1 — pure logic over package internals, under `odin test`.
//
// NOTHING HERE MAY TOUCH THE WINDOW SYSTEM. `core:testing` dispatches every `@(test)`
// onto a `thread.Pool` worker, and SDL's video subsystem is main-thread-only on macOS,
// so `init()` returns .Init_Failed inside this runner by construction. Anything needing
// a live window belongs in `tests/platform`, which is a `main()` for that reason.
//
// `test_shutdown_survives_unclosable_window` used to live here. It asserted that a window
// whose NATIVE destroy fails is still evicted by shutdown — a Win32 concern
// (`DestroyWindow` returns BOOL). `SDL_DestroyWindow` returns void and cannot fail, so
// the premise is gone; the surviving contract, "shutdown stales outstanding handles", is
// asserted against a real window by `window/shutdown_stales_handles` in tier 2.

import "core:testing"

@(test)
test_zii_desc_defaults_are_pure :: proc(t: ^testing.T) {
	zii := get_desc_or_default({})
	testing.expect_value(t, zii.title, DEFAULT_TITLE)
	testing.expect_value(t, zii.width, i32(DEFAULT_WIDTH))
	testing.expect_value(t, zii.height, i32(DEFAULT_HEIGHT))
	testing.expect(t, !zii.hidden, "a zero-value desc must describe a VISIBLE window")

	explicit := get_desc_or_default({title = "odyne-test", width = 640, height = 360})
	testing.expect_value(t, explicit.title, "odyne-test")
	testing.expect_value(t, explicit.width, i32(640))
	testing.expect_value(t, explicit.height, i32(360))

	negative := get_desc_or_default({width = -1, height = 0})
	testing.expect_value(t, negative.width, i32(DEFAULT_WIDTH))
	testing.expect_value(t, negative.height, i32(DEFAULT_HEIGHT))

	// `hidden` has no default to apply, so it must pass through untouched — the bug this
	// guards is defaulting dropping the field entirely and silently showing every window.
	testing.expect(t, get_desc_or_default({hidden = true}).hidden, "hidden must survive defaulting")
}
