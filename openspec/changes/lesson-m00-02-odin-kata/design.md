# Interface design

> **Interface:** provided — rationale: first-Odin warm-up kata. The learning budget belongs to language mechanics, not API design; learner-designed interfaces arrive where they pay off (m23 sprite API, m50 RHI seam). See lesson.md §"Why the interface is provided".

## Learner sketch

Not applicable for this lesson — the interface is provided (see rationale above). You are not skipping design practice permanently; you're spending this lesson's effort on Odin's syntax and idioms instead.

## Tutor critique

Not applicable — no learner sketch to critique. The design choices baked into the provided interface, and why, so you can interrogate them in review:

- **`find` returns `(int, bool)`, not a sentinel index.** A separate `found` bool can't be mistaken for an offset; a `-1` or `0` sentinel can. Engine handle code (m03) makes `0`-valued indices ordinary, so the sentinel habit is actively dangerous here.
- **`reverse` returns nothing and mutates in place.** The slice is a borrowed view; the point of the kata is to feel that writes reach the caller's array. Returning a new slice would require an allocator, which m02 owns — not this lesson.
- **`Parse_Error` is an enum with distinct failure modes**, not a single `ok: bool`. The caller should learn *why* parsing failed (empty / bad digit / overflow). The zero value `Parse_Error.None` means success, so the ZII-friendly `if err != nil`-style check reads naturally.
- **`sum_all` widens the accumulator to `u64`.** Summing many `u32`s overflows a `u32`; the accumulator width is a deliberate choice you should be able to defend.

## Agreed interface

`katas/odin_warmup/warmup.odin`:

```odin
package odin_warmup

// Parse_Error reports why parsing failed. The zero value None means success.
Parse_Error :: enum {
	None,          // success
	Empty,         // input contained no digits
	Invalid_Digit, // a byte outside '0'..='9' was encountered
	Overflow,      // the parsed value exceeds the u32 range
}

// find returns the index of the first element equal to target, with found=true.
// When no element matches, found is false and index is unspecified (do not rely
// on it — gate on found). Parapoly: works for any comparable element type T.
find :: proc(xs: []$T, target: T) -> (index: int, found: bool)

// reverse reverses xs in place. The slice is a view onto the caller's storage,
// so the caller observes the reordering. Allocates nothing.
reverse :: proc(xs: []$T)

// parse_u32 parses a base-10 unsigned integer: digits only, no sign, no
// whitespace, no radix prefix. On any failure value is 0 and err says why.
parse_u32 :: proc(s: string) -> (value: u32, err: Parse_Error)

// sum_all parses every string in parts and returns their sum, stopping at and
// returning the first parse error (use or_return). The accumulator is u64 to
// hold sums that exceed the u32 range.
sum_all :: proc(parts: []string) -> (total: u64, err: Parse_Error)
```

These exact signatures are what the tests are written against. Do not change them; implement the bodies.
