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

### ANDROID-PACING
- **Title:** Android Frame Pacing library (Swappy), Android Game Development Kit
- **Author:** Google
- **Type:** docs
- **Where:** https://developer.android.com/games/sdk/frame-pacing
- **Verified:** 2026-07-29
- **Notes:** The industry's most explicit treatment of frame pacing as a problem in its own right, and the one that abandons "compute a deadline and sleep" entirely. Definition: *"Frame pacing is the synchronization of a game's logic and rendering loop with an OS's display subsystem and the underlying display hardware."* The symptom, with numbers: a 30 fps render loop on 60 fps hardware *"doesn't realize that a repeated frame remains on the screen for an extra 16 milliseconds"*, producing frame times like *"49 milliseconds, 16 milliseconds, 33 milliseconds"* — and *"short frames followed by long frames are perceived by the player as stuttering."* The mechanism is presentation-time based rather than sleep based: *"The library uses the presentation timestamp extensions `EGL_ANDROID_presentation_time` and `VK_GOOGLE_display_timing` so that frames are not presented early"*, plus Android Choreographer for the tick and *"sync fences (`EGL_KHR_fence_sync` and `VkFence`) to inject waits into the application that allow the display pipeline to catch up, rather than allowing back pressure to build up."* Also sets the display refresh rate to the value *"closest to the target frame rate"* for battery. Cite as `[ANDROID-PACING]`.

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

### DEWITTERS
- **Title:** deWiTTERS Game Loop
- **Author:** Koen Witters
- **Type:** article
- **Where:** https://dewitters.com/dewitters-gameloop/
- **Verified:** 2026-07-28
- **Notes:** The 2009 tutorial that taught a generation the four loop shapes, ending on *"constant game speed independent of variable FPS"*: a `TICKS_PER_SECOND`/`SKIP_TICKS` fixed update, a `MAX_FRAMESKIP` cap on catch-up steps, and a render-time `interpolation` factor computed as `float(GetTickCount() + SKIP_TICKS - next_game_tick) / float(SKIP_TICKS)` and used as `view_position = position + (speed * interpolation)`. Same accumulator as [GAFFER-TIMESTEP], reached independently, with the catch-up bound expressed as a **step cap** rather than as a dt clamp. Note the milliseconds-and-`GetTickCount()` time base — the [MS-QPC] lesson had not landed in tutorials yet. Cite as `[DEWITTERS]`.

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

### GAFFER-TIMESTEP
- **Title:** Fix Your Timestep!
- **Author:** Glenn Fiedler
- **Type:** article
- **Where:** https://gafferongames.com/post/fix_your_timestep/
- **Verified:** 2026-07-28
- **Notes:** The canonical statement of the fixed-timestep accumulator — m11-02's spine. Five stages, each fixing the previous one's flaw: fixed delta time → variable delta time → semi-fixed timestep → free the physics → the final touch. Why a real dt cannot go into a simulation: *"The problem is that the behavior of your physics simulation depends on the delta time you pass in"*, and *"it's utterly unrealistic to expect your simulation to correctly handle any delta time passed into it."* The viewpoint flip: *"the renderer **produces time** and the simulation **consumes it** in discrete dt sized steps."* The failure mode named: *"It's called the spiral of death because being behind causes your update to simulate more steps to catch up, which causes you to fall further behind, which causes you to simulate more steps…"*, with the bound — *"Alternatively you can clamp at a maximum # of steps per-frame and the simulation will appear to slow down under heavy load."* And the leftover: *"We can use this remainder value to get a blending factor between the previous and current physics state simply by dividing by dt"* — the render-interpolation alpha. Cite as `[GAFFER-TIMESTEP]`.

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

### GPP-LOOP
- **Title:** Game Programming Patterns — "Game Loop" (Sequencing Patterns)
- **Author:** Robert Nystrom
- **Type:** book
- **Where:** https://gameprogrammingpatterns.com/game-loop.html (full text free online) · ISBN 978-0990582908
- **Verified:** 2026-07-28
- **Notes:** The pattern write-up of the loop, and the clearest statement of what it is *for*: *"Decouple the progression of game time from user input and processor speed."* Two jobs — *"it processes user input, but doesn't wait for it"* and *"it runs the game at a consistent speed despite differences in the underlying hardware."* Rejects the variable time step on determinism grounds (*"we've made the game non-deterministic and unstable"* — float rounding differs per machine, which breaks networked play) and lands on **fixed update + variable rendering**: a `lag` accumulator, a `while (lag >= MS_PER_UPDATE)` catch-up, and `render(lag / MS_PER_UPDATE)` — the alpha handed to the renderer. Warning worth keeping: *"If step two takes longer than step one, the game slows down."* Cite as `[GPP-LOOP]`.

