# Design: add-engine-curriculum

## Context

The tutor infrastructure (Change 1) is live: lesson schema, tracking format, bibliography rules. `curriculum.yaml` is an empty shell whose comments promise phases 0–5, a kata→graduate rhythm, Breakout and Game 2 milestones, and an RHI design lesson. This change decides the actual content: which modules exist, what each lesson is, what depends on what, and which sources seed the bibliography. Scope was confirmed with the learner: full arc through a **3D Game 2 on a DX12 backend**, with dedicated modules for **job system, asset pipeline + hot reload, audio, and ECS**.

## Goals / Non-Goals

**Goals:**
- A complete, prerequisite-sound module DAG from "Odin for C++ programmers" to Game 2 on DX12.
- Lessons sized so one lesson ≈ one or a few tutored sessions, typed per `references/lesson-types.md`.
- A seed bibliography that covers every phase's domain with verified sources, so no lesson is blocked on source-hunting.
- A narrative `curriculum/PLAN.md` so the learner can see the shape of the journey without parsing YAML.

**Non-Goals:**
- Authoring any lesson content (each lesson is its own future OpenSpec change under the `lesson` schema).
- Engine code, repo skeleton beyond what lessons themselves create, SDK installation.
- Pinning Game 2's exact game design now — the Breakout retrospective and phase-4 experience inform it (the milestone slot is reserved; its design happens in that lesson).

## Decisions

### D1: The module DAG

Twenty-one modules, 49 lessons, six phases. Lessons within a module are implicitly linear (intra-module predecessors, per the tracking spec). The table below is the canonical plan; `curriculum.yaml` is its machine encoding.

| Phase | Module | Requires | Lessons (id · slug · type) |
|---|---|---|---|
| 0 Foundations | `m00` Odin for C++ programmers | — | m00-01 odin-tour (concept) · m00-02 odin-kata (kata) |
| 0 | `m01` Tooling & project skeleton | m00 | m01-01 skeleton (build) |
| 0 | `m02` Memory & allocators | m01 | m02-01 allocators (concept) · m02-02 arena (kata) · m02-03 pool (kata) · m02-04 core-memory (build, graduate) |
| 0 | `m03` Containers & handles | m02 | m03-01 handles (concept) · m03-02 handle-pool (kata) · m03-03 core-containers (build, graduate) |
| 1 Platform | `m10` Window & input | m03 | m10-01 win32-window (build) · m10-02 input (build) |
| 1 | `m11` Timing & main loop | m10 | m11-01 timing (kata) · m11-02 main-loop (build) |
| 2 Renderer I (Vulkan 2D) | `m20` Vulkan bootstrap | m11 | m20-01 vulkan-mental-model (concept) · m20-02 instance-device (build) · m20-03 swapchain (build) |
| 2 | `m21` First triangle | m20 | m21-01 shaders-pipeline (build) · m21-02 triangle (build) |
| 2 | `m22` GPU resources | m21 | m22-01 buffers (build) · m22-02 textures (build) |
| 2 | `m23` 2D sprite renderer | m22 | m23-01 sprite-api (design) · m23-02 sprite-batch (build) · m23-03 debug-overlay (build) |
| 3 Game & Milestone 1 | `m30` Game math | m23 | m30-01 linalg-collision (kata) |
| 3 | `m31` Entities & game loop | m30 | m31-01 entities (build) |
| 3 | `m32` Audio | m11 | m32-01 audio-concepts (concept) · m32-02 wasapi-output (build) · m32-03 mixer (build) |
| 3 | `m33` **Breakout** | m31, m32 | m33-01 breakout (milestone) |
| 4 Engine systems | `m40` Asset pipeline & hot reload | m33 | m40-01 asset-concepts (concept) · m40-02 asset-loader (build) · m40-03 hot-reload (build) |
| 4 | `m41` Job system | m33 | m41-01 concurrency-model (concept) · m41-02 job-queue (kata) · m41-03 jobs (build, graduate) |
| 4 | `m42` ECS & data-oriented design | m33 | m42-01 dod (concept) · m42-02 ecs-storage (kata) · m42-03 ecs (build, graduate) |
| 4 | `m43` Renderer II (3D) | m40 | m43-01 3d-pipeline (concept) · m43-02 mesh-camera (build) · m43-03 lighting (build) · m43-04 gltf-models (build) |
| 5 RHI & Milestone 2 | `m50` RHI seam | m43 | m50-01 rhi-design (design) · m50-02 rhi-refactor (build) |
| 5 | `m51` DX12 backend | m50 | m51-01 dx12-deltas (concept) · m51-02 dx12-device (build) · m51-03 dx12-parity (build) |
| 5 | `m52` **Game 2** | m51, m41, m42 | m52-01 game2 (milestone) |

- *Alternative considered:* fewer, fatter modules (one "Vulkan" module). Rejected: lesson statuses are the progress ratchet, and Vulkan bring-up is exactly where learners stall — finer gating keeps each session's goal small and the "you are here" honest.

