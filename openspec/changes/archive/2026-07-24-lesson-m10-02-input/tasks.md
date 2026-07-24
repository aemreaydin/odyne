<!-- TUTORED LESSON — CONSTITUTION (binding)
     Every task carries exactly one owner tag: [tutor] or [you].
     Agent: execute [tutor] tasks in order; HARD-STOP at the first incomplete
     [you] task — summarize state, say exactly what the learner should do, END TURN.
     NEVER write, complete, or check off a [you] deliverable.
     When the learner reports a [you] task done, verify the observable outcome
     (run `odin test`, build the app, check files) before marking it and continuing.
     Full constitution: .claude/skills/tutor/SKILL.md -->

<!-- BUILD lesson: input built IN PLACE in engine/platform, extending m10-01's window
     system (WndProc grows key/mouse/wheel/focus cases). Interface: LEARNER-DESIGNED —
     including the decision m10-01 deferred here: event queue vs snapshot polling.
     Carries the platform-input spec delta into openspec/specs/ at archive. Tests drive a
     HIDDEN window via PostMessageW (deterministic, focus-independent) so `odin test`
     stays headless; single-threaded runner as m10-01 (-define:ODIN_TEST_THREADS=1).
     Demo checkpoint: testbed shows live mouse/key readout; Esc requests close. -->

## 1. Orient

- [x] 1.1 [tutor] Verify cite anchors (WIN32 keyboard-input / mouse-clicks / mouse-movement / wm-mousewheel / wm-killfocus / about-raw-input pages; HMH day 6; GEA 3e ch.9 TOC incl. §9.5; ODIN enumerated-array + bit-sets anchors — all under already-registered keys, nothing new to register); write lesson.md
- [x] 1.2 [you] Read lesson.md; read Learn-Win32 Keyboard Input + Responding to Mouse Clicks + Mouse Movement; watch HMH day 6 (keyboard segment); skim GEA ch.9 (§9.5 especially); note questions

## 2. Design

- [x] 2.1 [you] Sketch the platform input API in design.md §Learner sketch (sketched file split, enum coverage, per-window scope; read model + policies resolved via research Q&A — registered GLFW + SDL as sources)
- [x] 2.2 [tutor] Critique the sketch against the cited sources; record the agreed surface in design.md §Agreed interface (locked: mechanism C half-transition counts — Q1 corrected: the tap is lost within the drain, not between frames; snapshot read model, queue deferred with the m10-01 forecast overturned; silent clear on WM_KILLFOCUS; L/R modifiers; f32 wheel detents; capture now; WM_CHAR deferred)

## 3. Spec

- [x] 3.1 [tutor] Write the `platform-input` spec delta (specs/platform-input/spec.md — portable currency incl. L/R modifiers, frame-coherent snapshot with transition capture, repeat-no-edge, mouse position/buttons/wheel, silent focus-loss clear, per-window routing, sys-keys observed-not-consumed)
- [x] 3.2 [tutor] Write failing tests (14 PostMessageW-driven hidden-window tests) + red stubs (input.odin types; input_windows.odin ZII-body stubs — NOT unimplemented(): a panic skips the deferred shutdown and wedges the single-threaded runner, so every test carries a positive-path assertion instead); verified RED: 14/14 input tests fail, 8/8 window tests green, leak-clean, `-vet -strict-style` clean