### HMH
- **Title:** Handmade Hero
- **Author:** Casey Muratori
- **Type:** video
- **Where:** https://handmadehero.org (→ mollyrocket.com/handmade) · episode guide: https://guide.handmadehero.org/
- **Verified:** 2026-06-10
- **Notes:** Win32 platform layer, timing, and audio built from scratch on camera — phases 1 and 3. Project on hiatus; archives and guide remain live. Cite as `[HMH day 7]`. Days relevant so far: **day 10** "QueryPerformanceCounter and RDTSC" (wall-clock vs processor time, the inline `(1000*(counter - last_counter)) / freq` conversion); **day 18** "Enforcing a Video Frame Rate" (verified 2026-07-28) — why an enforced frame rate is necessary, the frame computation/display timeline, variable-refresh monitors, "Casey's game loop design overview", *"Looping to ensure we are within the targetSecondsPerFrame"*, giving time back with sleep, and *"Setting the Windows scheduler granularity with timeBeginPeriod()"* — the same limiter m11-02 builds, on camera, with the same [MS-TIMEPERIOD] caveat.

### KHR-GUIDE
- **Title:** Vulkan Guide (Khronos official)
- **Author:** Khronos Group
- **Type:** docs
- **Where:** https://docs.vulkan.org/guide/latest/index.html · https://docs.vulkan.org/guide/latest/what_is_vulkan.html · https://docs.vulkan.org/guide/latest/portability_initiative.html · https://docs.vulkan.org/guide/latest/vulkan_release_summary.html · https://docs.vulkan.org/guide/latest/enabling_features.html
- **Verified:** 2026-07-29 (all five pages)
- **Notes:** Khronos's own orientation guide — distinct from [VKGUIDE] (Victor Blanco's tutorial); this one is normative-adjacent prose sitting beside the spec on the same site, organized as *Logistics* / *Using Vulkan* / *When and Why to use Extensions*. The definition m20-01 opens on: Vulkan is *"a new generation graphics and compute API that provides high-efficiency, cross-platform access to modern GPUs used in a wide variety of devices from PCs and consoles to mobile phones and embedded platforms"*, and the framing that matters more — *"Vulkan is not a direct replacement for OpenGL, but rather an explicit API that allows for more explicit control of the GPU"*, which *"puts more work and responsibility into the application. Not every developer will want to make that extra investment, but those that do so correctly can find power and performance improvements."* The Portability Initiative page defines that effort as *"an effort inside the Khronos Group to develop resources to define and evolve the subset of Vulkan capabilities that can be made universally available at native performance levels across all major platforms"* (it links the provisional extension but does not itself specify the enable rule — that is [VKPORT]). **Release Summary (m20-01, capability model):** the authority on **promotion to core** — *"Each minor release version of Vulkan promoted a different set of extension to core. This means that it's no longer necessary to enable an extensions to use it's functionality if the application requests at least that Vulkan version (given that the version is supported by the implementation)"*; `VK_KHR_dynamic_rendering` and `VK_KHR_synchronization2` were promoted in **1.3**, `VK_KHR_timeline_semaphore` and `VK_KHR_buffer_device_address` in **1.2**. **Enabling Features (m20-01/m20-02):** the query-then-enable asymmetry — query with `vkGetPhysicalDeviceFeatures` *or* `vkGetPhysicalDeviceFeatures2` (the latter taking a `pNext` chain so extension and newer-core feature structs are filled in the same call), but *"all features must be enabled at `VkDevice` creation time inside the `VkDeviceCreateInfo` struct"*: core-1.0 features via `pEnabledFeatures`, everything else by chaining `VkPhysicalDeviceFeatures2` onto `VkDeviceCreateInfo.pNext`. Supported is not the same as on. Cite as `[KHR-GUIDE What is Vulkan]` / `[KHR-GUIDE Portability]` / `[KHR-GUIDE Release Summary]` / `[KHR-GUIDE Enabling Features]`.

