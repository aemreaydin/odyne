# Tasks: add-engine-curriculum

(Infrastructure change, not a lesson — no `[you]` implementation work; the learner reviews.)

## 1. Seed bibliography

- [x] 1.1 Verify each seed source from design D8 (web fetch/search: live URL, or real ISBN/publisher page for books; exact title and author)
- [x] 1.2 Register verified entries in `curriculum/BIBLIOGRAPHY.md` in the entry format, with today's Verified date and one-line Notes; substitute and re-verify any dead source rather than registering it unverified
- [x] 1.3 Cross-check phase coverage: every phase 0–5 domain (engine architecture, Odin, memory, Vulkan, real-time rendering, platform/audio, concurrency, ECS, D3D12, glTF) has at least one entry

## 2. Populate curriculum.yaml

- [x] 2.1 Encode the D1 module table into `curriculum/curriculum.yaml`: 21 modules with id, title, phase, requires; 49 lessons with id, slug, title, type
- [x] 2.2 Seed statuses per D7: `m00-01` `available`, all other lessons `locked`, `active_change: null`
- [x] 2.3 Validate against the spec deltas: phases respect prerequisite ordering, DAG acyclic and rooted at m00, milestone gating (m33 gates all phase-4 modules; m52 requires m51+m41+m42), kata modules contain graduate builds, RHI module requires m43 (script: `validate_curriculum.mjs` — all checks pass)
- [x] 2.4 Confirm the YAML parses (`npx js-yaml` → JSON, consumed by the validation script) and field names match the curriculum-tracking spec exactly

## 3. Write PLAN.md

- [x] 3.1 Write `curriculum/PLAN.md`: the six phases with per-phase rationale (D2–D6 narratives), the kata→graduate rhythm, milestone gating, and the D10 re-planning rule
- [x] 3.2 Consistency pass: module names/order in PLAN.md match curriculum.yaml; lesson-level detail appears only in the YAML

## 4. Review & finalize

- [x] 4.1 Learner reviews the full curriculum (PLAN.md + curriculum.yaml) and requests adjustments; apply them across both files (reviewed 2026-06-12: approved as-is; GEA 4e confirmed as the learner's copy)
- [x] 4.2 Run `openspec validate add-engine-curriculum` (or equivalent status check) and fix any artifact issues
- [x] 4.3 Commit the change (c9d7844); after archive, confirm `openspec/specs/engine-curriculum/spec.md` exists and the tutor's "status" view renders the new tree with m00-01 as the next available lesson
