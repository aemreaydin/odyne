# Interface design

> **Interface:** learner-designed — rationale: the pool's per-op contract is locked from
> m03-02 and does not reopen; what's open is everything a _dependent package_ sees —
> package path/name, proc naming, and above all the handle type that crosses package
> boundaries. m03-02's critique (finding 5) deferred the `$HT` question to exactly here.

## Learner sketch

<!-- [you] Your proposed engine surface for the graduated handle pool. Rough is fine — this
     starts the design conversation. Address:
       - packaging: engine/core/containers (one package, prefixed names — your m02-04
         memory shape) or engine/core/handle_pool / engine/core/containers/handle_pool
         (one sub-package per container — the core:container shape) or something else;
         name the landing spot for m41's job queue and m42's component storage in your scheme
       - naming: what call sites read like (`containers.pool_add(...)` vs `handle_pool.add(...)`),
         and the survival plan for when sibling containers arrive
       - the handle type (the crux): shared core `Handle` + per-system distinct wrapping,
         or Handle_Pool($T, $HT) with a caller-supplied distinct handle type? Sketch the
         signatures either way, say how the ZII zero-invalid guarantee survives, and how
         phase 2's render layer (Texture_Handle, ...) will consume it
       - anything else the surface changes: Handle_Error name/home, SENTINEL exposure,
         Slot visibility
     The m03-02 per-op contract (packed + index table, FIFO freelist, retire-on-wrap,
     generations start at 1, garbage-safe validation) is LOCKED — semantics don't reopen,
     only the surface. See lesson.md §Exercise for the full brief. -->

- Packaging + Naming: We will create a odyne/core/containers/handle_pool (we might eventually think about doing the same in memory)
- The Handle Type will be a user defined $HT

## Tutor critique

