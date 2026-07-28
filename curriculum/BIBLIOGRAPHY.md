# Bibliography

Every source the curriculum cites, one entry per source. **Lessons and reviews may
cite only keys registered here.** New web sources are verified reachable (search/fetch)
when added; books carry a real ISBN or publisher page. Citations include the
subdivision where the source has one: `[GEA §6.2]`, `[VKGUIDE ch.2]`, `[ND-FIBERS @14:30]`.

## Entry format

```
### <CITE-KEY>
- **Title:** <full title>
- **Author:** <author(s)>
- **Type:** book | article | video | talk | code | docs
- **Where:** <URL and/or ISBN>
- **Verified:** <YYYY-MM-DD>
- **Notes:** <one line on what it's canonical for>
```

Cite-keys are short, stable, and ALL-CAPS (`GEA`, `GB-MEM`, `VKGUIDE`, `ND-FIBERS`).
Never reuse or rename a key once a lesson cites it.

---

### APPLE
- **Title:** Apple Developer Documentation — AppKit (`NSApplication`, `NSWindow`, `NSWindowDelegate`, `NSView`, `NSEvent`)
- **Author:** Apple
- **Type:** docs
- **Where:** https://developer.apple.com/documentation/appkit/nswindow · https://developer.apple.com/documentation/appkit/nsapplication/nextevent(matching:until:inmode:dequeue:) · https://developer.apple.com/documentation/appkit/nswindowdelegate/windowshouldclose(_:) · https://developer.apple.com/documentation/appkit/nsview/isflipped · https://developer.apple.com/documentation/appkit/nswindow/backingscalefactor · https://developer.apple.com/documentation/appkit/nsapplication/finishlaunching()
- **Verified:** 2026-07-24 (content read through the docs JSON API — the HTML pages are JS-rendered and return title-only to fetchers)
- **Notes:** Canonical Cocoa window/event semantics — m10-03's API authority. `nextEvent(matching:until:inMode:dequeue:)`: nil expiration ≡ `distantPast` ≡ non-blocking, non-matching events stay queued. `windowShouldClose:` returning false vetoes the close (but is skipped on app quit). `isFlipped` defaults false ⇒ view origin lower-left, +y up. `backingScaleFactor` is 2.0 on Retina, with Apple's own advice to prefer `convertToBacking:` over multiplying by it. Cite as `[APPLE windowShouldClose]`.

### APPLE-THREADING
- **Title:** Thread Safety Summary (Cocoa Threading Programming Guide, archived)
- **Author:** Apple
- **Type:** docs
- **Where:** https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/ThreadSafetySummary.html
- **Verified:** 2026-07-24
- **Notes:** "The following classes must be used only from the main thread of an application: `NSCell` and all of its descendants, `NSView` and all of its descendants." Archived guide — it still permits window *creation* off the main thread, but modern AppKit is stricter and raises `NSInternalInconsistencyException: NSWindow should only be instantiated on the main thread!` (measured in m10-03 on macOS 15.2). The rule behind m10-03's test-strategy redesign.

### BITSQUID
- **Title:** Managing Decoupling Part 4 — The ID Lookup Table
- **Author:** Niklas Frykholm (Niklas Gray), Bitsquid
- **Type:** article
- **Where:** https://bitsquid.blogspot.com/2011/09/managing-decoupling-part-4-id-lookup.html
- **Verified:** 2026-07-18
- **Notes:** The classic id→object storage designs — array-with-holes + freelist, packed array + index table with swap-with-last delete, measured against std::map — m03's handle-pool blueprint.

### DX12
- **Title:** Direct3D 12 programming guide
- **Author:** Microsoft
- **Type:** docs
- **Where:** https://learn.microsoft.com/en-us/windows/win32/direct3d12/directx-12-programming-guide
- **Verified:** 2026-06-10
- **Notes:** Canonical D3D12 API model and usage docs — phase 5 backend bring-up.

