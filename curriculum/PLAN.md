# The odyne curriculum plan

The journey: from "I write C++ daily but have never written Odin" to a small 3D game
running on a renderer with two backends (Vulkan and DX12) — every line of engine code
written by you. Twenty-one modules across six phases. `curriculum.yaml` is the
machine-readable source of truth (lesson-level detail lives only there); this document
is the narrative — what each phase is for and why it sits where it does.

## How lessons work

One lesson = one OpenSpec change under the `lesson` schema (see the tutor skill).
The tutor explains with citations, you sketch the interface, the tutor writes failing
tests, you implement to green, the tutor reviews. Five lesson types: `concept`
(reading/understanding), `kata` (isolated exercise under `katas/`), `build` (code
landing in `engine/`), `design` (the deliverable is a design), `milestone` (a playable
thing).

**The kata→graduate rhythm:** fundamentals are first built in isolation where they can
be unit-tested and benchmarked without ceremony (arena allocator, handle pool, job
queue, ECS storage), then a short *graduate* build lesson moves them into `engine/`
behind the layering law (`core → platform → render → game`, dependencies point down
only). You learn the idea in a clean room, then pay the integration costs deliberately.

## The phases

### Phase 0 — Foundations
*Odin for C++ programmers → Tooling & project skeleton → Memory & allocators → Containers & handles.*

Everything here is `core` layer. Odin first, as deltas from C++ (`defer` vs RAII,
`context` vs singletons, ZII vs constructors); then the project skeleton with the
layered packages; then the engine's real spine: allocators (arena, pool — the topics
Odin's own creator writes about) and handle-based containers. Handles-not-pointers is
the package-boundary discipline every later layer builds on.

### Phase 1 — Platform
*Window & input → timing & main loop.*

The first thing you can *see*: a window, real input, a high-resolution clock, and a
fixed-timestep main loop. Small on purpose — the platform layer exists to be boring
and correct.

This phase was first built hand-rolled on Win32, then partly again on Cocoa, before
being moved onto SDL3 in July 2026 (see the amendment in `curriculum.yaml`). What
that migration made obvious is the point of the phase: `window.odin` and `input.odin`
— the handle pool, the frame-coherent snapshot, the edge algebra — did not change a
line. Swapping the OS underneath a seam without disturbing what sits above it is the
seam working, and it is the same move Phase 5 makes again for the renderer.

### Phase 2 — Renderer I (Vulkan 2D)
*Vulkan bootstrap → First triangle → GPU resources → 2D sprite renderer.*

The famous wall, split into ten small lessons with a demo checkpoint each ("run it;
you should see X"). The mental-model lesson comes first because Vulkan's difficulty
is conceptual, not syntactic. The phase ends with a designed-by-you sprite batch API
and a debug stats overlay — the tools Breakout needs. Handle discipline applies: no
`vk*` types escape the Vulkan package.

### Phase 3 — Game & Milestone 1: **Breakout**
*Game math → Entities & game loop → Audio → Milestone: Breakout.*

Math uses `core:math/linalg` plus hand-written collision — Odin ships the vectors;
your learning budget goes to the geometry. Entities are deliberately simple
(handle-indexed arrays, no ECS yet): feel the approach's limits first, study the fix
in phase 4. Audio lands *before* the milestone — minimal (WASAPI output + a mixer) —
because a silent Breakout is a worse Breakout; it hangs off the platform layer, so
it's also a palate cleanser available during the Vulkan grind. The milestone closes
with a retrospective: what was missing, what hurt — that list drives phase 4.

### Phase 4 — Engine systems
*Asset pipeline & hot reload · Job system · ECS & data-oriented design · Renderer II (3D).*

All four modules unlock together when Breakout ships — pick your order by interest or
by what the retrospective exposed (3D rendering additionally wants the asset pipeline
first, for model loading). This is the deep-engine phase: the job system studies the
fiber model used at Naughty Dog; the ECS module is the data-oriented-design capstone
and naturally ports Breakout's game objects; Renderer II takes the Vulkan renderer to
depth, meshes, cameras, lighting, and glTF.

### Phase 5 — RHI & Milestone 2: **Game 2**
*RHI seam → DX12 backend → Milestone: Game 2.*

The render-hardware-interface seam is designed only now, *after* one backend and two
usage profiles (2D batch, 3D meshes) exist — abstractions are extracted from
experience, not speculated. The DX12 backend then validates the seam, ending with the
same scene rendered on both backends. Game 2 — a small 3D game whose design is chosen
at the milestone itself, informed by everything before it — is the integration test of
the whole curriculum: it requires the DX12 backend, the job system, and the ECS.

## Milestones gate progress

Nothing in phase 4 opens until Breakout is `done`; Game 2 closes the curriculum.
Milestones end with a retrospective journal entry, and that retrospective is the
designated moment to **re-plan**: locked modules may be added, resized, or reordered
via a small OpenSpec change touching `curriculum.yaml` and this plan together.
`done` lessons are never rewritten; statuses only move forward.
