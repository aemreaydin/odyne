# Interface design

> **Interface:** learner-designed — rationale: same as the arena (m02-02). You have the allocator model and one allocator already built; the pool has its own real decisions (block-size constraints for the free-list link, what `.Resize` and oversize requests mean, whether to validate freed pointers). The `Allocator_Proc` signature is the one fixed piece.

## Learner sketch

<!-- [you] Your proposed API for katas/pool/. Rough is fine — this starts the design conversation.
     Address at least:
       - the `Pool` struct: what state does a fixed-size-block allocator hold? (backing, block size,
         free-list head — a used/free count?)
       - init: how does a caller set a pool over a fixed backing buffer AND choose block size/alignment?
         what must be true about block size for the free-list link to fit? how do you thread the list?
       - obtaining an `Allocator`: the proc yielding Allocator{procedure, data}
       - the Allocator_Proc mode switch — in particular:
           .Free      how do you push a block back? do you validate it belongs to this pool?
           .Resize    what does it mean when every block is one fixed size?
           oversize   what does a request with size > block_size return?
       - alignment: how block size and the buffer base interact so blocks are aligned and hold the link
     Signatures + short ownership/lifetime notes. See lesson.md §Exercise for the full brief. -->

MemoryBlock {
  data: []byte
  Node* next
}

Pool {
  data: []byte,
  block_size: int,
  MemoryBlock* head
  free_count int (for debug)
}

init :: proc(backing, block_size, alignment) -- len(backing) % (alignment) == 0
allocator :: proc(pool: ^Pool) -> mem.Allocator
free :: proc(block: ^MemoryBlock)
free_all :: proc()
-- no resize
oversied -- Out_of_memory or InvalidArgument


## Tutor critique

Good instincts — backing + block_size + free-list head + a debug count is the right state,
and you flagged the real hard parts. Findings, worst-first:

**1 — The free-list node is a `next` *overlaid on the block*, not a struct holding both
`data` and `next` (conceptual, the crux).** Your `MemoryBlock{ data: []byte, next }` keeps
metadata *beside* the block — which is exactly the bitmap-on-the-side approach the intrusive
list avoids. The trick: a free block isn't holding user data, so store the link *in the block's
own bytes*. The node is only a pointer:
```odin
Free_Node :: struct { next: ^Free_Node }   // overlaid on a free block; no `data` field
```
When free, the block's first `size_of(rawptr)` bytes hold `next`; when allocated, those same
bytes are the caller's. You *reinterpret* a block's address as `^Free_Node`. So `head` is
`^Free_Node`, and there's no separate `MemoryBlock` type. (Also: `Node*`/`MemoryBlock*` is C —
Odin is `^Free_Node`.) **Q:** if the node carried its own `data: []byte`, where would that
slice header physically live, and how is that different from a side bitmap?

**2 — Block size has constraints you haven't captured (correctness).** For the intrusive list
to work, every slot must be **≥ `size_of(rawptr)`** (or the `next` link doesn't fit) and the
**stride must be a multiple of `alignment`** (or block N+1 drifts out of alignment). Your
`len(backing) % alignment == 0` isn't the invariant that matters. What you actually want:
`stride := align_up(max(block_size, size_of(rawptr)), alignment)`; `count := len(backing) /
stride` (leftover bytes unused); base aligned. **Q:** what breaks if `block_size` is 4 but a
pointer is 8? What breaks if the stride isn't a multiple of `alignment`?

**3 — Two distinct failure modes, two errors (correctness).** You wrote oversize → "Out_of_memory
or InvalidArgument" — they're actually different situations: **pool exhausted** (free list empty,
correctly-sized request) = `.Out_Of_Memory` (transient — a `free` could fix it); **request bigger
than a block** = `.Invalid_Argument` (a caller bug — no `free` ever helps). Distinguishing them is
the honest design. **Q:** which is transient and which is a programming error?

**4 — `.Resize` still has to be *handled*, even if you don't truly resize (design).** "No resize"
is fine, but the mode can't fall through the switch. Cleanest: if the new `size` still fits in a
block, return the same block (a no-op resize); otherwise `.Mode_Not_Implemented`. Or just
`.Mode_Not_Implemented` for every resize. Your call — just don't drop the case.

**5 — Signatures + public surface (interface).** `free(block: ^MemoryBlock)` — the caller frees
the `rawptr`/`[]byte` it got, not a `^MemoryBlock`, and it needs the pool; `free_all()` is missing
its `^Pool`. Match the arena's surface: **public** `init`, `allocator`, `allocator_proc`,
`free_all`; **file-private** `alloc`/`free` helpers that `allocator_proc` calls. (A public direct
`free(p: ^Pool, ptr: rawptr)` convenience is optional.)

**6 — (note) Alignment ceiling.** Blocks are pre-aligned to the pool's fixed `alignment`. A caller
asking `allocator_proc` for a *larger* alignment than the pool was built with can't be guaranteed —
decide whether to assume `requested ≤ pool` or check and reject. Note only.