### ECS-FAQ
- **Title:** ECS FAQ
- **Author:** Sander Mertens
- **Type:** docs
- **Where:** https://github.com/SanderMertens/ecs-faq
- **Verified:** 2026-06-10
- **Notes:** ECS concepts, archetypes vs sparse sets, DoD/cache glossary — m42's map of the territory.

### FLOOOH
- **Title:** Handles are the better pointers
- **Author:** Andre Weissflog
- **Type:** article
- **Where:** https://floooh.github.io/2018/06/17/handles-vs-pointers.html
- **Verified:** 2026-07-18
- **Notes:** The handles manifesto — index+generation handles, system-owned arrays, stale-handle detection, "pointers are transient locals" — m03's conceptual spine.

### GB-MEM
- **Title:** Memory Allocation Strategies (series, parts 1–6)
- **Author:** Ginger Bill
- **Type:** article
- **Where:** https://www.gingerbill.org/series/memory-allocation-strategies/
- **Verified:** 2026-06-10
- **Notes:** Arena/stack/pool/free-list allocators, by Odin's creator — spine of m02. Cite as `[GB-MEM pt.2]`.

### GEA
- **Title:** Game Engine Architecture, 3rd Edition
- **Author:** Jason Gregory
- **Type:** book
- **Where:** ISBN 9781138035454 · https://www.gameenginebook.com/
- **Verified:** 2026-07-19 (3e section numbers checked against the publisher's TOC page) · ch.8 re-checked 2026-07-27
- **Notes:** The course spine — engine layering, subsystems, the industry view in most lessons. **Citations follow 3e numbering (the learner's copy).** §6.2 memory and §7.2 resource manager match the 4e; the gameplay-systems chapters differ (3e §16.5 object references = 4e §17.5). Ch.8 "The Game Loop and Real-Time Simulation" numbering also matches across 3e/4e — §8.4 Abstract Timelines, §8.5 Measuring and Dealing with Time (checked 2026-07-27 against the author's TOC at gameenginebook.com/toc.html, which is now the 4e listing, cross-checked against a search-index listing of the 3e contents; O'Reilly's 3e contents page itself is fetch-blocked, so treat sub-subsection numbers inside §8.5 as [unverified]).

### GLFW
- **Title:** GLFW — Input guide
- **Author:** GLFW team
- **Type:** docs
- **Where:** https://www.glfw.org/docs/latest/input_guide.html
- **Verified:** 2026-07-22 · note revised 2026-07-27
- **Notes:** Input surface: dual read model (callbacks + `glfwGetKey` cached state polled after `glfwPollEvents`), `GLFW_PRESS/REPEAT/RELEASE` with repeat explicitly "intended for text input", sticky keys against lost taps, sub-pixel double cursor coords, double scroll offsets — m10-02's read-model and policy reference. Also the runner-up in the 2026-07-27 platform migration: both build and link cleanly here, and GLFW is the smaller API, but [SDL] was chosen because it carries audio, gamepad and timing subsystems as well, so the same decision does not have to be re-litigated at every later platform lesson. GLFW's screen-coordinates-vs-framebuffer-size distinction is the precedent for odyne's `client_size`/`framebuffer_size` split.

### GLTF
- **Title:** glTF 2.0 Specification
- **Author:** Khronos Group
- **Type:** docs
- **Where:** https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html
- **Verified:** 2026-06-10
- **Notes:** Model/asset interchange format for m43-04. Registry blocks automated fetches; confirmed canonical via the official repo (https://github.com/KhronosGroup/glTF).

### HMH
- **Title:** Handmade Hero
- **Author:** Casey Muratori
- **Type:** video
- **Where:** https://handmadehero.org (→ mollyrocket.com/handmade) · episode guide: https://guide.handmadehero.org/
- **Verified:** 2026-06-10
- **Notes:** Win32 platform layer, timing, and audio built from scratch on camera — phases 1 and 3. Project on hiatus; archives and guide remain live. Cite as `[HMH day 7]`.

### MS-QPC
- **Title:** Acquiring high-resolution time stamps
- **Author:** Microsoft
- **Type:** docs
- **Where:** https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps
- **Verified:** 2026-07-27
- **Notes:** The canonical treatment of high-resolution timing on Windows, and the clearest general statement of the hazards anywhere — m11's authority. Monotonicity: *"Is the performance counter monotonic (non-decreasing)? Yes. QPC does not go backward."* Independence from wall time: *"QPC is completely independent of the system time and UTC"* — unaffected by DST, leap seconds, time zones, or admin clock changes; it is a **difference clock**, not an absolute clock. Frequency *"is fixed at system boot and is consistent across all processors so you only need to query the frequency from QueryPerformanceFrequency as the application initializes, and then cache the result"* — and *don't* assume it reflects hardware: under a v1.0 hypervisor (or on newer Windows) it is *"fixed to 10 MHz"*. Rollover: *"Not less than 100 years from the most recent system boot."* Direct TSC: *"We strongly discourage using the RDTSC or RDTSCP processor instruction."* Conversion: the sample code's comment — *"To guard against loss-of-precision, we convert to microseconds \*before\* dividing by ticks-per-second"* — plus the three integer hazards (division loses the remainder, i64↔f64 loses mantissa bits, 64-bit multiply can overflow) and the rule *"delay these computations and conversions as long as possible to avoid compounding the errors."* Also `Precision = MAX[Resolution, AccessTime]` (TSC-based QPC access ≈30 ns; platform-timer fallback ≈0.8–1.0 µs), the ±1-tick quantization/ordering ambiguity across threads, and the ppm frequency-offset table (±10 ppm ⇒ ±36 ms/hour). Cite as `[MS-QPC]`.

### ND-FIBERS
- **Title:** Parallelizing the Naughty Dog Engine Using Fibers (GDC 2015)
- **Author:** Christian Gyrling
- **Type:** talk
- **Where:** slides (free): https://media.gdcvault.com/gdc2015/presentations/Gyrling_Christian_Parallelizing_The_Naughty.pdf · video (membership): https://www.gdcvault.com/play/1022186/Parallelizing-the-Naughty-Dog-Engine
- **Verified:** 2026-06-10
- **Notes:** Fiber-based job system and frame-centric engine design — m41's industry anchor.

### ODIN
- **Title:** Odin Programming Language — site & Overview docs
- **Author:** Odin team (Ginger Bill et al.)
- **Type:** docs
- **Where:** https://odin-lang.org/docs/overview/ · https://odin-lang.org/
- **Verified:** 2026-06-12
- **Notes:** Language semantics: defer, context, slices, parapoly, SOA — m00 and every C++-delta explanation.

### ODIN-CONTAINER
- **Title:** Odin package documentation — `core:container` packages
- **Author:** Odin team (Ginger Bill et al.)
- **Type:** docs
- **Where:** https://pkg.odin-lang.org/core/container/queue/ · https://pkg.odin-lang.org/core/container/handle_map/
- **Verified:** 2026-07-21
- **Notes:** The stdlib's container shape — one sub-package per container (queue, small_array, priority_queue, handle_map, …) with unprefixed proc names; `handle_map` is a generational handle map generic over a caller-supplied `$Handle_Type` (structs with idx/gen fields, zero index reserved) — m03-03's packaging precedent and the in-stdlib reference for caller-typed handles. Cite as `[ODIN-CONTAINER handle_map]`.

### ODIN-DARWIN
- **Title:** Odin package documentation — `core:sys/darwin/Foundation`
- **Author:** Odin team (Ginger Bill et al.)
- **Type:** docs
- **Where:** https://pkg.odin-lang.org/core/sys/darwin/Foundation/
- **Verified:** 2026-07-24
- **Notes:** Odin's Objective-C/Cocoa bindings (138 types, 807 procs, generated for `darwin_arm64`): `Application`, `Window`, `View`, `Event`, the `kVK` hardware-keycode enum (from Carbon `Events.h`), and `window_delegate_register_and_alloc` — which builds an Objective-C class at runtime from a struct of Odin procs and threads a `runtime.Context` through the callback. Cocoa.framework is linked automatically via `@(require) foreign import`. `vendor:darwin/Foundation` is a moved-package stub that `#panic`s — this is the real package. Cite as `[ODIN-DARWIN Window]`.

### ODIN-MEM
- **Title:** Odin package documentation — `base:runtime` allocator interface & `core:mem`
- **Author:** Odin team (Ginger Bill et al.)
- **Type:** docs
- **Where:** https://pkg.odin-lang.org/base/runtime/ (Allocator, Allocator_Proc, Allocator_Mode, Allocator_Error) · https://pkg.odin-lang.org/core/mem/
- **Verified:** 2026-06-16
- **Notes:** The concrete allocator interface (`Allocator{procedure, data}`, the 8-mode `Allocator_Mode`, `Allocator_Error`) and `core:mem` helpers — m02's implementation reference. Cite as `[ODIN-MEM runtime.Allocator]`.

### ODIN-SYS
- **Title:** Odin package documentation — `core:sys/windows`
- **Author:** Odin team (Ginger Bill et al.)
- **Type:** docs
- **Where:** https://pkg.odin-lang.org/core/sys/windows/
- **Verified:** 2026-07-22
- **Notes:** The stdlib's Win32 bindings — 1000+ types (`HWND`, `WNDCLASSEXW`, `MSG`), 6000+ constants (`WS_*`, `WM_*`), user32/kernel32 procs — no hand-written foreign blocks needed for m10's platform layer.

### ODIN-SRC
- **Title:** Odin compiler source — `src/build_settings.cpp`, `src/parser.cpp`
- **Author:** Odin team (Ginger Bill et al.)
- **Type:** code
- **Where:** https://github.com/odin-lang/Odin/blob/master/src/build_settings.cpp · https://github.com/odin-lang/Odin/blob/master/src/parser.cpp
- **Verified:** 2026-07-24
- **Notes:** The authority for compiler behaviour the prose docs don't cover. `is_excluded_target_filename` (build_settings.cpp) is the whole file-suffix rule: strip the extension, take the **last** underscore-delimited segment and the one before it, and match them against the target OS/arch — so `foo_darwin.odin`, `foo_windows_amd64.odin` and `foo_amd64_windows.odin` are all gated, while a tag any earlier in the name (`foo_windows_test.odin`) is just a name and the file always compiles. `parse_build_tag` (parser.cpp) handles `#+build`; parser.cpp:5174 is the compiler telling you to "Prefer using the file suffixes (e.g. foo_windows.odin) or '#+build' tags" instead of `when`-guarded imports. Cite as `[ODIN-SRC is_excluded_target_filename]`.

### ODIN-TEST
- **Title:** Odin package documentation — `core:testing` (the `@(test)` runner)
- **Author:** Odin team (Ginger Bill et al.)
- **Type:** docs
- **Where:** https://pkg.odin-lang.org/core/testing/ · runner source: https://github.com/odin-lang/Odin/blob/master/core/testing/runner.odin
- **Verified:** 2026-07-24
- **Notes:** Runner configuration — `TEST_THREADS :: #config(ODIN_TEST_THREADS, 0)` (0 ⇒ one per core), `ODIN_TEST_TRACK_MEMORY` per-test leak checking, per-thread allocators. The runner *always* dispatches tests through a `thread.Pool` (`pool_init` → `pool_add_task(run_test_task)`): `ODIN_TEST_THREADS=1` means one **worker**, never the main thread — the constraint that makes AppKit windows untestable under `odin test`. Cite as `[ODIN-TEST runner]`.

### ODIN-TIME
- **Title:** Odin package documentation — `core:time`, plus the per-OS backends as shipped
- **Author:** Odin team (Ginger Bill et al.)
- **Type:** docs
- **Where:** https://pkg.odin-lang.org/core/time/ · source read locally at `$(odin root)/core/time/{time.odin,time_unix.odin,time_windows.odin}` on `dev-2026-07:819fdc7a8`
- **Verified:** 2026-07-27
- **Notes:** Odin's two clocks are two *types*: `Time :: struct{_nsec: i64}` (wall clock, UNIX epoch, `now()`) and `Tick :: struct{_nsec: i64}` (*"monotonic time, useful for measuring durations"*, `tick_now()`) — the steady/system split enforced by the type system rather than by discipline. `Duration :: distinct i64` in nanoseconds with `Nanosecond`…`Hour` constants; `tick_diff/tick_since/tick_lap_time/tick_add`; `Stopwatch{running, _start_time, _accumulation}` for multi-run accumulation; `duration_seconds` splits `d/Second` and `d%Second` before touching `f64`. Backends: darwin `clock_gettime(CLOCK_MONOTONIC_RAW)`; windows `QueryPerformanceCounter` normalized to ns through a quotient/remainder `mul_div_u64` — the overflow-safe conversion [MS-QPC] prescribes, in the stdlib. `_sleep` is `Sleep(d/Millisecond)` on Windows (whole-ms truncation, so sub-ms sleeps become 0) and `nanosleep` on unix; `_yield` is `SwitchToThread`/`sched_yield`. `accurate_sleep` is textbook sleep-then-spin: repeat `sleep(1*Millisecond)` while the remaining time exceeds a **Welford-estimated** `mean + stddev` of *observed* sleep overshoot, then busy-`_yield` the tail. Cite as `[ODIN-TIME tick_now]` / `[ODIN-TIME accurate_sleep]`.

### RTR
- **Title:** Real-Time Rendering, 4th Edition
- **Author:** Tomas Akenine-Möller, Eric Haines, Naty Hoffman, Angelo Pesce, Michał Iwanicki, Sébastien Hillaire
- **Type:** book
- **Where:** ISBN 978-1138627000 · https://www.realtimerendering.com/
- **Verified:** 2026-06-10
- **Notes:** Rendering theory — pipeline, transforms, lighting — m43 and renderer lessons generally.

### SDL
- **Title:** SDL3 wiki — SDL_GetKeyboardState · SDL_KeyboardEvent · SDL_Scancode · SDL_CreateWindow · SDL_PushEvent
- **Author:** SDL project
- **Type:** docs
- **Where:** https://wiki.libsdl.org/SDL3/SDL_GetKeyboardState · https://wiki.libsdl.org/SDL3/SDL_KeyboardEvent · https://wiki.libsdl.org/SDL3/SDL_Scancode · https://wiki.libsdl.org/SDL3/SDL_CreateWindow · https://wiki.libsdl.org/SDL3/SDL_PushEvent · https://wiki.libsdl.org/SDL3/SDL_GetTicksNS · https://wiki.libsdl.org/SDL3/SDL_DelayNS · https://wiki.libsdl.org/SDL3/SDL_DelayPrecise
- **Verified:** 2026-07-22 · scope widened 2026-07-27 (platform backend) · timing pages verified 2026-07-27
- **Notes:** Was m10-02's read-model reference; **since 2026-07-27 it is odyne's actual platform backend** (`engine/platform/window_sdl.odin`, `input_sdl.odin`, via `vendor:sdl3`). Ships BOTH input read models side by side: a scancode-indexed snapshot array updated by the event pump (with the documented lost-tap caveat: press+release before the pump "will never show up"), and an event queue whose key events carry `down` + `repeat` flags — odyne uses the queue, because the lost-tap caveat is exactly what the half-transition counter exists to defeat. `SDL_Scancode` is USB HID usage page 0x07 — physical key identity, layout-independent, which is what WASD needs. `SDL_PushEvent` puts a synthetic event on the same queue the OS writes to, which is what made the input WIRING tier portable (`tests/platform/suite_input_wiring.odin`) after the per-OS message-injection suites were retired. **Timing (m11):** `Uint64 SDL_GetTicksNS(void)` returns *"the number of nanoseconds since the SDL library initialized"* (thread-safe, since 3.2.0) — an app-relative monotonic origin, unlike `core:time`'s boot-relative one; `void SDL_DelayNS(Uint64 ns)` *"waits at least the specified time, but possibly longer due to OS scheduling"*; `void SDL_DelayPrecise(Uint64 ns)` *"will attempt to wait as close to the requested time as possible, busy waiting if necessary, but could return later due to OS scheduling"* — SDL's own sleep-then-spin, the same shape as [ODIN-TIME accurate_sleep]. Cite as `[SDL SDL_GetKeyboardState]` / `[SDL SDL_DelayPrecise]`.

### SOKOL
- **Title:** sokol — `sokol_app.h`, the cross-platform application wrapper
- **Author:** Andre Weissflog (floooh)
- **Type:** code
- **Where:** https://github.com/floooh/sokol · https://github.com/floooh/sokol/blob/master/sokol_app.h
- **Verified:** 2026-07-24
- **Notes:** "A minimal cross-platform application-wrapper library" — one API for window, 3D context, and event-based keyboard/mouse/touch across macOS, iOS, HTML5, Win32, Linux/RPi and Android, with the backend chosen by compile-time defines (`SOKOL_METAL`, `SOKOL_D3D11`, `SOKOL_GLCORE`, …) inside a single 15k-line header. The reference shape for m10-03's one-API-many-backends seam; same author as [FLOOOH]. Cite as `[SOKOL sokol_app.h]`.

### VKGUIDE
- **Title:** Vulkan Guide
- **Author:** Victor Blanco
- **Type:** docs
- **Where:** https://vkguide.dev/
- **Verified:** 2026-06-10
- **Notes:** Practical Vulkan 1.3 engine-style bring-up (dynamic rendering) — phase 2 backbone. Cite as `[VKGUIDE ch.1]`.

### VKSPEC
- **Title:** Vulkan Specification (Vulkan Documentation site)
- **Author:** Khronos Group
- **Type:** docs
- **Where:** https://docs.vulkan.org/spec/latest/index.html
- **Verified:** 2026-06-10
- **Notes:** Authoritative API semantics (1.4.353 at verification) — the arbiter when VKGUIDE and reality disagree.

### WIN32
- **Title:** Get Started with Win32 (Learn Win32 module) & Win32 API reference
- **Author:** Microsoft
- **Type:** docs
- **Where:** https://learn.microsoft.com/en-us/windows/win32/learnwin32/creating-a-window · API ref: https://learn.microsoft.com/en-us/windows/win32/api/ · Keyboard Input Overview: https://learn.microsoft.com/en-us/windows/win32/inputdev/about-keyboard-input
- **Verified:** 2026-07-22 · Keyboard Input Overview added 2026-07-24
- **Notes:** Canonical Win32 window semantics — window classes, `CreateWindowEx`, the window procedure, the message loop — m10's API authority. The Keyboard Input Overview adds the input model: the keyboard driver maps a **scan code** (device-dependent, "identifies the key pressed regardless of the active keyboard layout") to a **virtual-key code** *through the currently selected keyboard layout*, and Microsoft names the consequence outright — scan codes "might be required … for example, the WASD … key bindings for games, which ensure a consistent key formation across US QWERTY or French AZERTY keyboard layouts." Cite as `[WIN32 Creating a Window]` / `[WIN32 Keyboard Input]`.

### ZYL-HANDLES
- **Title:** "Handles are the better pointers": An Odin gamedev follow-up · odin-handle-map
- **Author:** Karl Zylinski
- **Type:** article
- **Where:** https://zylinski.se/posts/handle-based-arrays/ · repo: https://github.com/karl-zylinski/odin-handle-map · three-implementations write-up: https://zylinski.se/posts/handle-based-maps-three-implementations/
- **Verified:** 2026-07-18
- **Notes:** floooh's handle idea translated to idiomatic Odin (index+generation handle maps; static / growing-arena / pointer-stable variants) — Odin-side reference for m03.