- [x] 2.3 [tutor+you] Mid-build design conversation (learner-raised): focus/capture API surface. Locked and recorded in design.md §Amendment — has_focus level query (no edge procs); cursor persists through focus loss (overriding the code's zeroing); capture stays private (cursor MODE is the future public knob, m43) with WM_CAPTURECHANGED chord-end reconciliation implemented now
- [x] 3.3 [tutor] Follow-up tests for the two demo-only contract gaps (learner-requested): probe showed capture IS headlessly observable (GetCapture on a hidden window) → test_input_capture_follows_buttons added RED + capture requirement added to the spec delta; probe showed posted synthetic Alt+F4 does NOT traverse DefWindowProc's SC_CLOSE path on a hidden window → sys-key fall-through stays demo-verified, probe result documented in the test file

- [x] 3.4 [tutor] Amendment spec scenarios (focus observable, cursor persists, stolen capture) + red tests + stubs (`focused` field, `has_focus` ZII stub); verified 26 tests: 22 green, 4 RED (capture chord, has_focus, cursor persistence, stolen capture)

## 4. Build

- [x] 4.1 [you] Implement input in engine/platform (WndProc key/mouse/wheel/focus cases, VK→Key translation, snapshot/queue bookkeeping in poll_events, public queries); `odin test` green, leak-clean, vet/style clean (verified: 22/22 green incl. the tap test; flip-and-count process_state; scancode/extended L/R resolve; learner added set_should_close; debugging journey: killfocus routing, .Unknown recorded, wheel overwrite+no-reset; OUTSTANDING before review: sys-key DefWindowProc fall-through, SetCapture/ReleaseCapture)
- [x] 4.15 [you] Implement the design amendment + outstanding contract items: sys-key DefWindowProc fall-through · chord capture + WM_CAPTURECHANGED reconciliation · has_focus (WM_SETFOCUS case + wm_kill_focus) · cursor persists in the focus-loss clear; all 26 tests green, vet/style clean (verified 2026-07-24: 26/26 green under -vet -strict-style; syskey fall-through in wm_input; debugging journey: one-directional buttons_down set → capture never released; update_capture state-before-syscall reorder made holds_capture a valid initiated-by-me discriminator; wm_capture_changed branches were inverted — benign pre-reorder, edge-destroying post-reorder, caught by the mouse_button_edges regression)
- [x] 4.2 [you] Wire the demo checkpoint — testbed shows live mouse position + buttons + last key (title bar or console) and Esc requests close through the same path as ✕ (verified 2026-07-24: title-bar readout, mouse_down chord loop, last_key persisted as value with per-frame temp free_all; learner added set_window_title to platform — recorded as design.md amendment 4; title-set-on-change declined as unnecessary for a testbed. Alt+F4 fall-through: confirm at demo before finalize)

## 5. Review

- [x] 5.1 [tutor] Verify green + demo + build; review per references/review-rubric.md (OS-type/VK confinement, layering, WndProc discipline, frame-coherence semantics); ask ≥2 comprehension probes (done 2026-07-24: 27/27 green -vet -strict-style, testbed builds; findings — killfocus capture leak [fixed, test-enforced], wm_input tail [fixed], dead consts + shadowing [fixed], hwnd_of privacy [retracted, #+private already present], testbed readout gaps [fixed]; probes P1/P2 answered — P1 counter recount 2→4 caught and corrected by learner)
- [x] 5.15 [tutor] Review finding 1 enforcement (learner-approved): focus-loss-releases-capture scenario added to the platform-input spec delta + red test test_input_focus_loss_releases_capture; verified 26 green / 1 RED on the GetCapture assertion. Findings 5, 6 fixed+verified; finding 4 retracted (#+private was already in place); test files converted to self-contained #+private file per new project convention
- [x] 5.2 [you] Answer the probes; address review findings (done 2026-07-24: all findings addressed; P1 both variants + P2 by-construction repeat immunity answered correctly after one recount follow-up)

## 6. Finalize

- [x] 6.1 [tutor] Run the measurement task (flooded-pump ns/msg + 1000 Hz projection; snapshot bookkeeping vs 185 ns empty-pump baseline; query ns; build time + size vs m10-01's 480,256 B); record Built + Measured in curriculum/JOURNAL.md (done 2026-07-24: katas/input_pump_bench, 2 stable runs; visible-pump 184.3 ns ≈ baseline with retire included; retire 6.7 ns/window via 1→4 slope; hidden-pump 9.2 ns discovery; floods 745/2113 ns/msg; queries sub-ns; build +6,656 B)
- [x] 6.2 [tutor] Walk the learner through what the numbers mean (delivered with the 6.1 results)
- [x] 6.3 [you] Write Takeaways + Reflections in curriculum/JOURNAL.md (your own words) (verified 2026-07-24)
- [x] 6.4 [tutor] Copy lesson.md → curriculum/modules/m10/m10-02-input/LESSON.md (done 2026-07-24)
- [x] 6.5 [tutor] Update curriculum/curriculum.yaml (m10-02 → done; m11-01 → available; clear active_change) (done 2026-07-24)
- [x] 6.6 [tutor] Commit the lesson; hand off to /opsx:archive (syncs the platform-input spec into openspec/specs/) (committed 7b176de; archived 2026-07-24)
