# Stub and documentation style

How tutor-authored `.odin` code is commented. Applies to stubs, to anything the tutor
writes into `engine/`, and to what reviews hold the learner's diff to. **Test files are
exempt** — their comments explain why a tier exists, which is not caller contract.

## The rule

> **State consequence, not procedure.**

A doc comment serves the **caller**, not the implementer. Document what a caller cannot
derive: ownership, lifetime, invalidation, error conditions, units, invariants. Never
narrate the algorithm sitting beneath it.

```odin
// ✗ recipe — narrates the body, and hands over the exercise
// remove deletes the item `h` refers to: the last dense item is swapped into
// the gap and its slot is patched via dense_to_slot; the freed slot's
// generation is bumped (wrap-to-0 ⇒ retired, else FIFO-enqueued).

// ✓ contract — everything a caller can act on, nothing they can't
/*
Removes the item `h` refers to. Remaining items may be reordered, invalidating
pointers from `get_ptr` and slices from `slice`. An invalid handle returns
`.Invalid_Handle` rather than panicking.
*/
```

The second version is not merely shorter. The deleted sentence is the algorithm the
learner was assigned to derive — see "Comments are on the hint ladder" below.

## Selection: everything unless trivial

> **Trivial ≡ fully recoverable from the declaration's name and type.**

Applies to procedures, structs, enums, distinct types, constants, and struct fields.
Ask it per declaration. Calibrated against the m03-02 handle pool's 18 declarations:

| Commented | Why it isn't derivable |
|---|---|
| `SENTINEL` | what it terminates |
| `Handle` | the packing is invisible |
| `Error.Full` | "full" of what, and when |
| `Slot.gen` | generation 0 means retired forever |
| `init` | capacity range, who owns the storage |
| `clear` | how it differs from `destroy` |
| `add` | when `.Full` happens |
| `remove` | reordering invalidates outstanding loans |
| `get_ptr` | the pointer is a loan |
| `slice` | invalidation, and order is unspecified |
| `resolve_dense_idx` | the *why* — private, non-obvious |

| Bare | Why |
|---|---|
| `is_empty`, `increment_gen`, `pack_handle`, `unpack_handle` | name and type say all of it |

Roughly four in eighteen end up bare. `Key`'s sixty enum variants are all trivial and get
nothing. Borderline cases (`Init_Failed`, `Create_Failed`) can go either way — the rule
leaves that open on purpose.

## Format

Both forms are extracted by `odin doc` and shown on OLS hover, so this is calibration.

- **One line → `//`.** A block costs two lines of delimiter; at this codebase's density
  that difference is roughly 25% of lines versus 34%.
- **Multi-sentence → `/* */`.**
- **`Inputs:`/`Returns:` → only at ≥3 parameters carrying real contract.** The extended
  Odin form (as in `core:strings`, `core:slice` — 44 of 981 core files) is the exception.
  **The receiver and a defaulted `allocator := context.allocator` do not count** toward
  the three.

```odin
// adjusted count = 1 (capacity). Short form.
// Prepares `p` to hold up to `capacity` live items; the pool owns its storage until `destroy`.
init :: proc(p: ^Handle_Pool($T), capacity: int, allocator := context.allocator)

// adjusted count = 3 (size, alignment, zero) — each carries a constraint. Extended form.
/*
Bump-allocates `size` bytes from the arena.

Inputs:
- size: bytes requested; the arena does not grow
- alignment: must be a power of two
- zero: whether the returned bytes are zeroed

Returns:
- data: the allocation, or nil
- err: `.Out_Of_Memory` if the request does not fit
*/
alloc :: proc(a: ^Arena, size: int, alignment: int, zero: bool) -> (data: []byte, err: mem.Allocator_Error)
```

Counting raw parameters instead would fire on `init` and produce `- p: The pool` —
restatement, which is the noise this convention exists to prevent.

## No file-wide comments

Source files carry no explanatory header. Content that wants to be one belongs elsewhere:

| Content | Home |
|---|---|
| Architectural rationale, layering justification | `openspec/specs/<capability>/spec.md` |
| Interface trade-offs, rejected alternatives | the lesson's `design.md` |
| Teaching prose, cite-keys, lesson cross-references | `lesson.md` → `curriculum/` |
| Measurement numbers | `lesson.md` → Performance notes → Measured |

A deviation that a maintainer would otherwise "fix" still earns an inline note — but as
one line on the declaration, not an essay above the package:

```odin
// ✗ five lines of reasoning
// DEFAULT_FIXED_DT — 50 Hz. Chosen over 60 Hz because 1/50 s is a whole number of nanoseconds
// (20,000,000) and 1/60 s is not: `time.Second/60` truncates to 16,666,666 ns, which is 0.67 ns
// short of a real 60 Hz step, forever. Harmless in itself — sim_time is derived, not accumulated
// — but a rate with no residue at all costs nothing here. 64 Hz (15,625,000 ns) is the other
// exact option worth remembering.

// ✓ the non-obvious why, one line
// 50 Hz: 1/50 s is exactly 20,000,000 ns, where 1/60 s truncates to 16,666,666.
DEFAULT_FIXED_DT :: time.Second / 50
```

## Stub bodies

`unimplemented()` and nothing else. It is declared `-> !`, so it terminates a body of any
return signature — no placeholder returns, no `_ =` discards, no `TODO` marker. Verified
against parapoly procedures with named returns.

```odin
// ✓
get_ptr :: proc(p: ^Handle_Pool($T), h: Handle) -> (item: ^T, err: Handle_Error) {
	unimplemented()
}

// ✗ four lines of scaffolding that outlive their purpose
get_ptr :: proc(p: ^Handle_Pool($T), h: Handle) -> (^T, Handle_Error) {
	// TODO(you) — m03-02
	_ = p
	_ = h
	return nil, .None
}
```

## Comments are on the hint ladder

A comment describing the strategy or structure of an implementation is a **rung-2 or
rung-3 hint**. Writing it into the stub delivers it at rung 0, unprompted, before the
learner has asked — which is the ladder bypassed, not a style preference.

If a fact is needed to *use* the procedure, it is contract and belongs in the comment. If
it is needed to *write* it, it belongs in the hint ladder, on request.

## Why this exists

Stub prose outlives the lesson. `TODO(you)` markers get deleted during implementation;
paragraphs do not — they graduate into `engine/` and stay. Density by lesson order, before
this convention: m02-02 arena 10% → m03-02 handle pool 19% → m11-01 timing 40% → m11-02
pacer 56%. The tutor's habit compounded roughly fivefold across nine modules.
