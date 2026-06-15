package odin_warmup

// Failing tests for the m00-02 warm-up katas. These compile against the stubs
// in warmup.odin and FAIL (the stubs call unimplemented()). Implement the
// bodies until every test passes and the per-test leak check reports 0 leaks.
//
// Run:  odin test katas/odin_warmup
//
// This file is your template for every later kata — note the @(test) attribute,
// the ^testing.T parameter, and the expect / expect_value helpers.

import "core:testing"

// ── find ─────────────────────────────────────────────────────────────────

@(test)
test_find_hit :: proc(t: ^testing.T) {
	xs := []int{10, 20, 30, 40}
	idx, found := find(xs, 30)
	testing.expect(t, found, "expected to find 30")
	testing.expect_value(t, idx, 2)
}

@(test)
test_find_first :: proc(t: ^testing.T) {
	xs := []int{7, 7, 7}
	idx, found := find(xs, 7)
	testing.expect(t, found)
	testing.expect_value(t, idx, 0) // first match wins
}

@(test)
test_find_miss :: proc(t: ^testing.T) {
	xs := []int{1, 2, 3}
	_, found := find(xs, 99)
	testing.expect(t, !found, "99 is not present, found must be false")
}

@(test)
test_find_empty :: proc(t: ^testing.T) {
	xs := []int{}
	_, found := find(xs, 1)
	testing.expect(t, !found, "nothing is present in an empty slice")
}

@(test)
test_find_parapoly_bytes :: proc(t: ^testing.T) {
	// Same procedure, different element type — exercises parapoly.
	bs := []u8{'a', 'b', 'c'}
	idx, found := find(bs, u8('b'))
	testing.expect(t, found)
	testing.expect_value(t, idx, 1)
}

// ── reverse ────────────────────────────────────────────────────────────────

@(test)
test_reverse_even :: proc(t: ^testing.T) {
	arr := [4]int{1, 2, 3, 4}
	reverse(arr[:]) // mutates the caller's backing array through the view
	testing.expect(t, arr == [4]int{4, 3, 2, 1}, "even-length reverse")
}

@(test)
test_reverse_odd :: proc(t: ^testing.T) {
	arr := [5]int{1, 2, 3, 4, 5}
	reverse(arr[:])
	testing.expect(t, arr == [5]int{5, 4, 3, 2, 1}, "odd-length keeps the middle fixed")
}

@(test)
test_reverse_single :: proc(t: ^testing.T) {
	arr := [1]int{42}
	reverse(arr[:])
	testing.expect(t, arr == [1]int{42})
}

@(test)
test_reverse_empty :: proc(t: ^testing.T) {
	arr := [0]int{}
	reverse(arr[:]) // must not crash or read out of bounds
}

// ── parse_u32 ────────────────────────────────────────────────────────────────

@(test)
test_parse_zero :: proc(t: ^testing.T) {
	v, err := parse_u32("0")
	testing.expect_value(t, err, Parse_Error.None)
	testing.expect_value(t, v, u32(0))
}

@(test)
test_parse_basic :: proc(t: ^testing.T) {
	v, err := parse_u32("12345")
	testing.expect_value(t, err, Parse_Error.None)
	testing.expect_value(t, v, u32(12345))
}

@(test)
test_parse_max :: proc(t: ^testing.T) {
	v, err := parse_u32("4294967295") // max u32
	testing.expect_value(t, err, Parse_Error.None)
	testing.expect_value(t, v, u32(4294967295))
}

@(test)
test_parse_leading_zeros :: proc(t: ^testing.T) {
	v, err := parse_u32("007")
	testing.expect_value(t, err, Parse_Error.None)
	testing.expect_value(t, v, u32(7))
}

@(test)
test_parse_empty :: proc(t: ^testing.T) {
	_, err := parse_u32("")
	testing.expect_value(t, err, Parse_Error.Empty)
}

@(test)
test_parse_invalid_digit :: proc(t: ^testing.T) {
	_, err := parse_u32("12a3")
	testing.expect_value(t, err, Parse_Error.Invalid_Digit)
}

@(test)
test_parse_overflow_by_one :: proc(t: ^testing.T) {
	_, err := parse_u32("4294967296") // max u32 + 1
	testing.expect_value(t, err, Parse_Error.Overflow)
}

@(test)
test_parse_overflow_huge :: proc(t: ^testing.T) {
	_, err := parse_u32("99999999999")
	testing.expect_value(t, err, Parse_Error.Overflow)
}

// ── sum_all ────────────────────────────────────────────────────────────────

@(test)
test_sum_basic :: proc(t: ^testing.T) {
	total, err := sum_all([]string{"1", "2", "3"})
	testing.expect_value(t, err, Parse_Error.None)
	testing.expect_value(t, total, u64(6))
}

@(test)
test_sum_empty :: proc(t: ^testing.T) {
	total, err := sum_all([]string{})
	testing.expect_value(t, err, Parse_Error.None)
	testing.expect_value(t, total, u64(0))
}

@(test)
test_sum_stops_at_first_error :: proc(t: ^testing.T) {
	_, err := sum_all([]string{"1", "x", "3"})
	testing.expect_value(t, err, Parse_Error.Invalid_Digit)
}

@(test)
test_sum_exceeds_u32 :: proc(t: ^testing.T) {
	// Two max-u32 values sum past u32 range — the u64 accumulator must hold it.
	total, err := sum_all([]string{"4294967295", "4294967295"})
	testing.expect_value(t, err, Parse_Error.None)
	testing.expect_value(t, total, u64(8589934590))
}