### MOLTENVK
- **Title:** MoltenVK — Vulkan Portability Implementation
- **Author:** Khronos Group / The Brenwill Workshop
- **Type:** code
- **Where:** https://github.com/KhronosGroup/MoltenVK
- **Verified:** 2026-07-29
- **Notes:** The Vulkan implementation odyne actually runs on, the macOS dev machine having no native Vulkan driver: *"MoltenVK is a layered implementation of Vulkan 1.4 graphics and compute functionality, that is built on Apple's Metal graphics and compute framework"* — a translation layer, not a driver, and *"a key component of the Khronos Vulkan Portability Initiative."* It is not fully spec-compliant by construction (Metal cannot express all of Vulkan), which is exactly why it ships [VKPORT]'s `VK_KHR_portability_subset`. The loader consequence, stated by MoltenVK itself: *"when using the Vulkan Loader from the Vulkan SDK to run MoltenVK on macOS, the Vulkan Loader will only include MoltenVK VkPhysicalDevices in the list returned by vkEnumeratePhysicalDevices() if the VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR flag is enabled in vkCreateInstance()"* — i.e. forget the flag and the machine appears to have no GPU at all. Cite as `[MOLTENVK]`.

### MS-QPC
- **Title:** Acquiring high-resolution time stamps
- **Author:** Microsoft
- **Type:** docs
- **Where:** https://learn.microsoft.com/en-us/windows/win32/sysinfo/acquiring-high-resolution-time-stamps
- **Verified:** 2026-07-27
- **Notes:** The canonical treatment of high-resolution timing on Windows, and the clearest general statement of the hazards anywhere — m11's authority. Monotonicity: *"Is the performance counter monotonic (non-decreasing)? Yes. QPC does not go backward."* Independence from wall time: *"QPC is completely independent of the system time and UTC"* — unaffected by DST, leap seconds, time zones, or admin clock changes; it is a **difference clock**, not an absolute clock. Frequency *"is fixed at system boot and is consistent across all processors so you only need to query the frequency from QueryPerformanceFrequency as the application initializes, and then cache the result"* — and *don't* assume it reflects hardware: under a v1.0 hypervisor (or on newer Windows) it is *"fixed to 10 MHz"*. Rollover: *"Not less than 100 years from the most recent system boot."* Direct TSC: *"We strongly discourage using the RDTSC or RDTSCP processor instruction."* Conversion: the sample code's comment — *"To guard against loss-of-precision, we convert to microseconds \*before\* dividing by ticks-per-second"* — plus the three integer hazards (division loses the remainder, i64↔f64 loses mantissa bits, 64-bit multiply can overflow) and the rule *"delay these computations and conversions as long as possible to avoid compounding the errors."* Also `Precision = MAX[Resolution, AccessTime]` (TSC-based QPC access ≈30 ns; platform-timer fallback ≈0.8–1.0 µs), the ±1-tick quantization/ordering ambiguity across threads, and the ppm frequency-offset table (±10 ppm ⇒ ±36 ms/hour). Cite as `[MS-QPC]`.

