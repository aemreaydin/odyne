# Proposal: add-engine-curriculum

## Why

The learning infrastructure (tutor skill, lesson workflow, progress tracking) exists, but `curriculum.yaml` has an empty module list and the bibliography has zero registered sources — there is nothing to learn yet and nothing the tutor may cite. This change authors the curriculum itself: the full module DAG from "Odin for C++ programmers" through a 3D Game 2 running on a DX12 backend, plus the seed bibliography that makes cited lessons possible.

## What Changes

- Populate `curriculum/curriculum.yaml` with the complete module DAG across phases 0–5:
  - **Phase 0 — Foundations**: Odin for C++ programmers, tooling/project skeleton, memory & allocators, core containers & handles.
  - **Phase 1 — Platform**: Win32 window & input, timing & main loop, file I/O.
  - **Phase 2 — Renderer I (Vulkan 2D)**: Vulkan bootstrap, pipelines & first triangle, buffers/images/textures, 2D sprite batch.
  - **Phase 3 — Game & Milestone 1**: math & game loop integration, entities, audio fundamentals, **Breakout** milestone.
  - **Phase 4 — Engine systems**: asset pipeline + hot reload, job system / multithreading, ECS & data-oriented game objects, Renderer II (3D: depth, meshes, camera, lighting).
  - **Phase 5 — RHI & Milestone 2**: RHI seam design, DX12 backend bring-up, **Game 2** (small 3D game) milestone.
  - Each lesson carries id, slug, title, type (`concept | kata | build | design | milestone`), and status; first lesson(s) of phase 0 start `available`, everything else `locked` per prerequisites.
- Seed `curriculum/BIBLIOGRAPHY.md` with verified core sources (Game Engine Architecture, vkguide, Odin docs/overview, gingerBill's memory allocation series, Real-Time Rendering, Naughty Dog fibers talk, D3D12/Vulkan official docs, plus audio/ECS references) — every entry link-verified per the bibliography spec before registration.
- Add a human-readable curriculum plan document (`curriculum/PLAN.md`) describing the phases, the rationale for ordering, the kata→graduate rhythm, and where the milestones gate progression — the narrative companion to the machine-readable DAG.

Out of scope: lesson content itself (each lesson is authored as its own OpenSpec change under the `lesson` schema when it starts), engine code, Vulkan SDK setup.

## Capabilities

### New Capabilities
- `engine-curriculum`: Requirements on the curriculum content — phase ordering and module DAG soundness (acyclic, prerequisites reflect real knowledge dependencies), lesson-type composition (katas graduate into builds; every phase past 0 ends in something runnable; milestones close phases 3 and 5), the design lesson placement for the RHI seam, and the seed-bibliography coverage rule (every phase's topics have at least one registered source before its first lesson can start).

### Modified Capabilities
(none — `curriculum-tracking`, `bibliography`, `lesson-workflow`, and `tutor-constitution` requirements are unchanged; this change supplies content that conforms to them)

## Impact

- Modified files: `curriculum/curriculum.yaml` (modules seeded), `curriculum/BIBLIOGRAPHY.md` (seed entries).
- New files: `curriculum/PLAN.md`, `openspec/specs/engine-curriculum/spec.md` (on archive).
- No engine code, no dependencies. Requires web access during implementation to verify bibliography links.
