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
