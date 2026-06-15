package odin_warmup

import "base:intrinsics"
// odin_warmup — m00-02 warm-up katas. Four small procedures over caller-owned
// memory (no allocators — that is m02's topic). Implement the bodies until
// `odin test katas/odin_warmup` is green and the leak check reports 0 leaks.
//
// Signatures are the agreed interface (see the lesson's design.md). Do not
// change them; replace each `unimplemented()` with your implementation.

// Parse_Error reports why parsing failed. The zero value None means success.
Parse_Error :: enum {
	None, // success
	Empty, // input contained no digits
	Invalid_Digit, // a byte outside '0'..='9' was encountered
	Overflow, // the parsed value exceeds the u32 range
}

// find returns the index of the first element equal to target, with found=true.
// When no element matches, found is false and index is unspecified — gate on
// found, never on index. Parapoly: works for any comparable element type T.
find :: proc(xs: []$T, target: T) -> (index: int, found: bool) {
	for el, ind in xs {
		if el == target {
			return ind, true
		}
	}
	return {}, false
}

// reverse reverses xs in place. The slice is a view onto the caller's storage,
// so the caller observes the reordering. Allocates nothing.
reverse :: proc(xs: []$T) {
	for ind in 0 ..< len(xs) / 2 {
		x := xs[ind]
		xs[ind] = xs[len(xs) - 1 - ind]
		xs[len(xs) - 1 - ind] = x
	}
}

// parse_u32 parses a base-10 unsigned integer: digits only, no sign, no
// whitespace, no radix prefix. On any failure value is 0 and err says why.
parse_u32 :: proc(s: string) -> (value: u32, err: Parse_Error) {
	if len(s) == 0 {
		return {}, Parse_Error.Empty
	}
	value = 0
	for ch in s {
		if ch < '0' || ch > '9' {
			return {}, Parse_Error.Invalid_Digit
		}
		digit := u32(ch - '0')
		mul, ov1 := intrinsics.overflow_mul(value, 10)
		if ov1 do return {}, Parse_Error.Overflow
		add, ov2 := intrinsics.overflow_add(mul, digit)
		if ov2 do return {}, Parse_Error.Overflow
		value = add
	}
	return value, Parse_Error.None
}

// sum_all parses every string in parts and returns their sum, stopping at and
// returning the first parse error (use or_return). The accumulator is u64 to
// hold sums that exceed the u32 range.
sum_all :: proc(parts: []string) -> (total: u64, err: Parse_Error) {
	total = 0
	for part in parts {
		total += u64(parse_u32(part) or_return)
	}
	return total, Parse_Error.None
}