Good bones, and bold ones. Sub-package-per-container is exactly the stdlib's `core:container`
shape — each container its own package, unprefixed procs, call sites read `handle_pool.add(...)`
[[ODIN-CONTAINER]](https://pkg.odin-lang.org/core/container/queue/) — and it means the kata's
names survive verbatim: the graduation becomes almost purely a move. And `$HT` commits to the
compile-time-safety side of the crux, which is where the Odin ecosystem has converged: Zylinski's
handle maps [[ZYL-HANDLES]](https://zylinski.se/posts/handle-based-maps-three-implementations/),
the stdlib's `core:container/handle_map`
[[ODIN-CONTAINER handle_map]](https://pkg.odin-lang.org/core/container/handle_map/), and floooh
arguing it from C, where it costs the most boilerplate
[[FLOOOH]](https://floooh.github.io/2018/06/17/handles-vs-pointers.html). Findings, worst-first:

**1 — `$HT` is a bullet point; it needs a mechanism (the crux).** What is HT *allowed to be*,
and how do the internals build one? The kata packs `u64(gen) << 32 | u64(idx)` into a
`distinct u64`. The clean generalization: **constrain HT to 64 bits** — a `where` clause on the
struct, `where size_of(HT) == size_of(u64)` — and have pack/unpack `transmute` between HT and
`u64`. Then `Texture_Handle :: distinct u64` is one line at the call site, and the ZII guarantee
carries over mechanically: the zero HT transmutes to `u64(0)` → generation 0 → never validates
(generations still start at 1). Nothing else in the locked contract moves. Compare: the stdlib's
`handle_map` constrains HT differently — a struct with `idx`/`gen` fields
[[ODIN-CONTAINER handle_map]](https://pkg.odin-lang.org/core/container/handle_map/) — two valid
mechanisms for the same invariant; ours keeps your packed-u64 contract.
**Q1:** walk me through `add` under your `$HT`: an item goes in, slot 7 / generation 3 comes
back — what exact steps turn `(7, 3)` into a `Texture_Handle`, and why can that value never
collide with the ZII zero handle?

**2 — Signatures unspecified — and tests bind to signatures.** Every handle-taking proc must
take/return HT, not a shared type, or the type-safety claim silently evaporates (an `add`
returning core `Handle` puts the manual-wrap burden right back at every call site). Full
proposed surface below — confirm or adjust.

**3 — Keep the ready-made `Handle`.** Not every pool crosses a package boundary; forcing every
internal use to invent a distinct type is ceremony. The stdlib ships ready-made handle types for
exactly this reason [[ODIN-CONTAINER handle_map]](https://pkg.odin-lang.org/core/container/handle_map/).
Your kata's `Handle :: distinct u64` stays exported as the default: internal pools instantiate
`Handle_Pool(Thing, handle_pool.Handle)`; boundary-crossing systems define their own. Zero new code.

**4 — Path spelling and the future tenants.** The collection is `engine`, so the directory is
`engine/core/containers/handle_pool`, imported as `engine:core/containers/handle_pool` (alias at
will: `import hp "engine:core/containers/handle_pool"`). The intermediate `containers/` holds no
`.odin` files — it's a grouping directory, exactly like the stdlib's `core/container/`
[[ODIN-CONTAINER]](https://pkg.odin-lang.org/core/container/queue/). Your scheme implies m41's
job queue lands as `engine/core/containers/job_queue` and m42's component storage likewise —
name that intent in the agreed interface so future lessons don't relitigate it.
**Q2 (minor):** stdlib says singular `container`, your sketch says plural `containers` — either
is fine, but pick deliberately; the path is spelled at every import forever.

**5 — "Do the same to memory eventually" — parked, deliberately.** Restructuring
`engine/core/memory` is out of this lesson's scope (graduate the pool; don't churn a shipped
package). It's a legitimate candidate for the m33 milestone retrospective, where curriculum
amendments belong. Noted here so it isn't lost.

**6 — Surface polish, your call:** (a) `handle_pool.Handle_Error` stutters now that the package
name carries context — stdlib-style would be plain `Error`; you renamed it *to* `Handle_Error`
in m03-02 by preference, so keep or shorten, just decide. (b) `SENTINEL` and `Slot` remain
exported implementation details; in-package tests see them regardless — leave as-is, with the
engine convention that dependents treat struct fields as read-only and mutate through procs.

### Proposed interface — confirm or adjust (tests bind to this)

```odin
package handle_pool
// engine/core/containers/handle_pool — import "engine:core/containers/handle_pool"

import "core:mem"

SENTINEL :: max(u32) // freelist "none"

// Ready-made handle type for pools that never cross a package boundary.
// Boundary-crossing systems define their own 64-bit distinct type instead:
//   Texture_Handle :: distinct u64
//   pool: handle_pool.Handle_Pool(Texture, Texture_Handle)
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

// $HT: the caller's handle type — any 64-bit type, typically `distinct u64`.
// Packed low 32 bits slot index, high 32 bits generation; pack/unpack transmute HT ↔ u64.
Handle_Pool :: struct($T: typeid, $HT: typeid) where size_of(HT) == size_of(u64) {
	items:         []T,   // dense storage; [0:count) live — owned via `allocator`
	dense_to_slot: []u32, // dense position → owning slot (remove's patch-up map)
	slots:         []Slot,
	count:         u32,
	free_head:     u32,   // dequeue end (oldest freed slot) — FIFO per BITSQUID
	free_tail:     u32,   // enqueue end
	allocator:     mem.Allocator,
}

init    :: proc(p: ^Handle_Pool($T, $HT), capacity: int, allocator := context.allocator)
destroy :: proc(p: ^Handle_Pool($T, $HT))
clear   :: proc(p: ^Handle_Pool($T, $HT))                              // empty; ALL outstanding handles go stale
add     :: proc(p: ^Handle_Pool($T, $HT), item: T) -> (HT, Handle_Error)
remove  :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> Handle_Error
get     :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> (T, Handle_Error)  // value copy; T{} on error
get_ptr :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> (^T, Handle_Error) // LOAN: dies at next remove/clear/destroy
has     :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> bool
slice   :: proc(p: ^Handle_Pool($T, $HT)) -> []T                       // items[0:count] — iteration is a slice
```

**Per-operation contract — unchanged from m03-02 except the handle type** (tests re-enforce
exactly this against the new surface):

| Operation | Behavior | Edge |
|---|---|---|
| `init` | allocate the three arrays from `allocator`; thread freelist 0→cap−1 FIFO; all gens = 1 | assert `0 < capacity < SENTINEL` |
| `destroy` | free all three arrays via stored allocator | leak check binds here |
| `add` | dequeue `free_head`; item → `items[count]`; wire `dense_to_slot`/`slot.dense_idx`; `count += 1`; return packed `{slot, gen}` as HT | freelist empty → `HT{}, .Full` |
| `remove(h)` | validate; swap `items[count-1]` into the gap; patch the moved item's slot via `dense_to_slot`; `count -= 1`; `gen += 1`; wrapped-to-0 → retired else FIFO-enqueue | invalid → `.Invalid_Handle` |
| validation (`get`/`get_ptr`/`has`/`remove`) | transmute h → u64; `index < capacity` **and** `gen(h) != 0` **and** `slots[index].gen == gen(h)` | garbage-safe: never panics |
| `get` on invalid | `T{}, .Invalid_Handle` | ZII |
| `clear` | bump every **live** slot's gen (same retire rule); rebuild freelist; `count = 0` | every prior handle now stale |
| zero handle | `HT{}` transmutes to `u64(0)` → gen 0 never matches (gens start at 1) | the ZII zero of *every* HT fails everywhere |

Internals: only `pack_handle`/`unpack_handle`/`resolve` change (transmute HT ↔ u64 at the
edges); every other body ports byte-for-byte from the kata.

**To lock:** answer Q1 (the add walkthrough) and Q2 (singular/plural), decide 6(a)
(`Handle_Error` vs `Error`), and confirm or adjust the surface above.

## Agreed interface

Locked 2026-07-21 (learner confirmed via the design Q&A). Q1 answered correctly — packed
`u64(gen) << 32 | u64(idx)`, generations start at 1 so a valid handle can never equal the ZII
zero — with one tutor addendum recorded: the final step of `add` is `transmute`-ing that packed
`u64` into the caller's `HT`; validation transmutes back at every entry point. Q2: plural
`containers`. 6(a): enum renamed `Handle_Error` → `Error` (the package name now carries the
context: `handle_pool.Error`). Surface accepted as proposed. Future tenants recorded: m41's job
queue lands as `engine/core/containers/job_queue`, m42's component storage beside it;
restructuring `engine/core/memory` to match is parked for the m33 retrospective.

`engine/core/containers/handle_pool/handle_pool.odin` (`containers/` is a grouping directory
with no `.odin` files, per the stdlib's `core/container/` shape):

```odin
package handle_pool
// import "engine:core/containers/handle_pool"

import "core:mem"

SENTINEL :: max(u32) // freelist "none"

// Ready-made handle type for pools that never cross a package boundary.
// Boundary-crossing systems define their own 64-bit distinct type instead:
//   Texture_Handle :: distinct u64
//   pool: handle_pool.Handle_Pool(Texture, Texture_Handle)
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

// $HT: the caller's handle type — any 64-bit type, typically `distinct u64`.
// Packed low 32 bits slot index, high 32 bits generation; pack/unpack transmute HT ↔ u64.
Handle_Pool :: struct($T: typeid, $HT: typeid) where size_of(HT) == size_of(u64) {
	items:         []T,   // dense storage; [0:count) live — owned via `allocator`
	dense_to_slot: []u32, // dense position → owning slot (remove's patch-up map)
	slots:         []Slot,
	count:         u32,
	free_head:     u32,   // dequeue end (oldest freed slot) — FIFO per BITSQUID
	free_tail:     u32,   // enqueue end
	allocator:     mem.Allocator,
}

init    :: proc(p: ^Handle_Pool($T, $HT), capacity: int, allocator := context.allocator)
destroy :: proc(p: ^Handle_Pool($T, $HT))
clear   :: proc(p: ^Handle_Pool($T, $HT))                        // empty; ALL outstanding handles go stale
add     :: proc(p: ^Handle_Pool($T, $HT), item: T) -> (HT, Error)
remove  :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> Error
get     :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> (T, Error)   // value copy; T{} on error
get_ptr :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> (^T, Error)  // LOAN: dies at next remove/clear/destroy
has     :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> bool
slice   :: proc(p: ^Handle_Pool($T, $HT)) -> []T                 // items[0:count] — iteration is a slice
```

**Per-operation contract — unchanged from m03-02 except the handle type** (tests re-enforce
exactly this against the new surface):

| Operation | Behavior | Edge |
|---|---|---|
| `init` | allocate the three arrays from `allocator`; thread freelist 0→cap−1 FIFO; all gens = 1 | assert `0 < capacity < SENTINEL` |
| `destroy` | free all three arrays via stored allocator | leak check binds here |
| `add` | dequeue `free_head`; item → `items[count]`; wire `dense_to_slot`/`slot.dense_idx`; `count += 1`; return packed `{slot, gen}` transmuted to HT | freelist empty → zero HT, `.Full` |
| `remove(h)` | validate; swap `items[count-1]` into the gap; patch the moved item's slot via `dense_to_slot`; `count -= 1`; `gen += 1`; wrapped-to-0 → retired else FIFO-enqueue | invalid → `.Invalid_Handle` |
| validation (`get`/`get_ptr`/`has`/`remove`) | transmute h → u64; `index < capacity` **and** `gen(h) != 0` **and** `slots[index].gen == gen(h)` | garbage-safe: never panics |
| `get` on invalid | `T{}, .Invalid_Handle` | ZII |
| `clear` | bump every **live** slot's gen (same retire rule); rebuild freelist; `count = 0` | every prior handle now stale |
| zero handle | `HT{}` transmutes to `u64(0)` → gen 0 never matches (gens start at 1) | the ZII zero of *every* HT fails everywhere |

Internals: only `pack_handle`/`unpack_handle`/`resolve` change (transmute HT ↔ u64 at the
edges); every other body ports byte-for-byte from the kata.

## Design amendment (2026-07-21) — embedded handle

Learner reopened the surface before 4.1 (proposal sketched directly in the stub,
`engine/core/containers/handle_pool/handle_pool.odin`): tighten the `where` clause to
`size_of(HT) == size_of(u64)` **and** `intrinsics.type_is_unsigned(HT)`, and — the substantive
change — require **`T` to embed its own handle**: `intrinsics.type_has_field(T, "handle")` and
`intrinsics.type_field_type(T, "handle") == HT`. Plus a new `HandleType :: distinct Handle`
declaration.

### Tutor critique

First, credit where due: in m03-02 (finding 2) I claimed *"a generic container can't demand `T`
carry its id, so a parallel `dense_to_slot` is the clean equivalent."* Your `where` clause
refutes that — `type_has_field` lets a generic container demand exactly what Bitsquid's
hand-written one assumed, an object that knows its own id, which is how his swap-with-last
patch actually works (`_indices[_objects[o].id & INDEX_MASK].index = o`)
[[BITSQUID]](https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html).
It's also precisely the contract of Zylinski's handle map — items embed a `handle` field the
map maintains [[ZYL-HANDLES]](https://zylinski.se/posts/handle-based-maps-three-implementations/).
So the shape is canonical, not exotic.

**Verified mechanics** (tutor-run `odin check` probes): the four-condition `where` compiles;
`type_is_unsigned` accepts `distinct u64` *and* distinct-of-distinct; procs need not repeat the
struct's `where` clause; a violating instantiation fails with a clean error naming the failed
condition and the offending types. One typo to fix when the stub is rebound: `intrinsincs` on
the last condition.

Findings, worst-first:

**1 — You haven't cashed the payoff: a struct field just became redundant.**
**Q1:** with every stored item carrying its own handle, which of the pool's three arrays is now
redundant — and which two operation bodies change to exploit that? Work it through `remove`'s
patch step and `clear`'s generation sweep before answering. Recommendation: **drop it** — that's
the entire point of embedding (it's what Bitsquid's patch line does); keeping both means the
same fact stored twice and kept in sync by hand. Net accounting if dropped: pool bookkeeping
shrinks 4 B/slot; items grow 8 B for a handle callers actually want (see finding 2); `remove`'s
patch reads the moved item's cache line (already being touched by the swap) instead of a
separate array.

**2 — Someone must write `item.handle`, and the contract must say who.** Proposed addition to
the per-op table: **`add` overwrites the stored copy's `handle` field with the issued handle** —
whatever the caller left there is ignored. In exchange the old surface's real gap closes:
`slice()` used to lose the handles (iterate live items, want to remove one — with what handle?);
now every yielded item knows its own identity. Borrowing rule restated for the new pattern: the
slice is still invalidated by any `remove` — collect handles during the walk, remove after.

**3 — `HandleType :: distinct Handle` is dead weight.** Nothing references it, callers define
their own types (`Sprite_Handle :: distinct u64` — and `distinct handle_pool.Handle` also
satisfies the `where` clause, verified). If it was meant as an example, that belongs in the doc
comment; if kept it should be `Handle_Type` per repo naming. Recommendation: drop the
declaration. **Q3:** what did you intend it for?

**4 — `type_is_unsigned(HT)`: keep.** It tightens "any 64-bit type" to "64-bit unsigned,
distinct included" — exactly what the packed-u64 transmute contract wants; `f64` and 8-byte
structs are out. (Deliberate divergence from the stdlib's struct-shaped `Handle64` — ours is
the packed-integer contract [[ODIN-CONTAINER handle_map]](https://pkg.odin-lang.org/core/container/handle_map/).)

**Consequences once re-locked** (tutor work, before your 4.1): stub rebound to the amended
surface (typo fixed), tests rewritten — `T` becomes a small struct (`Test_Item{handle, value}`),
plus a new test binding "add sets the embedded handle / slice yields self-identifying items" —
and re-verified RED.

**To re-lock:** answer Q1 (the redundant array, and drop-or-keep), confirm finding 2's contract
addition, and answer Q3 (or accept dropping `HandleType`).

### Amended agreed interface (locked)

Re-locked 2026-07-21. Q1 answered correctly — **`dense_to_slot` is dropped**; the handle
embedded in each item carries the same information. Tutor precision note for implementation:
*three* bodies change to cash it — `add` writes the issued handle into the stored copy (and no
longer wires a back-map), `remove` patches the moved item's slot via
`unpack(moved.handle).idx`, and `clear` sweeps the live items' embedded handles instead of a
back-map. Finding 2's contract addition confirmed (add overwrites `item.handle`).
`HandleType` dropped. Tests bind to this surface:

```odin
package handle_pool
// import "engine:core/containers/handle_pool"

import "base:intrinsics"
import "core:mem"

SENTINEL :: max(u32) // freelist "none"

// Ready-made handle type for pools that never cross a package boundary.
// Boundary-crossing systems define their own 64-bit unsigned distinct type instead:
//   Texture_Handle :: distinct u64        (distinct handle_pool.Handle also satisfies the constraints)
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

// $HT: the caller's handle type — 64-bit unsigned, distinct included; packed low 32 bits slot
// index, high 32 bits generation. $T must embed `handle: HT`, which the pool maintains: add
// overwrites it with the issued handle, so every stored item identifies itself.
Handle_Pool :: struct($T: typeid, $HT: typeid) where size_of(HT) == size_of(u64),
	intrinsics.type_is_unsigned(HT),
	intrinsics.type_has_field(T, "handle"),
	intrinsics.type_field_type(T, "handle") == HT {
	items:     []T,   // dense storage; [0:count) live — owned via `allocator`; items know their handles
	slots:     []Slot,
	count:     u32,
	free_head: u32,   // dequeue end (oldest freed slot) — FIFO per BITSQUID
	free_tail: u32,   // enqueue end
	allocator: mem.Allocator,
}

init    :: proc(p: ^Handle_Pool($T, $HT), capacity: int, allocator := context.allocator)
destroy :: proc(p: ^Handle_Pool($T, $HT))
clear   :: proc(p: ^Handle_Pool($T, $HT))                        // empty; ALL outstanding handles go stale
add     :: proc(p: ^Handle_Pool($T, $HT), item: T) -> (HT, Error)
remove  :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> Error
get     :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> (T, Error)   // value copy; T{} on error
get_ptr :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> (^T, Error)  // LOAN: dies at next remove/clear/destroy
has     :: proc(p: ^Handle_Pool($T, $HT), h: HT) -> bool
slice   :: proc(p: ^Handle_Pool($T, $HT)) -> []T                 // items[0:count] — self-identifying live items
```

**Amended per-operation contract** (tests enforce exactly this):

| Operation | Behavior | Edge |
|---|---|---|
| `init` | allocate the two arrays from `allocator`; thread freelist 0→cap−1 FIFO; all gens = 1 | assert `0 < capacity < SENTINEL` |
| `destroy` | free both arrays via stored allocator | leak check binds here |
| `add` | dequeue `free_head`; item → `items[count]`; **`items[count].handle` = packed `{slot, gen}` transmuted to HT (caller's field value overwritten)**; `slot.dense_idx = count`; `count += 1`; return that handle | freelist empty → zero HT, `.Full` |
| `remove(h)` | validate; swap `items[count-1]` into the gap; **patch the moved item's slot via `unpack(moved.handle).idx`** → `dense_idx` = hole; `count -= 1`; `gen += 1`; wrapped-to-0 → retired else FIFO-enqueue | invalid → `.Invalid_Handle` |
| validation (`get`/`get_ptr`/`has`/`remove`) | transmute h → u64; `index < capacity` **and** `gen(h) != 0` **and** `slots[index].gen == gen(h)` | garbage-safe: never panics |
| `get` on invalid | `T{}, .Invalid_Handle` | ZII |
| `clear` | **for each live item: bump `slots[unpack(item.handle).idx].gen`** (same retire rule); rebuild freelist; `count = 0` | every prior handle now stale |
| zero handle | `HT{}` transmutes to `u64(0)` → gen 0 never matches (gens start at 1) | the ZII zero of *every* HT fails everywhere |

Borrowing rule unchanged: pointers and slices die at the next `remove`/`clear`/`destroy`; to
remove while iterating, collect handles during the walk, remove after.
