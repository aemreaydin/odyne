# Interface design

> **Interface:** learner-designed — rationale: by m02 you have the Odin idioms (m00) and the allocator model (m02-01) to make real API decisions, and the arena has genuine ones to make (struct state, init over borrowed backing, how you obtain an `Allocator`, reset shape, which modes to support). The one fixed piece is the `Allocator_Proc` signature your procedure must match — everything around it is yours. Design practice lands here because it now pays off; it recurs at m23 (sprite API) and m50 (RHI seam).

## Learner sketch

<!-- [you] Your proposed API for katas/arena/. Rough is fine — this starts the design conversation.
     Address at least:
       - the `Arena` struct: what state does a bump allocator hold?
       - init: how does a caller set an arena over a fixed backing buffer they provide?
       - obtaining an `Allocator`: the proc that yields Allocator{procedure, data} for `context.allocator`
       - reset: Free_All mode only, or also a directly-callable helper?
       - alignment: `mem.align_forward` or your own arithmetic?
       - which Allocator_Mode values you support, and what each returns
         (don't forget: what does `Free` return? does `Resize` get the last-allocation fast path?)
     Signatures + short ownership/lifetime notes. See lesson.md §Exercise for the full brief. -->

Arena :: struct {
     data: []byte,
     current_offset: uintptr,
     prev_offset: uintptr
}

init :: proc(bytes: []byte) -> Arena
alloc :: proc(arena: ^Arena)
reset :: proc(arena: ^Arena)
@private align_forward :: proc(arena: ^Arena, align: uint)

Arena allocator will support Alloc, Free_all, Resize, Alloc_Non_Zeroed, Resize_Non_Zeroed, Query_features


## Tutor critique

Strong start — the struct is essentially Ginger Bill's pt.2 arena (`data` + a current
and a previous offset), which tells me you read the source. Findings, worst-first:

**1 — The two procedures that make it an allocator are missing (blocker).** You have
`init`/`alloc`/`reset`/`align_forward`, but nothing that yields an `Allocator{procedure, data}`
value and no procedure with the `Allocator_Proc` signature — and those two *are* the kata
(m02-01: `context.allocator = my_arena`):
- an accessor `allocator(a: ^Arena) -> mem.Allocator` returning `{allocator_proc, a}`, and
- `allocator_proc` — the one procedure with the fixed signature that recovers `^Arena` from
  `allocator_data` and `switch`es on `mode`. **This is the deliverable.**
Your `alloc :: proc(arena: ^Arena)` can't allocate — no `size`/`alignment` in, no `[]byte`
out. Decide: does anything call a direct `alloc`, or do callers set `context.allocator` and
use `new`/`make`/`mem.alloc` (which route into `allocator_proc`)? The lesson wants the latter;
a direct `alloc` is at most an optional convenience.

**2 — Alignment is on the address, not the offset (correctness).** `current_offset` is a
position inside `data`, but alignment is a property of the *absolute* address
`raw_data(data) + offset`. Aligning only the offset assumes `raw_data(data)` is itself aligned
to every requested alignment — false for an arbitrary borrowed `[]byte` (a stack array, a
sub-slice). pt.2 aligns the absolute pointer, then subtracts the base back to an offset
[GB-MEM pt.2]. My tests will hand you a deliberately misaligned backing slice to catch this.
Also: your `align_forward` returns nothing — it needs to return the aligned offset/pointer.

**3 — `Free` is missing, and it's the defining mode (correctness/completeness).** You listed
six modes but not `Free` (nor `Query_Info`) — both must be handled or they fall through. An
arena can't free one allocation, so it *declares* that: Odin's arena family returns
`.Mode_Not_Implemented` for `.Free`, and downstream code tolerates that specific error —
`delete` and dynamic-array growth treat `.Mode_Not_Implemented` as "fine, skip it," not a hard
failure [ODIN-MEM]. (The `nil_allocator` instead returns `.None` for `.Free`; both are safe,
but match the arena convention.) `Query_Info` → `.Mode_Not_Implemented` too. The only reclaim
is `Free_All`. — *(Correction to my earlier note: I first said `Free` should be a `(nil, .None)`
no-op; checking the Odin source, the arena convention is `.Mode_Not_Implemented`. Matching std.)*

**4 — `prev_offset` → name the payoff (design; good).** It exists for one reason: the Resize
fast path. When `old_memory == raw_data(data) + prev_offset` (the block being resized is the
most recent allocation), grow/shrink in place by moving `offset` — no copy [GB-MEM pt.2]. The
general Resize (not the last block) falls back to alloc-new + copy-old. Confirm that's the plan.