### MS-TIMEPERIOD
- **Title:** `timeBeginPeriod` function (timeapi.h)
- **Author:** Microsoft
- **Type:** docs
- **Where:** https://learn.microsoft.com/en-us/windows/win32/api/timeapi/nf-timeapi-timebeginperiod
- **Verified:** 2026-07-28
- **Notes:** *"requests a minimum resolution for periodic timers"* — the knob every Windows frame limiter has reached for since the 1990s, and the reason a 1 ms sleep on Windows is not a 1 ms sleep. Scope changed twice: *"Prior to Windows 10, version 2004, this function affects a global Windows setting. For all processes Windows uses the lowest value (that is, highest resolution) requested by any process. Starting with Windows 10, version 2004, this function no longer affects global timer resolution. For processes which call this function, Windows uses the lowest value … requested by any process. For processes which have not called this function, Windows does not guarantee a higher resolution than the default system resolution."* And on Windows 11, *"if a window-owning process becomes fully occluded, minimized, or otherwise invisible or inaudible to the end user, Windows does not guarantee a higher resolution than the default system resolution."* The costs: *"it can also reduce overall system performance, because the thread scheduler switches tasks more often. High resolutions can also prevent the CPU power management system from entering power-saving modes."* And the line that separates the two clocks m11-01 measured: *"Setting a higher resolution does not improve the accuracy of the high-resolution performance counter."* Must be paired with `timeEndPeriod`. Cite as `[MS-TIMEPERIOD]`.

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
- **Title:** Odin source tree — compiler (`src/build_settings.cpp`, `src/parser.cpp`) and vendor bindings (`vendor/vulkan/`)
- **Author:** Odin team (Ginger Bill et al.)
- **Type:** code
- **Where:** https://github.com/odin-lang/Odin/blob/master/src/build_settings.cpp · https://github.com/odin-lang/Odin/blob/master/src/parser.cpp · https://github.com/odin-lang/Odin/tree/master/vendor/vulkan
- **Verified:** 2026-07-24 · scope widened to `vendor/` 2026-07-29, `vendor/vulkan` read in the local install (Homebrew `odin` dev-2026-07:819fdc7a8)
- **Notes:** The authority for compiler and vendor-binding behaviour the prose docs don't cover. **`vendor/vulkan` (m20):** the bindings contain **no `foreign import`** — every Vulkan entry point is a mutable global procedure variable, filled in at runtime. `procedures.odin` exposes the loader tiers as an overload set, `load_proc_addresses :: proc{load_proc_addresses_global, load_proc_addresses_instance, load_proc_addresses_device, load_proc_addresses_device_vtable, load_proc_addresses_custom}` — global (bootstrapped from a `vkGetInstanceProcAddr` pointer), then instance, then device, mirroring the loader's own dispatch-table tiers ([VKLOADER]). Consequence for the build: linking Vulkan needs no linker flags at all, unlike `vendor:sdl3`. Cite as `[ODIN-SRC vendor/vulkan/procedures.odin]`.
- **Compiler notes:** `is_excluded_target_filename` (build_settings.cpp) is the whole file-suffix rule: strip the extension, take the **last** underscore-delimited segment and the one before it, and match them against the target OS/arch — so `foo_darwin.odin`, `foo_windows_amd64.odin` and `foo_amd64_windows.odin` are all gated, while a tag any earlier in the name (`foo_windows_test.odin`) is just a name and the file always compiles. `parse_build_tag` (parser.cpp) handles `#+build`; parser.cpp:5174 is the compiler telling you to "Prefer using the file suffixes (e.g. foo_windows.odin) or '#+build' tags" instead of `when`-guarded imports. Cite as `[ODIN-SRC is_excluded_target_filename]`.

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
- **Where:** https://wiki.libsdl.org/SDL3/SDL_GetKeyboardState · https://wiki.libsdl.org/SDL3/SDL_KeyboardEvent · https://wiki.libsdl.org/SDL3/SDL_Scancode · https://wiki.libsdl.org/SDL3/SDL_CreateWindow · https://wiki.libsdl.org/SDL3/SDL_PushEvent · https://wiki.libsdl.org/SDL3/SDL_GetTicksNS · https://wiki.libsdl.org/SDL3/SDL_DelayNS · https://wiki.libsdl.org/SDL3/SDL_DelayPrecise · https://wiki.libsdl.org/SDL3/SDL_HINT_TIMER_RESOLUTION · https://wiki.libsdl.org/SDL3/SDL_AppIterate
- **Verified:** 2026-07-22 · scope widened 2026-07-27 (platform backend) · timing pages verified 2026-07-27 · timer-resolution hint + main-callback pages verified 2026-07-28
- **Notes:** Was m10-02's read-model reference; **since 2026-07-27 it is odyne's actual platform backend** (`engine/platform/window_sdl.odin`, `input_sdl.odin`, via `vendor:sdl3`). Ships BOTH input read models side by side: a scancode-indexed snapshot array updated by the event pump (with the documented lost-tap caveat: press+release before the pump "will never show up"), and an event queue whose key events carry `down` + `repeat` flags — odyne uses the queue, because the lost-tap caveat is exactly what the half-transition counter exists to defeat. `SDL_Scancode` is USB HID usage page 0x07 — physical key identity, layout-independent, which is what WASD needs. `SDL_PushEvent` puts a synthetic event on the same queue the OS writes to, which is what made the input WIRING tier portable (`tests/platform/suite_input_wiring.odin`) after the per-OS message-injection suites were retired. **Timing (m11):** `Uint64 SDL_GetTicksNS(void)` returns *"the number of nanoseconds since the SDL library initialized"* (thread-safe, since 3.2.0) — an app-relative monotonic origin, unlike `core:time`'s boot-relative one; `void SDL_DelayNS(Uint64 ns)` *"waits at least the specified time, but possibly longer due to OS scheduling"*; `void SDL_DelayPrecise(Uint64 ns)` *"will attempt to wait as close to the requested time as possible, busy waiting if necessary, but could return later due to OS scheduling"* — SDL's own sleep-then-spin, the same shape as [ODIN-TIME accurate_sleep]. **`SDL_HINT_TIMER_RESOLUTION` (m11-02):** *"A variable that controls the timer resolution, in milliseconds"* — Windows-only, *"The default value is '1'"*, and *"If this variable is set to '0', the system timer resolution is not set"*; the wiki names the trade-off (more frequent timer interrupts ⇒ more precise delays, at the cost of power and CPU time), i.e. SDL calls [MS-TIMEPERIOD] on your behalf unless told not to. **`SDL_AppIterate` (m11-02, loop ownership):** *"App-implemented iteration entry point for SDL_MAIN_USE_CALLBACKS apps"* — *"called repeatedly by SDL after SDL_AppInit returns SDL_APP_CONTINUE"*, one *"iteration the program's primary loop"*, and it *"should not go into an infinite mainloop; it should do one iteration of whatever the program does and return."* The inverted-control loop, offered by the platform layer — the standing alternative to an app-owned `for`, and a live option in m11-02's design conversation. Cite as `[SDL SDL_GetKeyboardState]` / `[SDL SDL_DelayPrecise]` / `[SDL SDL_AppIterate]`.

