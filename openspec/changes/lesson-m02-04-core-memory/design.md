# Interface design

> **Interface:** learner-designed — the allocator APIs are already agreed (m02-02/03); what's new is how the two allocators are *packaged and named* inside `engine/core`, and how that surface reads at the call site and scales as `core` grows. The `Allocator_Proc` contract is unchanged.

## Learner sketch

I want to have arena_init, pool_init etc. this makes the calls more clear on what it is
And also works well with odin practices
core/mem is fine - only low level code will probably use stdlib core/mem anyways

<!-- [you] Your proposed packaging + naming for the graduated allocators. Address:
       - layout: flat in `package core` (type-prefixed: Arena/arena_init/Pool/pool_init),
         a `mem` sub-package (engine:core/mem — mind the clash with stdlib core:mem),
         or separate sub-packages (engine:core/arena + engine:core/pool)?
       - the resulting public names and how a call site reads (e.g. core.arena_init(...) vs
         mem.arena_init(...) vs arena.init(...))
       - what stays public vs @(private="file") after the move
       - how it scales when core later also holds containers (m03), math (m30), logging
     Short rationale for the choice + the trade you're accepting. See lesson.md §Exercise. -->

## Tutor critique

Prefixed naming is the right instinct — unambiguous at the call site and exactly what Odin's
`core:mem` does (`arena_init`, `pool_init`) [ODIN-MEM]. Two things to settle:

**A — which package holds them (the real fork).** Prefixed names work in either home:
- **`engine:core/mem` sub-package** → `mem.arena_init`, `mem.pool_init`. Mirrors stdlib
  `core:mem` most faithfully, and *scales*: as `core` later gains containers (m03), math (m30),
  logging, each becomes its own sub-package (`engine:core/container`, …) instead of one giant
  flat package. **Gotcha:** the name `mem` clashes with stdlib `core:mem` — any file importing
  both needs an alias (`import cmem "core:mem"`), including the engine mem package itself (it
  uses `mem.align_forward`).
- **Flat in `package core`** → `core.arena_init`, `core.pool_init`. No clash, simplest today;
  the cost is `core` grows into one flat namespace over time.
Both are layering-clean (core-level, importing only `base:runtime` + `core:mem`). I lean the
**sub-package** for scaling + stdlib fidelity, but flat-in-core is a fine "keep it simple" call.

**B — the rename is bigger than it looks.** In ONE package, *every* public proc collides, not
just `init`: your arena and pool both expose `init`, `allocator`, `allocator_proc`, `free_all`,
and `alloc`. So all of them get the type prefix — `arena_init`/`arena_allocator`/
`arena_allocator_proc`/`arena_alloc`/`arena_resize`/`arena_free_all`, and the `pool_*` set. The
types `Arena`/`Pool` are already distinct (no change). Your file-private helpers (`Free_Node`,
`thread_free_list`, `safe_add`, `align_forward`) are file-scoped — no collision, leave them.

## Agreed interface

Locked: **`engine/core/memory/`** as **`package memory`**, imported `import "engine:core/memory"`
→ call sites read `memory.arena_init(...)`, `memory.pool_init(...)`.

*(Why not `mem`: a package named `mem` can't import `core:mem` — Odin errors `Duplicate
declaration of 'package mem'`, and an alias doesn't fix it. Renaming the package to `memory`
sidesteps it entirely — and, because `memory` ≠ `mem`, the package imports `core:mem` with **no
alias**, so your kata code's `mem.` references (`mem.Allocator`, `mem.align_forward_int`,
`mem.byte_slice`, …) carry over verbatim.)*

**Public surface (prefixed):**

```odin
package memory
import "core:mem"   // no alias needed — `mem.` = stdlib

Arena :: struct { data: []byte, offset, prev_offset, peak_used: int }
arena_init           :: proc(a: ^Arena, backing: []byte)
arena_allocator      :: proc(a: ^Arena) -> mem.Allocator
arena_allocator_proc :: proc(allocator_data: rawptr, mode: mem.Allocator_Mode, size, alignment: int, old_memory: rawptr, old_size: int, location := #caller_location) -> ([]byte, mem.Allocator_Error)
arena_alloc          :: proc(a: ^Arena, size, alignment: int, zero: bool) -> ([]byte, mem.Allocator_Error)
arena_resize         :: proc(a: ^Arena, old_memory: rawptr, old_size, size, alignment: int, zero: bool) -> ([]byte, mem.Allocator_Error)
arena_free_all       :: proc(a: ^Arena)

Pool :: struct { data: []byte, block_size, alignment: int, head: ^Free_Node, free_count: int }
pool_init            :: proc(p: ^Pool, backing: []byte, block_size, alignment: int)
pool_allocator       :: proc(p: ^Pool) -> mem.Allocator
pool_allocator_proc  :: proc(/* same shape as arena_allocator_proc */) -> ([]byte, mem.Allocator_Error)
pool_alloc           :: proc(p: ^Pool, size, alignment: int, zero: bool) -> ([]byte, mem.Allocator_Error)
pool_free_block      :: proc(p: ^Pool, block: rawptr)
pool_free_all        :: proc(p: ^Pool)

// ── logging (folded in as a bonus; wraps any allocator) ──
Logging_Allocator :: struct { backing: mem.Allocator, label: string }
logging_allocator_init :: proc(l: ^Logging_Allocator, backing: mem.Allocator, label := "mem")
logging_allocator      :: proc(l: ^Logging_Allocator) -> mem.Allocator
logging_allocator_proc :: proc(/* Allocator_Proc; forwards to l.backing, then prints */) -> ([]byte, mem.Allocator_Error)
```

Bodies unchanged from the katas; only the `package` clause (→ `memory`) and the public names
(→ prefixed) change. File-private helpers (`Free_Node`, `thread_free_list`, `safe_add`, …) carry
over as-is.
