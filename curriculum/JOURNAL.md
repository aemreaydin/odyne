# Learning journal

One entry per completed lesson, newest first. The learner writes the reflections —
in their own words; that's part of the learning. Measured numbers come from the
lesson's measurement task.

## Entry format

```
## YYYY-MM-DD — <lesson id>: <title>
- **Built:** <what now exists>
- **Measured:** <numbers from the measurement task>
- **Takeaways:** <review findings + probe answers worth keeping>
- **Reflections:** <learner's own words: what was hard, what clicked, open questions>
```

---

## 2026-06-16 — lesson-m01-01: skeleton

- **Built:** `engine/` as four layered packages — `core` (`VERSION` + `version()`, the
  unit-tested seam), `platform`/`render` (`info()` identity stubs, import `core` only),
  `game` (`boot()` assembles the four-layer banner via `fmt.tprintf`; imports core+platform+
  render) — plus `examples/testbed` (`main` prints `game.boot()`) and `build.ps1`. Imports
  point downward only; `engine` collection wired. Banner:
  `odyne 0.1.0 | platform: platform | render: render | game: stub`.
- **Measured:** (tutor-run, median of 3)
  - Clean build of `examples/testbed`: `-o:none` 216.6 ms / 581,120 B · `-o:speed` 940.6 ms /
    417,792 B → optimized build ~4.3× slower to compile, binary ~28% smaller.
  - Incremental (no-op touch of `engine/core/core.odin`, rebuild `-o:none`): 198.6 ms ≈ clean
    216.6 ms → **no incremental savings.** Odin recompiles the whole program every build
    (whole-program compiler, no object cache). The number to watch grow in phase 2.
  - `odin test engine/core`: 245.4 ms · 2 tests green · leak-clean · `-vet -strict-style` clean.
  - Packages compiled: 5 engine packages (core, platform, render, game, testbed) + `core:fmt`/runtime.
  - The ~580 KB `-o:none` binary is an essentially-empty engine — fixed runtime+`fmt` overhead, the "zero point."
- **Takeaways:**
  The package system makes organization easier compared to C++. We don't need to deal with header files - #pragma onces etc.\
  String concatenation with '+' can only be done using constant strings
  -collection=engine:engine exposes the packages as "engine:..."
- **Reflections:**
  A very straightforward section, nothing particularly challenging.

## 2026-06-15 — lesson-m00-02: odin-kata

- **Built:** `katas/odin_warmup/` — first kata package. Four procedures over caller-owned
  memory (no allocators): `find` (parapoly + (index, found)), `reverse` (in-place slice
  view), `parse_u32` (error enum + overflow via `intrinsics.overflow_*`), `sum_all`
  (`or_return` propagation, u64 accumulator). 21 `core:testing` tests, all green.
- **Measured:** (tutor-run)
  - Test suite: 21 tests in ~5.0 ms · 0 leaks (memory tracking on, no issue reported).
  - `-vet -strict-style`: clean.
  - `find` micro-bench, 10,000,000 iterations over an `[]int` of 11 (loop timed internally;
    result accumulated so the loop can't be elided — `acc=30909090` identical across all runs):
    - `-o:none` : ~63 ms (~6.4 ns/op)
    - `-o:speed` : ~6.5 ms (~0.65 ns/op) **debug→optimized ≈ 9.7× faster**
  - Binary sizes: `none.exe` 571,904 B · `speed.exe` 415,744 B.
- **Takeaways:** or_return is really useful for error handling - makes code so much cleaner.
- **Reflections:** This was a reasonably simple section. Learning more of Odin is nice.

## 2026-06-12 - lesson-m00-01 : odin-tour

- Built: hello.odin - now have speed.exe and none.exe
- Measured:
  - odin version: dev-2025-12-nightly:ac61f08, windows-amd64 (Windows 11)
  - none build takes 362.2257 milliseconds and generates a 537 KB file
  - speed built takes 855.19 milliseconds and generates a 395 KB file
  - time-to-first-output: none.exe 13.4227 ms, speed.exe 12.6057 ms
- Takeaways:
  Odin is quite different when it comes to ZII, template programming and RAII logic. The context helps when using third part libraries or when a specific part of the program needs a different context.
- Reflections:
  Understanding Odin might take a while as I'm used to C++ but in general it seems like a very promising and looks like its built for game engine development.