### SOKOL
- **Title:** sokol — `sokol_app.h`, the cross-platform application wrapper
- **Author:** Andre Weissflog (floooh)
- **Type:** code
- **Where:** https://github.com/floooh/sokol · https://github.com/floooh/sokol/blob/master/sokol_app.h
- **Verified:** 2026-07-24
- **Notes:** "A minimal cross-platform application-wrapper library" — one API for window, 3D context, and event-based keyboard/mouse/touch across macOS, iOS, HTML5, Win32, Linux/RPi and Android, with the backend chosen by compile-time defines (`SOKOL_METAL`, `SOKOL_D3D11`, `SOKOL_GLCORE`, …) inside a single 15k-line header. The reference shape for m10-03's one-API-many-backends seam; same author as [FLOOOH]. Cite as `[SOKOL sokol_app.h]`.

### UE-SUBSTEP
- **Title:** Physics Sub-Stepping in Unreal Engine
- **Author:** Epic Games
- **Type:** docs
- **Where:** https://dev.epicgames.com/documentation/en-us/unreal-engine/physics-sub-stepping-in-unreal-engine
- **Verified:** 2026-07-28
- **Notes:** The industry's *other* answer: keep the engine tick variable and give the accumulator to physics alone. The premise is stated plainly — the engine uses variable frame rates for scalability, but *"the physics engine works best with small fixed time steps."* Two knobs: **Max Substep Delta Time**, *"the maximum time, in seconds a sub-step is allowed to take"*, and **Max Substeps**, *"the maximum number of sub-steps a full step is permitted to be broken into"* — so a 0.05 s frame with a 0.025 s max substep delta *"will be split into 2 sub-steps"*, capped by Max Substeps. Same accumulator, same catch-up bound as [GAFFER-TIMESTEP]/[DEWITTERS], scoped to one subsystem instead of the whole simulation. Cite as `[UE-SUBSTEP]`.