### D2: Audio before Breakout, small

Breakout with no sound is a worse milestone (the lesson-types spec wants a *playable thing*; the retrospective should be about engine gaps, not missing senses). So `m32` lands in phase 3 with a deliberately minimal scope — WASAPI output + a mixing layer — and deeper audio work (DSP, spatialization) is deliberately absent; if Game 2 needs it, the Breakout/phase-4 retrospectives can add a module. `m32` hangs off `m11` (platform), not the renderer, so it can also serve as a change of pace during the Vulkan grind.

### D3: Math via `core:math/linalg`, not a hand-rolled library

Odin ships vectors/matrices with array programming built into the language — hand-rolling a math library teaches C++ habits, not Odin. `m30` is one kata: *use* linalg idiomatically (a C++-delta goldmine: swizzles and array arithmetic vs operator-overload culture) and implement the collision routines Breakout actually needs (AABB, sweep). Rejected alternative: a full math-library module, the traditional engine-course opener — low learning yield for this learner.

### D4: Plain entities for Breakout; ECS as a phase-4 refactor

Breakout ships on simple handle-indexed arrays (`m31`), deliberately *before* the learner studies ECS. The pain (or absence of pain) of that approach is the data the DOD module (`m42`) builds on, and porting Breakout's game objects is `m42-03`'s natural exercise. This sequencing — feel the problem, then study the solution — is the curriculum's core pedagogical bet.

### D5: RHI designed only after two concrete renderers exist

`m50-01` (the design lesson) requires phase 2 *and* the 3D renderer (`m43`): an abstraction seam extracted from one backend and two usage profiles (2D batch, 3D meshes) instead of speculation. DX12 (`m51`) then *validates* the seam — its parity lesson renders the same demo scene on both backends. Rejected alternative: design the RHI before the renderer (abstraction-first); that's how you get an API shaped like a tutorial instead of like your engine.

### D6: Milestones gate phases; phase 4 is deliberately parallel

`m33` (Breakout) is the sole prerequisite of `m40`/`m41`/`m42`, which unlock *together* — after the retrospective the learner picks their order by interest or by what Breakout exposed. Everything funnels back into `m52` (Game 2), which requires the DX12 backend plus jobs and ECS, making it the integration test of the whole curriculum.

### D7: Seed statuses

`m00-01` is `available`; every other lesson is `locked`; `active_change: null`. Forward-only transitions from there per the tracking spec.

### D8: Seed bibliography — minimal but phase-covering

One+ verified source per phase domain, registered now so no early lesson stalls on source verification: **GEA** (Gregory, *Game Engine Architecture* 3e — spine of the whole course), **ODIN** (official overview docs), **GB-MEM** (gingerBill's memory-allocation series), **VKGUIDE** (vkguide.dev), **VKSPEC** (Vulkan spec/registry), **RTR** (*Real-Time Rendering* 4e), **HMH** (Handmade Hero — platform/WASAPI episodes), **ND-FIBERS** (GDC: Parallelizing the Naughty Dog Engine), **ECS-FAQ** (Sander Mertens), **DX12** (Microsoft Learn D3D12 programming guide), **GLTF** (glTF 2.0 spec). Each entry is link-verified at implementation time per the bibliography spec; per-lesson sources are added as lessons start.

### D9: `PLAN.md` is narrative, `curriculum.yaml` is data

The YAML stays exactly the tracking-spec shape (no prose beyond its header comment). `PLAN.md` carries the journey description, per-phase rationale, the kata→graduate rhythm, and the re-planning rule (D10). Duplication is limited to module titles; lesson-level detail lives only in YAML to avoid drift.

### D10: The DAG is re-plannable at milestones

Milestone retrospectives (already required by lesson-types) are the designated moments to amend the curriculum — add/resize/reorder *locked* modules via a small OpenSpec change touching `curriculum.yaml` + `PLAN.md`. Done lessons are never rewritten; statuses stay forward-only.

## Risks / Trade-offs

- [49 lessons is a long road; motivation risk] → Phases 0–3 are front-loaded with visible wins (window by phase 1, triangle in phase 2, playable game in phase 3); D6 gives choice after Breakout; D10 allows shrinking later phases without rework.
- [Vulkan phase is the classic stall point] → Split into 4 modules / 10 small lessons with demo checkpoints each; `m32` (audio) is available in parallel as a palate cleanser.
- [Planned lesson granularity may prove wrong once real lessons run] → Lesson ids/slugs for *locked* lessons can be amended under D10; only `done` history is immutable.
- [Seed sources may move or 404 at implementation time] → Verification happens during apply (web fetch); a dead link means substitute and verify, never register unverified.
- [DX12 on this DAG assumes Windows remains the dev platform] → True for this learner (Win32 platform module already assumes it); a future platform module is a D10 amendment if that changes.

## Open Questions

- Game 2's concrete design (genre, scope) — intentionally deferred to the `m52-01` lesson, informed by the phase-4 retrospectives (D10).
