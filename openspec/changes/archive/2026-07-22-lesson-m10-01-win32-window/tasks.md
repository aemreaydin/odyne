<!-- TUTORED LESSON — CONSTITUTION (binding)
     Every task carries exactly one owner tag: [tutor] or [you].
     Agent: execute [tutor] tasks in order; HARD-STOP at the first incomplete
     [you] task — summarize state, say exactly what the learner should do, END TURN.
     NEVER write, complete, or check off a [you] deliverable.
     When the learner reports a [you] task done, verify the observable outcome
     (run `odin test`, build the app, check files) before marking it and continuing.
     Full constitution: .claude/skills/tutor/SKILL.md -->

<!-- BUILD lesson, first of Phase 1: platform code built IN PLACE in engine/platform (no
     kata). Interface: LEARNER-DESIGNED (the platform window API; Win32's side is fixed).
     Carries the platform-window spec delta into openspec/specs/ at archive. Demo checkpoint
     is dominant per build-lesson rules: a visible, responsive window closed via ✕ — the
     first observable odyne artifact. Tests run against a HIDDEN window so `odin test` stays
     headless-friendly. -->

## 1. Orient

- [x] 1.1 [tutor] Verify/register cite-keys (registered WIN32 — Learn-Win32 module + API ref; ODIN-SYS — core:sys/windows bindings; HMH, GEA, ODIN already registered); write lesson.md
- [x] 1.2 [you] Read lesson.md; read the Learn-Win32 module through "Closing the Window"; watch HMH day 2; skim core:sys/windows for RegisterClassExW/CreateWindowExW/PeekMessageW; note questions

## 2. Design

- [x] 2.1 [you] Sketch the platform window API in design.md §Learner sketch (surface + boundary type + event path + file split; no OS types in public signatures)
- [x] 2.2 [tutor] Critique the sketch against the cited sources; record the agreed surface in design.md §Agreed interface (locked: handle-in-GWLP_USERDATA — Q1 corrected: the swap's victim is the SURVIVING window; create/destroy_window + poll_events naming; hidden flag; state queries now, queue in m10-02; global pump; single-threaded contract)
## 3. Spec

- [x] 3.1 [tutor] Write the `platform-window` spec delta (specs/platform-window/spec.md — lifecycle, close-as-request, non-blocking pump, OS-type confinement + survivor-window independence, headless windows)
- [x] 3.2 [tutor] Write failing tests (hidden-window lifecycle incl. the Q1 swap-survival test) + red stubs (window.odin types; window_windows.odin stub with Window_State/pool declared); verify RED under `-collection:engine=engine -define:ODIN_TEST_THREADS=1`, `-vet -strict-style` clean (8 tests, all RED)

## 4. Build

- [x] 4.1 [you] Implement the window in engine/platform (class registration, CreateWindowExW, WndProc + GWLP_USERDATA plumbing, PeekMessageW pump, destroy); `odin test` green, leak-clean, vet/style clean (verified: 8/8 green incl. the swap-survival routing test; debugging journey: cbSize, class re-registration, handle-vs-stack-pointer in USERDATA, client-vs-outer size, ZII named-return)
- [x] 4.2 [you] Wire the demo checkpoint — testbed opens a visible titled window, stays responsive (move/resize), exits cleanly on ✕ (verified: observed black-brushed resizable window, clean exit + leak report; en route fixed inverted success guard, LIFO defer order, missing background brush)

## 5. Review

- [x] 5.1 [tutor] Verify green + demo + build; review per references/review-rubric.md (OS-type confinement and layering especially; WndProc context discipline); ask ≥2 comprehension probes (findings: F1 stale stub header, F2 iterate-while-removing shutdown, F3/F4 nits; confinement + layering verified by grep; no tutor-written implementation — rung-3 pseudocode given once for the USERDATA scheme)
- [x] 5.2 [you] Answer the probes; address review findings (F1+F2 fixed, 8/8 green; F3/F4 left as-is, logged; probes: message-trace + context answered after teach-back, thread-affinity corrected via re-probe — queue ownership now solid)

## 6. Finalize

- [x] 6.1 [tutor] Run the measurement task (empty-pump ns/frame; init→visible ms; build time + size vs m03-03's 472,576 B); record Built + Measured in curriculum/JOURNAL.md (bench: katas/window_pump_bench)
- [x] 6.2 [tutor] Walk the learner through what the numbers mean
- [x] 6.3 [you] Write Takeaways + Reflections in curriculum/JOURNAL.md (your own words)
- [x] 6.4 [tutor] Copy lesson.md → curriculum/modules/m10/m10-01-win32-window/LESSON.md
- [x] 6.5 [tutor] Update curriculum/curriculum.yaml (m10-01 → done; m10-02 → available; clear active_change)
- [x] 6.6 [tutor] Commit the lesson; hand off to /opsx:archive (syncs the platform-window spec into openspec/specs/)