### UE-PACING
- **Title:** Frame Pacing for Mobile Devices in Unreal Engine · Smooth Frame Rate
- **Author:** Epic Games
- **Type:** docs
- **Where:** https://dev.epicgames.com/documentation/en-us/unreal-engine/frame-pacing-for-mobile-devices-in-unreal-engine · https://dev.epicgames.com/documentation/en-us/unreal-engine/smooth-frame-rate?application_version=4.27
- **Verified:** 2026-07-29
- **Notes:** Unreal's answer to *pacing* (distinct from [UE-SUBSTEP], which is about the fixed simulation step). Frame pacing is defined as *"a system that restricts an application to rendering frames at a lower framerate than a device's native refresh rate"*, in order to *"prioritize consistency and stability in rendering, providing for a smoother user experience"* — the goal is consistency, not a lower number. The stated cause is the same one [ANDROID-PACING] names: *"games' renderers are often unaware of this process and out of synch with it, causing them to get ahead of the displayed frame"*, and on Android Unreal simply **integrates Google's Swappy** rather than rolling its own. On desktop the knob is **Smooth Frame Rate**, in Project Settings under General Settings/Framerate, *"enabled by default"*, which *"can be used to define the min/max acceptable frame rates on a per-application basis"* with each bound settable as *"Exclusive (excludes value), Inclusive (includes value), or Open (value is not capped)"* — i.e. a frame-rate *range*, not a single target. Cite as `[UE-PACING]`.

### UNITY-TIME
- **Title:** Unity documentation — the fixed timestep loop, `Time.fixedDeltaTime`, `Time.maximumDeltaTime`, `Application.targetFrameRate`
- **Author:** Unity Technologies
- **Type:** docs
- **Where:** https://docs.unity3d.com/Manual/fixed-updates.html · https://docs.unity3d.com/ScriptReference/Time-fixedDeltaTime.html · https://docs.unity3d.com/ScriptReference/Time-maximumDeltaTime.html · https://docs.unity3d.com/ScriptReference/Application-targetFrameRate.html
- **Verified:** 2026-07-28 · `targetFrameRate` added 2026-07-29
- **Notes:** A shipping engine's accumulator, described from the user's side. `fixedDeltaTime` is *"The interval in seconds of in-game time at which physics and other fixed frame rate updates are performed"* — in-game time, so `Time.timeScale` scales it. The loop: *"a fixed update always needs a frame to run in and the duration of a frame and the length of the fixed time step are not in perfect sync"*, so at high frame rates *"each frame has one fixed update or none at all"* and at low ones *"each frame has one or more fixed updates"*; a *"backlog of fixed updates accumulates during some frames"* and Unity *"executes all of them in the next frame to catch up"*, with *"a maximum timestep period beyond which Unity will not attempt to catch up."* That bound is a **dt clamp, not a step cap**: `maximumDeltaTime` is *"The maximum value of Time.deltaTime in any given frame"*, it *"bounds the maximum number of times Unity executes MonoBehaviour.FixedUpdate in a frame to maximumDeltaTime / fixedDeltaTime"*, and it *"is always at least as large as Time.fixedDeltaTime."* Default values are **not published on these pages** — treat any specific default as `[unverified]`. **`Application.targetFrameRate` (m11-02, the limiter):** a software frame cap that Unity's own docs discourage relative to vsync — it is *"a software-based timing method"*, *"If `vSyncCount != 0`, then `targetFrameRate` is ignored"*, and most usefully: *"Setting `vSyncCount = 0` and using `targetFrameRate` will not produce a completely stutter-free output"*, being *"subject to microstuttering."* The waiting mechanism is not documented. Cite as `[UNITY-TIME fixed-updates]` / `[UNITY-TIME maximumDeltaTime]` / `[UNITY-TIME targetFrameRate]`.

### VKGUIDE
- **Title:** Vulkan Guide
- **Author:** Victor Blanco
- **Type:** docs
- **Where:** https://vkguide.dev/
- **Verified:** 2026-06-10 · chapter structure + philosophy re-verified 2026-07-29
- **Notes:** Practical Vulkan 1.3 engine-style bring-up — phase 2 backbone. Structure as of 2026-07-29: *Introduction* (API overview + libraries), *ch.0* project setup, *ch.1* initialization and render loop to a clear colour, *ch.2* compute shaders and drawing, *ch.3* mesh drawing through the graphics pipeline, *ch.4* textures and descriptor-set management, *ch.5* glTF scene loading and optimized rendering — the same arc as m20→m23, which is why it is the backbone. Uses **dynamic rendering, not render passes**, deliberately: *"so that it can act as a better base code for a game engine."* Aims to *"understand Vulkan correctly, and act as a stepping stone for then working in your own projects"*, and assumes prior 3D graphics experience — it *"will not explain 3d rendering basics such as linear algebra math."* Cite as `[VKGUIDE ch.1]`.

