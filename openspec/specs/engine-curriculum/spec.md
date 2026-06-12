# engine-curriculum Specification

## Purpose
TBD - created by syncing change add-engine-curriculum. Update Purpose after archive.
## Requirements
### Requirement: Phase structure
The curriculum SHALL organize modules into six ordered phases: 0 Foundations (Odin, tooling, memory, containers), 1 Platform, 2 Renderer I (Vulkan 2D), 3 Game & Milestone 1, 4 Engine systems (assets, jobs, ECS, 3D rendering), 5 RHI & Milestone 2 (DX12, Game 2). Every module SHALL belong to exactly one phase, and no module SHALL list a prerequisite from a higher-numbered phase.

#### Scenario: Prerequisites respect phase order
- **WHEN** any module in `curriculum.yaml` is inspected
- **THEN** each of its prerequisite module ids resolves to a module whose phase number is less than or equal to its own

### Requirement: DAG soundness
The module prerequisite graph SHALL be acyclic, every prerequisite id SHALL resolve to a defined module, and every module except the root SHALL be reachable from `m00` by following prerequisite edges backward.

#### Scenario: Curriculum is loadable as a DAG
- **WHEN** `curriculum.yaml` is parsed and prerequisite edges are followed
- **THEN** no cycle exists and no edge points to an undefined module id

### Requirement: Milestone gating
Phase 3 SHALL culminate in a Breakout `milestone` lesson and phase 5 in a Game 2 `milestone` lesson. Every phase-4 module SHALL list the Breakout module among its prerequisites (directly or transitively), and the Game 2 module SHALL require the DX12 backend, job system, and ECS modules.

#### Scenario: Phase 4 is locked until Breakout
- **WHEN** the Breakout milestone lesson is not `done`
- **THEN** every phase-4 lesson has status `locked`

#### Scenario: Game 2 integrates the systems phases
- **WHEN** the Game 2 module's transitive prerequisites are computed
- **THEN** they include the DX12 backend, job system, and ECS modules

### Requirement: Kata graduation
Every module containing a `kata` lesson whose code is destined for the engine SHALL also contain a subsequent `build` lesson in the same module that integrates (graduates) the kata code into `engine/`.

#### Scenario: Kata is followed by a graduate build
- **WHEN** a module's kata produces engine-bound code (e.g., arena allocator, handle pool, job queue, ECS storage)
- **THEN** a later lesson in that module is of type `build` and its scope is the integration of that code

### Requirement: RHI lesson placement
The RHI seam `design` lesson SHALL be reachable only after both the 2D sprite renderer and the 3D renderer modules are `done`, so the abstraction is extracted from two concrete usage profiles of a working backend.

#### Scenario: RHI design stays locked without 3D experience
- **WHEN** the 3D renderer module is not `done`
- **THEN** the RHI seam module's lessons have status `locked`

### Requirement: Seed bibliography coverage
For every phase, `curriculum/BIBLIOGRAPHY.md` SHALL contain at least one registered, link-verified source covering that phase's domain before the phase's first lesson can start. This change SHALL seed entries covering all six phases (engine architecture, Odin language, memory, Vulkan, real-time rendering, platform/audio, concurrency, ECS, D3D12, glTF).

#### Scenario: A phase's first lesson starts
- **WHEN** the first lesson of any phase becomes `active`
- **THEN** the bibliography already contains at least one verified entry whose scope covers that phase's domain

### Requirement: Seed state
When seeded, `curriculum.yaml` SHALL have `active_change: null`, exactly one lesson with status `available` (the curriculum root, m00-01), and every other lesson `locked`.

#### Scenario: Fresh curriculum after this change
- **WHEN** `curriculum.yaml` is read immediately after this change is applied
- **THEN** m00-01 is `available`, no lesson is `active` or `done`, and `active_change` is null

### Requirement: Narrative plan document
The curriculum SHALL include `curriculum/PLAN.md` describing the phases and their rationale, the kata→graduate rhythm, milestone gating, and the re-planning rule (locked modules may be amended at milestone retrospectives via an OpenSpec change; `done` history is never rewritten). Module-level structure in `PLAN.md` SHALL stay consistent with `curriculum.yaml`; lesson-level detail SHALL live only in `curriculum.yaml`.

#### Scenario: Learner reads the plan
- **WHEN** the learner opens `curriculum/PLAN.md`
- **THEN** it names the same phases and modules as `curriculum.yaml` and explains why they are ordered as they are

#### Scenario: Curriculum amended at a milestone
- **WHEN** a milestone retrospective leads to a curriculum change
- **THEN** `curriculum.yaml` and `PLAN.md` are updated together in one OpenSpec change and previously `done` lessons are untouched