**5 — Offset type: `uintptr` → `int` (idiom).** Odin's `mem.Arena` uses `offset: int` and
`peak_used: int` [ODIN-MEM]. A slice offset is naturally `int` (what `len` returns, what
indexes a slice); `uintptr` is for the brief address arithmetic inside `align_forward`, where
you cast up and back. The `uintptr`/`size_t` reflex is a C habit here — defend it if you
disagree, but you'll be casting on every slice index.

**6 — `init` shape + naming (minor).** `init(bytes) -> Arena` returns by value; std's
`arena_init(a: ^Arena, data)` inits in place (ZII + set `data`), which embeds better in larger
structs. And `init`/`alloc`/`reset` are generic even inside package `arena`; `free_all`
(matching the `.Free_All` mode and `mem.free_all`) reads better than `reset`. Your call — be
deliberate.

**Ownership (add to your notes):** the arena *borrows* `data` — caller owns it, arena never
frees it; handed-out memory is valid until the next `free_all`; nothing from the arena may
outlive the backing buffer. That is m02-01's ownership rule, made concrete.

### Proposed interface — confirm or adjust (tests bind to this)

```odin
package arena
import "core:mem"

// Arena — bump allocator over a borrowed, fixed backing buffer. Owns none of
// `data`; the caller's buffer must outlive the arena. Memory handed out is valid
// until the next free_all.
Arena :: struct {
	data:        []byte, // borrowed backing (not owned)
	offset:      int,    // bytes used; next alloc aligns up from here
	prev_offset: int,    // start of the most recent alloc — enables the Resize fast path
	peak_used:   int,    // high-water mark (for the measurement task)
}

init      :: proc(a: ^Arena, backing: []byte)
allocator :: proc(a: ^Arena) -> mem.Allocator
allocator_proc :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode,
	size, alignment: int, old_memory: rawptr, old_size: int,
	location := #caller_location) -> ([]byte, mem.Allocator_Error)
free_all  :: proc(a: ^Arena)
```

`align_forward` stays an unexported implementation detail — roll your own or call
`mem.align_forward_int`; not part of the public surface.

## Agreed interface

Locked (learner confirmed the three defaults: `int` offsets · in-place `init` · Allocator path
only, no direct `alloc`). Tests bind to exactly this. `katas/arena/arena.odin`:

```odin
package arena
import "core:mem"

// Arena — bump allocator over a borrowed, fixed backing buffer. Owns none of `data`;
// the caller's buffer must outlive the arena. Memory handed out stays valid until the
// next free_all (there is no per-allocation free). ZII: a zeroed Arena is a valid empty
// arena with no backing storage.
Arena :: struct {
	data:        []byte, // borrowed backing storage (not owned)
	offset:      int,    // bytes used; the next allocation aligns up from here
	prev_offset: int,    // start of the most recent allocation — enables the Resize fast path
	peak_used:   int,    // high-water mark of offset, for the measurement task
}

init      :: proc(a: ^Arena, backing: []byte)
allocator :: proc(a: ^Arena) -> mem.Allocator
allocator_proc :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode,
	size, alignment: int, old_memory: rawptr, old_size: int,
	location := #caller_location) -> ([]byte, mem.Allocator_Error)
free_all  :: proc(a: ^Arena)
```

**`allocator_proc` per-mode contract** (what the tests enforce):

| Mode | Behavior | Returns |
|---|---|---|
| `.Alloc` | align the **absolute address** `raw_data(data)+offset` up to `alignment`, bump `offset` past it, update `peak_used`; **zero** the bytes | the `size`-byte slice, `.None` |
| `.Alloc_Non_Zeroed` | same, without zeroing | the slice, `.None` |
| `.Free` | nothing — an arena can't free one allocation | `nil, .Mode_Not_Implemented` |
| `.Free_All` | `offset = 0; prev_offset = 0` | `nil, .None` |
| `.Resize` / `.Resize_Non_Zeroed` | if `old_memory` is the most-recent alloc (`== raw_data(data)+prev_offset`), grow/shrink in place; else alloc-new + copy old bytes; Resize zeroes any grown tail | the slice, `.None` (or `.Out_Of_Memory`) |
| `.Query_Features` | fill `(^mem.Allocator_Mode_Set)(old_memory)` with `{.Alloc, .Alloc_Non_Zeroed, .Free_All, .Resize, .Resize_Non_Zeroed, .Query_Features}` | `nil, .None` |
| `.Query_Info` | — | `nil, .Mode_Not_Implemented` |

Request doesn't fit → `nil, .Out_Of_Memory`. `align_forward` is an unexported implementation
detail (roll your own or use `mem.align_forward_int`) — not part of the public surface.