### VKLOADER
- **Title:** Architecture of the Vulkan Loader Interfaces
- **Author:** Khronos Group (Vulkan-Loader project)
- **Type:** docs
- **Where:** https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md
- **Verified:** 2026-07-29
- **Notes:** Why there is a `libvulkan` between the application and the driver at all, and the authority for m20-01's three-layer picture. The loader *"is critical to managing the proper dispatching of Vulkan functions to the appropriate set of layers and drivers"*; drivers are ICDs — *"Vulkan allows multiple ICDs each supporting one or more devices. Each of these devices is represented by a Vulkan VkPhysicalDevice object"*; layers are *"optional components that augment the Vulkan development environment. They can intercept, evaluate, and modify existing Vulkan functions on their way from the application down to the drivers and back up"*, inserted into call chains at instance and device creation. The mechanism connects to [VKSPEC]'s object model: *"The dispatchable object handle is a pointer to a structure, which in turn, contains a pointer to a dispatch table maintained by the loader. This dispatch table contains pointers to the Vulkan functions appropriate to that object"* — one table built at `vkCreateInstance`, one at `vkCreateDevice`. Both drivers and layers are discovered through JSON **manifest files** naming the library and its configuration, which is why layers are an install-time/runtime property of the machine rather than something linked into the binary. Cite as `[VKLOADER]`.

### VKPORT
- **Title:** `VK_KHR_portability_subset` (Vulkan specification appendix)
- **Author:** Khronos Group
- **Type:** docs
- **Where:** https://github.com/KhronosGroup/Vulkan-Docs/blob/main/appendices/VK_KHR_portability_subset.adoc (registry man page https://registry.khronos.org/vulkan/specs/latest/man/html/VK_KHR_portability_subset.html is fetch-blocked, HTTP 403)
- **Verified:** 2026-07-29
- **Notes:** The extension that makes non-native Vulkan legal, and a hard rule m20-02 must obey. It exists *"to enable a non-conformant Vulkan implementation to be built on top of another non-Vulkan graphics API, and identifies differences between that implementation and a fully-conformant native Vulkan implementation"*, letting an implementation *"mark otherwise-required capabilities as unsupported, or to establish additional properties and limits that the application should adhere to in order to guarantee portable behavior and operation across platforms."* The tell: *"Fully-conformant Vulkan implementations provide all the required capabilities, and so will not provide this extension"* — so its presence is the signal you are on a translation layer. The obligation: *"If this extension is supported by the Vulkan implementation, the application must enable this extension."* Cite as `[VKPORT]`.

### VKPROFILES
- **Title:** Vulkan Profiles Toolset — OVERVIEW
- **Author:** Khronos Group (Vulkan-Profiles project)
- **Type:** docs
- **Where:** https://github.com/KhronosGroup/Vulkan-Profiles/blob/main/OVERVIEW.md (raw: https://raw.githubusercontent.com/KhronosGroup/Vulkan-Profiles/main/OVERVIEW.md) · repo: https://github.com/KhronosGroup/Vulkan-Profiles
- **Verified:** 2026-07-29
- **Notes:** The industry's formalization of "declare your capability baseline", and the answer to how you *test* a fallback path on hardware that does not need it. A profile is *"the explicit expression and formalization of Vulkan requirements"* providing *"clear communication of these requirements within the Vulkan Community"* — a named, machine-readable capability set (version + extensions + features + limits + formats) an application targets instead of assuming universal support. Predefined profiles include `VP_KHR_roadmap_2024` and `VP_KHR_roadmap_2022` (both Vulkan 1.3), `VP_LUNARG_desktop_baseline_2024` (1.2), and `VP_ANDROID_vulkan_profile_2022` (1.1). The critical tool for odyne is `VK_LAYER_KHRONOS_profiles` — installed on the dev machine as of 2026-07-29 — which *"simulates but doesn't emulate"* a profile: it **restricts** reported capabilities to the profile rather than adding missing functionality, so *"when combined with the Validation Layer, developers can test applications as if running on more limited hardware than their development system."* That is exactly how a modern-path-plus-fallback renderer keeps its fallback honest on a single machine. Cite as `[VKPROFILES]`.