**Ownership (add to your notes):** the pool *borrows* `data` — caller owns it, pool never frees it;
a block is valid until freed or `free_all`; nothing may outlive the backing.

### Proposed interface — confirm or adjust (tests bind to this)

```odin
package pool
import "core:mem"

// Pool — fixed-size block allocator over a borrowed backing buffer. Owns none of `data`.
// Free blocks are threaded by an intrusive singly-linked list whose links live inside the
// free blocks themselves. Memory is valid until the block is freed or free_all is called.
Pool :: struct {
	data:       []byte,     // borrowed backing (not owned)
	block_size: int,        // effective slot stride: align_up(max(requested, size_of(rawptr)), alignment)
	head:       ^Free_Node, // first free block, or nil when exhausted
	free_count: int,        // free blocks remaining (stats/debug)
}

Free_Node :: struct { next: ^Free_Node }   // @(private="file"); overlaid on a free block

init      :: proc(p: ^Pool, backing: []byte, block_size: int, alignment: int)
allocator :: proc(p: ^Pool) -> mem.Allocator
allocator_proc :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode,
	size, alignment: int, old_memory: rawptr, old_size: int,
	location := #caller_location) -> ([]byte, mem.Allocator_Error)
free_all  :: proc(p: ^Pool)
```

**`allocator_proc` per-mode contract** (what the tests enforce):

| Mode | Behavior | Returns |
|---|---|---|
| `.Alloc` | pop head; zero the block | `size` bytes, `.None` |
| `.Alloc_Non_Zeroed` | pop head, no zeroing | `size` bytes, `.None` |
| (alloc, pool empty) | free list is nil | `nil, .Out_Of_Memory` |
| (alloc, `size > block_size`) | can never be served | `nil, .Invalid_Argument` |
| `.Free` | push `old_memory`'s block onto the head | `nil, .None` |
| `.Free_All` | re-thread the whole buffer into a fresh free list | `nil, .None` |
| `.Resize` / `.Resize_Non_Zeroed` | `size ≤ block_size` → return `old_memory` as a `size`-slice; else `.Mode_Not_Implemented` | slice / error |
| `.Query_Features` | fill the set — **includes `.Free`** (unlike the arena) | `nil, .None` |
| `.Query_Info` | — | `nil, .Mode_Not_Implemented` |

## Agreed interface

Locked (learner confirmed: oversize → `.Invalid_Argument`, exhausted → `.Out_Of_Memory`;
`.Resize` → **always** `.Mode_Not_Implemented`; arena conventions for the surface — public
`init`/`allocator`/`allocator_proc`/`free_all`, file-private `alloc`/`free` helpers;
`.Alloc` returns exactly `size` bytes). Tests bind to this. `katas/pool/pool.odin`:

```odin
package pool
import "core:mem"

// Pool — fixed-size block allocator over a borrowed backing buffer. Owns none of `data`.
// Free blocks are threaded by an intrusive singly-linked list whose links live inside the
// free blocks themselves. A block is valid until it is freed or free_all is called.
Pool :: struct {
	data:       []byte,     // borrowed backing (not owned)
	block_size: int,        // effective slot stride: align_up(max(requested, size_of(rawptr)), alignment)
	head:       ^Free_Node, // first free block, or nil when exhausted
	free_count: int,        // free blocks remaining (stats/debug)
}

Free_Node :: struct { next: ^Free_Node }   // @(private="file"); overlaid on a free block

init      :: proc(p: ^Pool, backing: []byte, block_size: int, alignment: int)
allocator :: proc(p: ^Pool) -> mem.Allocator
allocator_proc :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode,
	size, alignment: int, old_memory: rawptr, old_size: int,
	location := #caller_location) -> ([]byte, mem.Allocator_Error)
free_all  :: proc(p: ^Pool)
```

**`allocator_proc` per-mode contract** (what the tests enforce):

| Mode | Behavior | Returns |
|---|---|---|
| `.Alloc` | pop the head block, zero it | `size` bytes, `.None` |
| `.Alloc_Non_Zeroed` | pop the head block, no zeroing | `size` bytes, `.None` |
| (alloc, `size > block_size`) | can never be served | `nil, .Invalid_Argument` |
| (alloc, free list empty) | exhausted | `nil, .Out_Of_Memory` |
| `.Free` | push `old_memory`'s block onto the head | `nil, .None` |
| `.Free_All` | re-thread the whole buffer into a fresh free list | `nil, .None` |
| `.Resize` / `.Resize_Non_Zeroed` | not supported | `nil, .Mode_Not_Implemented` |
| `.Query_Features` | `{.Alloc, .Alloc_Non_Zeroed, .Free, .Free_All, .Query_Features}` — **includes `.Free`** | `nil, .None` |
| `.Query_Info` | — | `nil, .Mode_Not_Implemented` |

`alloc`/`free` are file-private helpers `allocator_proc` calls; the free-list threading
(init and Free_All) walks the buffer wiring each slot's `Free_Node.next` to the next.
