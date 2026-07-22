<!-- TUTORED LESSON — CONSTITUTION (binding)
     Every task carries exactly one owner tag: [tutor] or [you].
     Agent: execute [tutor] tasks in order; HARD-STOP at the first incomplete
     [you] task — summarize state, say exactly what the learner should do, END TURN.
     NEVER write, complete, or check off a [you] deliverable.
     When the learner reports a [you] task done, verify the observable outcome
     (run `odin test`, build the app, check files) before marking it and continuing.
     Full constitution: .claude/skills/tutor/SKILL.md -->

<!-- BUILD (graduate) lesson, interface: LEARNER-DESIGNED (packaging/naming inside
     engine/core + the engine-boundary handle-type decision; m03-02's per-op contract is
     locked and does not reopen). Carries the engine's second spec delta:
     specs/core-containers/spec.md merges into openspec/specs/ at archive. Includes a
     demo checkpoint (the testbed exercises the pool through engine:core) per
     build-lesson rules. -->

## 1. Orient

- [x] 1.1 [tutor] Verify/register cite-keys (registered ODIN-CONTAINER — core:container docs incl. handle_map; GEA, ODIN, FLOOOH, BITSQUID, ZYL-HANDLES already registered); write lesson.md
- [x] 1.2 [you] Read lesson.md; skim core:container/handle_map's API and ZYL's three-implementations post; note questions

## 2. Design

- [x] 2.1 [you] Sketch the surface in design.md §Learner sketch (packaging + naming with both precedents weighed; the shared-Handle vs $HT decision with signatures; ZII survival; render-layer consumption story)
- [x] 2.2 [tutor] Critique the sketch against the cited references; record the agreed surface in design.md §Agreed interface (locked: engine/core/containers/handle_pool · $HT via where size_of + transmute · ready-made Handle kept · Error rename; AMENDED same day per learner proposal: where clause adds type_is_unsigned + T embeds `handle: HT` maintained by the pool · dense_to_slot dropped — see design.md §Design amendment)

## 3. Spec

- [x] 3.1 [tutor] Write the `core-containers` spec delta (specs/core-containers/spec.md — generational-handle storage guarantees, caller-typed + self-identifying items, stale/garbage rejection, iteration, ownership, layering)
- [x] 3.2 [tutor] Write failing conformance tests + red stub against the (amended) agreed surface; verify RED under `-collection:engine=engine`, `-vet -strict-style` clean (16 tests, all RED)

## 4. Build

- [x] 4.1 [you] Move + adapt the handle pool into engine/core per the agreed surface (semantics unchanged); `odin test` green, leak-clean, `-vet -strict-style` clean (verified: 16/16 green, memory tracking clean, vet/style clean)
- [x] 4.2 [you] Wire the demo checkpoint — testbed exercises the pool through engine:core (add / get / mutate / stale-handle-refused / slice); builds and runs clean (verified: heap-tracked, no leaks; stale refusal + loan mutation + self-identifying slice walk all observed; flushed out an init-hardening finding → carried to 5.1)

## 5. Review

- [x] 5.1 [tutor] Verify green + demo + build; review per references/review-rubric.md (layering law; handle-based boundary especially); ask ≥2 comprehension probes (findings: F1 clear walked full array — pinned by new red test; F2 init swallowed alloc failure; F3 nits; layering clean; no tutor-written implementation)
- [x] 5.2 [you] Answer the probes; address review findings (F1+F2 fixed → 17/17 green; pack_handle asymmetry nit also taken; probes: P2+P3 answered well, P1 taught — get_ptr scribble mechanism + pool-owned contract comment added)

## 6. Finalize

- [x] 6.1 [tutor] Run the measurement task (core test/build time + size vs m02-04 baseline; no-regression bench re-run; distinct-type-tax check); record Built + Measured in curriculum/JOURNAL.md (bench: katas/handle_pool_bench_engine)
- [x] 6.2 [tutor] Walk the learner through what the numbers mean
- [x] 6.3 [you] Write Takeaways + Reflections in curriculum/JOURNAL.md (your own words)
- [x] 6.4 [tutor] Copy lesson.md → curriculum/modules/m03/m03-03-core-containers/LESSON.md
- [x] 6.5 [tutor] Update curriculum/curriculum.yaml (m03-03 → done; m10-01 → available; clear active_change)
- [x] 6.6 [tutor] Commit the lesson; hand off to /opsx:archive (syncs the core-containers spec into openspec/specs/)