### VKSPEC
- **Title:** Vulkan Specification (Vulkan Documentation site)
- **Author:** Khronos Group
- **Type:** docs
- **Where:** https://docs.vulkan.org/spec/latest/index.html · Fundamentals: https://docs.vulkan.org/spec/latest/chapters/fundamentals.html · Synchronization: https://docs.vulkan.org/spec/latest/chapters/synchronization.html
- **Verified:** 2026-06-10 · Fundamentals + Synchronization chapters verified 2026-07-29
- **Notes:** Authoritative API semantics (1.4.353 at verification) — the arbiter when [VKGUIDE] and reality disagree. **Fundamentals** is m20-01's spine. Object model: **dispatchable** handles are pointers to opaque types that *"may be used by layers as part of intercepting API commands"*; **non-dispatchable** handles are 64-bit integers whose meaning is implementation-defined and which need not be unique unless the `privateData` feature is enabled. Execution model: the system exposes *"one or more devices, each of which exposes one or more queues which may process work asynchronously to one another"*, grouped into families by capability (graphics, compute, transfer, video decode/encode, sparse, protected); submission is asynchronous — queue submission commands *"should return as soon as the work has been submitted, without waiting for the work to complete"* — and within one queue, submissions *"respect submission order and other implicit ordering guarantees, but otherwise may overlap or execute out of order."* Valid usage: *"Vulkan implementations are not required to validate that the correct use of each command is satisfied"*, so violations are undefined behaviour and catching them is the validation layer's job, not the driver's. **Synchronization**: fences *"can be used to communicate to the host that execution of some task on the device has completed, controlling resource access between host and device"*; semaphores *"can be used to control resource access across multiple queues"*; events are *"a fine-grained synchronization primitive which can be signaled either within a command buffer or by the host, and can be waited upon within a command buffer or queried on the host"*; an *execution dependency* is *"a guarantee that for two sets of operations, the first set must happen-before the second set"*; and the memory half is two-stage — *"Availability operations cause the values generated by specified memory write accesses to become available to a memory domain for future access… Visibility operations cause values available to a memory domain to become visible to specified memory accesses."* Image layout transitions ride on those dependencies: the old layout *"must either be VK_IMAGE_LAYOUT_UNDEFINED, or match the current layout."* Cite as `[VKSPEC §Fundamentals — Execution Model]` / `[VKSPEC §Synchronization]`.

### VMA
- **Title:** Vulkan Memory Allocator
- **Author:** AMD (GPUOpen)
- **Type:** code
- **Where:** https://gpuopen.com/vulkan-memory-allocator/ · repo: https://github.com/GPUOpen-LibrariesAndSDKs/VulkanMemoryAllocator
- **Verified:** 2026-07-29
- **Notes:** The industry's answer to "who sub-allocates GPU memory", and evidence that m02's arena/pool work is the same problem one level down. VMA is *"a simple and easy to integrate API to help you allocate memory for Vulkan® buffer and image storage"*, providing *"functions that help to choose correct and optimal memory type based on intended usage"* and, the core of it, *"functions that allocate memory blocks, reserve and return parts of them (`VkDeviceMemory` + offset + size) to the user. Library keeps track of allocated memory blocks, used and unused ranges inside them, finds best matching unused ranges for new allocations, respects all the rules of alignment and buffer/image granularity."* One `VkDeviceMemory` block, many resources at offsets — a suballocator, because `maxMemoryAllocationCount` is a real and often small limit (VMA ships `VMA_DEBUG_DONT_EXCEED_MAX_MEMORY_ALLOCATION_COUNT`, on by default, to catch exceeding it). Adoption is the point of the citation: *"integrated into the majority of Vulkan® game titles on PC"*, plus Google Filament and the official Khronos Vulkan Samples. Cite as `[VMA]`.

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
