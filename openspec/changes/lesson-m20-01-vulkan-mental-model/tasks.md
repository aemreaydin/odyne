<!-- TUTORED LESSON — CONSTITUTION (binding)
     Every task carries exactly one owner tag: [tutor] or [you].
     Agent: execute [tutor] tasks in order; HARD-STOP at the first incomplete
     [you] task — summarize state, say exactly what the learner should do, END TURN.
     NEVER write, complete, or check off a [you] deliverable.
     When the learner reports a [you] task done, verify the observable outcome
     (run `odin test`, check files) before marking it and continuing.
     Full constitution: .claude/skills/tutor/SKILL.md -->

<!-- Concept lesson: Design/Spec/Build groups dropped per references/lesson-types.md;
     Review uses recall questions instead of a diff review. design.md = "Not applicable". -->

## 1. Orient

- [x] 1.1 [tutor] Verify + register cite-keys KHR-GUIDE, MOLTENVK, VKLOADER, VKPORT, VKPROFILES, VMA in BIBLIOGRAPHY.md; widen ODIN-SRC to `vendor/vulkan`; refresh VKGUIDE + VKSPEC notes; write lesson.md
- [x] 1.2 [tutor] Amend lesson.md per learner direction (2026-07-29): add §Capabilities (four axes, query-vs-enable, branch-on-capability-never-on-platform, three fallback shapes, modern-path-first), reframe the MoltenVK section as an instance of it, add the profiles-layer fallback-testing route, record the m20-02 constraints in design.md
- [x] 1.3 [you] Read lesson.md and the required reading ([KHR-GUIDE What is Vulkan], [VKGUIDE Vulkan API intro], [VKSPEC §Fundamentals] — Object Model, Execution Model, Valid Usage; plus the two short [KHR-GUIDE] pages: Release Summary, Enabling Features); note questions

## 2. Review

- [x] 2.1 [you] Answer the 11 recall questions from lesson.md §Exercise, in your own words
- [x] 2.2 [tutor] Review the answers against the sources; correct misconceptions; ask ≥2 follow-up probes
- [x] 2.3 [you] Answer the probes

## 3. Finalize

- [x] 3.1 [tutor] Run the measurement task (four-axis capability census via `vulkaninfo`; the same census under `VK_LAYER_KHRONOS_profiles` at a Vulkan 1.2 baseline, recording the diff; `vkcube` under `VK_LAYER_LUNARG_api_dump` for setup/per-frame call counts and validation-layer frame-time delta; `vendor:vulkan` import build cost + `glslc` SPIR-V baseline); record Built + Measured in curriculum/JOURNAL.md
- [x] 3.2 [tutor] Walk the learner through what the numbers mean
- [x] 3.3 [you] Write Takeaways + Reflections in curriculum/JOURNAL.md (your own words)
- [x] 3.4 [tutor] Copy lesson.md → curriculum/modules/m20/m20-01-vulkan-mental-model/LESSON.md
- [x] 3.5 [tutor] Update curriculum/curriculum.yaml (m20-01 → done; m20-02 → available; clear active_change)
- [ ] 3.6 [tutor] Commit the lesson; hand off to /opsx:archive
