# Interface design

> **Interface:** learner-designed — rationale: m03-01 handed you the models (floooh's index+generation handles, Bitsquid's two array designs) and the m03-01 probes already made you take positions on wraparound and layout choice. The kata's real learning is committing: one layout, one bit budget, one ownership story — stated precisely enough that tests can bind to them.

## Learner sketch

<!-- [you] Your proposed API for katas/handle_pool/. Rough is fine — this starts the design
     conversation. Address at least:
       - storage layout: holes or packed + index table? name the workload you're picking for,
         and what it means for iteration and for how long a resolved ^T stays usable
       - the Handle: packed u64 / packed u32 / two-field struct? index vs generation widths,
         how Handle{} (zero) is guaranteed invalid, one shared Handle type vs distinct per pool
       - the Handle_Pool($T) struct: fields, and who owns the storage (caller-provided slices
         at init, or make with an explicit allocator + a destroy?) — state lifetimes
       - generation policy: where in remove the counter bumps; your wrap answer made concrete
         (retire-at-max? how wide is the field and what's the branch?)
       - API surface: signatures for add / remove / resolve-get / valid / count / iteration,
         and the edge semantics: full pool, stale remove, double remove, zero handle
     Signatures + short ownership/lifetime notes. See lesson.md §Exercise for the full brief. -->

  Storage Layout: packed + index table - easy iteration as objects are packed, short lived ^Ts
  Parapoly handle with packed u64 - 32 bits for slots - 32 bits for generation(both are probably
  overkill) - ZII handle is invalid handle by default, one shared Handle - engine will have `distinct` types
  Handle_Pool struct($T: typeid, HT: typeid) {
    items: [dynamic]T,
    indices: [dynamic]T
    num_elements: u32
    freelist_enq: u32
    freelist_deq: u32
  }
  - generation policy: retire at max - 32 bits so very unlikely we will ever reach it
  - API: 
    - add
    - remove
    - count
    - has
    - get
    - get_ptr
    - iteration(maybe)
  - Will return an Error type for invalid/stale/full etc.
  

## Tutor critique

Good bones — packed layout with a stated reason, a real bit budget, FIFO freelist ends straight
out of Bitsquid, and errors-as-values. The FIFO detail deserves its praise: Bitsquid keeps
*enqueue and dequeue* ends precisely so a freed slot goes to the back of the line — reuse is
spread across all slots instead of hammering one, which slows each slot's generation climb and
pushes wraparound even further out [[BITSQUID]](https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html).
Findings, worst-first:

**1 — The struct has no generations (the crux).** `items`, counters, and freelist ends are
there, but no field stores **each slot's current generation** — without it, `has`/`get` have
nothing to compare a handle against, and stale detection (the entire point vs. m02-03) can't
exist. The sparse entry needs to be a real record, roughly `Slot{gen, dense_idx, next}` — your
`indices: [dynamic]T` is typed `T` (typo?), and a bare index isn't enough. **Q:** where does
Bitsquid keep the equivalent of the generation in his `Index` struct, and what field of your
`Slot` plays that role?

**2 — Packed remove needs a back-map you don't have.** Swap-with-last: the *last* dense item
moves into the gap — and **its owning slot must be patched** to point at its new dense position.
To find that slot you need dense→slot information (Bitsquid embeds the object's `id` in the
object itself; a generic container can't demand `T` carry its id, so a parallel
`dense_to_slot: []u32` is the clean equivalent). Without it, the first remove corrupts the pool.
**Q:** walk me through `remove(h)` step by step — which arrays are touched, and which slot gets
patched?

**3 — Ownership is implicit; make it explicit and fixed-capacity.** `[dynamic]` silently means
"grows via `context.allocator`". But your own edge list says **full → error**, which implies a
capacity; fixed capacity also keeps `get_ptr` loans honest (`add` never reallocates, so only
`remove`/`clear`/`destroy` move items) and matches how engines budget pools. Propose:
`init(p, capacity, allocator := context.allocator)` + `destroy(p)` — the pool *owns* its three
arrays via the stored allocator (a deliberate flip from m02's borrowed-`[]byte` katas: three
typed arrays make caller-provided backing awkward; owning-with-explicit-allocator is the
container convention, and the leak check will verify `destroy`).

**4 — "ZII handle is invalid by default" needs a mechanism, not an assertion.** `Handle(0)` is
index 0, generation 0 — if slot 0's first life had generation 0, the zero handle would *resolve*.
The standard fix: **generations start at 1** and a handle with generation 0 never validates. This
also gives your retire-at-max policy a free implementation: bump on remove, and **if the counter
wraps to 0, the slot is retired** — never re-enqueued. One branch, both guarantees.

**5 — `$HT` contradicts your own call of "one shared Handle".** The second type parameter is the
Zylinski-style road (caller-supplied distinct handle type per pool) — defensible, but you chose
shared-`Handle`-now, `distinct`-at-engine-boundaries-later, and I agree for kata scope: drop
`HT`, revisit at m03-03 where the engine wraps its own types. (If you want `HT` back later, ZYL's
`odin-handle-map` is the reference for that shape.)

**6 — API polish.**
- `count` as a plain struct field (read it like m02-03's `free_count`); no proc needed.
- **Iteration is the packed payoff: it's just a slice.** `slice(p) -> []T` returning
  `items[0:count]` — no iterator machinery. ("iteration(maybe)" → resolved: yes, one line.)
- `get -> (T, Error)` (value copy, `T{}` on error — ZII-consistent) and
  `get_ptr -> (^T, Error)` with the loan rule stated *precisely*: the pointer dies at the next
  `remove`/`clear`/`destroy` (any remove may swap *your* item); `add` does NOT invalidate
  (fixed capacity — no reallocation ever).
- `remove` returns just `Error` (want the value? `get` first).
- Add `clear(p)` — the `free_all` analog, and the best generation exercise in the API: it must
  leave **every outstanding handle stale** (bump every live slot, same retire-on-wrap rule).
- **Validation must be garbage-proof:** every handle-taking op range-checks the index before
  touching `slots` — a handle from another pool or a corrupted one returns `.Invalid_Handle`,
  never panics. Error enum stays small: `{None, Full, Invalid_Handle}` — zero, stale, retired,
  and out-of-range are all the same answer to the caller: "not a thing you may touch."

### Proposed interface — confirm or adjust (tests bind to this)

```odin
package handle_pool

import "core:mem"

SENTINEL :: max(u32) // freelist "none"

// Handle — packed u64: low 32 bits slot index, high 32 bits generation.
// Generations start at 1, so Handle(0) — the ZII zero value — can never validate.
Handle :: distinct u64

Error :: enum {
	None,
	Full,           // no free slot (all live or retired)
	Invalid_Handle, // zero, stale, retired, or out-of-range
}

// Slot — sparse entry: which lifetime (gen), where the item lives (dense_idx), freelist link.
Slot :: struct {
	gen:       u32, // current generation; starts at 1; wraps-to-0 ⇒ slot retired
	dense_idx: u32, // position in items[] while live
	next:      u32, // next free slot in FIFO order, SENTINEL if none
}

Handle_Pool :: struct($T: typeid) {
	items:         []T,   // dense storage; [0:count) live — owned via `allocator`
	dense_to_slot: []u32, // dense position → owning slot (remove's patch-up map)
	slots:         []Slot,
	count:         u32,
	free_head:     u32,   // dequeue end (oldest freed slot) — FIFO per BITSQUID
	free_tail:     u32,   // enqueue end
	allocator:     mem.Allocator,
}

init    :: proc(p: ^Handle_Pool($T), capacity: int, allocator := context.allocator)
destroy :: proc(p: ^Handle_Pool($T))
clear   :: proc(p: ^Handle_Pool($T))                             // empty the pool; ALL outstanding handles go stale
add     :: proc(p: ^Handle_Pool($T), item: T) -> (Handle, Error)
remove  :: proc(p: ^Handle_Pool($T), h: Handle) -> Error
get     :: proc(p: ^Handle_Pool($T), h: Handle) -> (T, Error)    // value copy; T{} on error
get_ptr :: proc(p: ^Handle_Pool($T), h: Handle) -> (^T, Error)   // LOAN: dies at next remove/clear/destroy
has     :: proc(p: ^Handle_Pool($T), h: Handle) -> bool
slice   :: proc(p: ^Handle_Pool($T)) -> []T                      // items[0:count] — iteration is a slice
```

**Per-operation contract** (what the tests enforce):

| Operation | Behavior | Edge |
|---|---|---|
| `init` | allocate the three arrays from `allocator`; thread freelist 0→cap−1 FIFO; all gens = 1 | assert `0 < capacity < SENTINEL` |
| `destroy` | free all three arrays via stored allocator | leak check binds here |
| `add` | dequeue `free_head`; item → `items[count]`; wire `dense_to_slot`/`slot.dense_idx`; `count += 1`; return `{slot, gen}` | freelist empty → `0, .Full` |
| `remove(h)` | validate; swap `items[count-1]` into the gap; **patch the moved item's slot via `dense_to_slot`**; `count -= 1`; `gen += 1`; wrapped-to-0 → retired (not enqueued) else FIFO-enqueue | invalid → `.Invalid_Handle` |
| `get` / `get_ptr` / `has` / `remove` validation | `index < capacity` **and** `gen(h) != 0` **and** `slots[index].gen == gen(h)` | garbage-safe: never panics |
| `get` on invalid | `T{}, .Invalid_Handle` | ZII |
| `clear` | bump every **live** slot's gen (same retire rule); rebuild freelist; `count = 0` | every prior handle now stale |
| zero handle | gen 0 never matches (gens start at 1) | `Handle(0)` fails everywhere |

## Agreed interface

Locked (learner confirmed via the design Q&A; proposal accepted as-is: **packed + index
table** · owned fixed-capacity storage via `init(capacity, allocator)`/`destroy` · packed
`u64` shared `Handle`, 32/32 split · generations start at 1 (zero handle never validates) ·
retire-on-wrap · FIFO freelist · `Handle_Error{None, Full, Invalid_Handle}` · `count` as a
field · iteration = `slice()`). Amended 2026-07-20: enum renamed `Error` → `Handle_Error`
(learner preference; Ada_Case per repo type style). Tests bind to this.
`katas/handle_pool/handle_pool.odin`:

```odin
package handle_pool

import "core:mem"

SENTINEL :: max(u32) // freelist "none"

// Handle — packed u64: low 32 bits slot index, high 32 bits generation.
// Generations start at 1, so Handle(0) — the ZII zero value — can never validate.
Handle :: distinct u64

Handle_Error :: enum {
	None,
	Full,           // no free slot (all live or retired)
	Invalid_Handle, // zero, stale, retired, or out-of-range
}

// Slot — sparse entry: which lifetime (gen), where the item lives (dense_idx), freelist link.
Slot :: struct {
	gen:       u32, // current generation; starts at 1; wraps-to-0 ⇒ slot retired
	dense_idx: u32, // position in items[] while live
	next:      u32, // next free slot in FIFO order, SENTINEL if none
}

Handle_Pool :: struct($T: typeid) {
	items:         []T,   // dense storage; [0:count) live — owned via `allocator`
	dense_to_slot: []u32, // dense position → owning slot (remove's patch-up map)
	slots:         []Slot,
	count:         u32,
	free_head:     u32,   // dequeue end (oldest freed slot) — FIFO per BITSQUID
	free_tail:     u32,   // enqueue end
	allocator:     mem.Allocator,
}

init    :: proc(p: ^Handle_Pool($T), capacity: int, allocator := context.allocator)
destroy :: proc(p: ^Handle_Pool($T))
clear   :: proc(p: ^Handle_Pool($T))                             // empty the pool; ALL outstanding handles go stale
add     :: proc(p: ^Handle_Pool($T), item: T) -> (Handle, Handle_Error)
remove  :: proc(p: ^Handle_Pool($T), h: Handle) -> Handle_Error
get     :: proc(p: ^Handle_Pool($T), h: Handle) -> (T, Handle_Error)    // value copy; T{} on error
get_ptr :: proc(p: ^Handle_Pool($T), h: Handle) -> (^T, Handle_Error)   // LOAN: dies at next remove/clear/destroy
has     :: proc(p: ^Handle_Pool($T), h: Handle) -> bool
slice   :: proc(p: ^Handle_Pool($T)) -> []T                             // items[0:count] — iteration is a slice
```

**Per-operation contract** (tests enforce exactly this):

| Operation | Behavior | Edge |
|---|---|---|
| `init` | allocate the three arrays from `allocator`; thread freelist 0→cap−1 FIFO; all gens = 1 | assert `0 < capacity < SENTINEL` |
| `destroy` | free all three arrays via stored allocator | leak check binds here |
| `add` | dequeue `free_head`; item → `items[count]`; wire `dense_to_slot`/`slot.dense_idx`; `count += 1`; return `{slot, gen}` | freelist empty → `0, .Full` |
| `remove(h)` | validate; swap `items[count-1]` into the gap; **patch the moved item's slot via `dense_to_slot`**; `count -= 1`; `gen += 1`; wrapped-to-0 → retired (not enqueued) else FIFO-enqueue | invalid → `.Invalid_Handle` |
| validation (`get`/`get_ptr`/`has`/`remove`) | `index < capacity` **and** `gen(h) != 0` **and** `slots[index].gen == gen(h)` | garbage-safe: never panics |
| `get` on invalid | `T{}, .Invalid_Handle` | ZII |
| `clear` | bump every **live** slot's gen (same retire rule); rebuild freelist; `count = 0` | every prior handle now stale |
| zero handle | gen 0 never matches (gens start at 1) | `Handle(0)` fails everywhere |
