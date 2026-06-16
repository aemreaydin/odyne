package core

import "core:testing"

@(test)
test_version_matches_constant :: proc(t: ^testing.T) {
	testing.expect_value(t, version(), VERSION)
}

@(test)
test_version_is_nonempty :: proc(t: ^testing.T) {
	testing.expect(t, len(version()) > 0, "engine version must not be empty")
}

