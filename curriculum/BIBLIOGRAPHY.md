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
- **Verified:** 2026-07-19 (3e section numbers checked against the publisher's TOC page)
- **Notes:** The course spine — engine layering, subsystems, the industry view in most lessons. **Citations follow 3e numbering (the learner's copy).** §6.2 memory and §7.2 resource manager match the 4e; the gameplay-systems chapters differ (3e §16.5 object references = 4e §17.5).

### GLFW
- **Title:** GLFW — Input guide
- **Author:** GLFW team
- **Type:** docs
- **Where:** https://www.glfw.org/docs/latest/input_guide.html
- **Verified:** 2026-07-22
- **Notes:** The windowing middleware odyne didn't buy, input surface: dual read model (callbacks + `glfwGetKey` cached state polled after `glfwPollEvents`), `GLFW_PRESS/REPEAT/RELEASE` with repeat explicitly "intended for text input", sticky keys against lost taps, sub-pixel double cursor coords, double scroll offsets — m10-02's read-model and policy reference.

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

### RTR
- **Title:** Real-Time Rendering, 4th Edition
- **Author:** Tomas Akenine-Möller, Eric Haines, Naty Hoffman, Angelo Pesce, Michał Iwanicki, Sébastien Hillaire
- **Type:** book
- **Where:** ISBN 978-1138627000 · https://www.realtimerendering.com/
- **Verified:** 2026-06-10
- **Notes:** Rendering theory — pipeline, transforms, lighting — m43 and renderer lessons generally.

### SDL
- **Title:** SDL3 wiki — SDL_GetKeyboardState · SDL_KeyboardEvent
- **Author:** SDL project
- **Type:** docs
- **Where:** https://wiki.libsdl.org/SDL3/SDL_GetKeyboardState · https://wiki.libsdl.org/SDL3/SDL_KeyboardEvent
- **Verified:** 2026-07-22
- **Notes:** Ships BOTH input read models side by side: a scancode-indexed snapshot array updated by the event pump (with the documented lost-tap caveat: press+release before the pump "will never show up"), and an event queue whose key events carry `down` + `repeat` flags — m10-02's coexistence proof. Cite as `[SDL SDL_GetKeyboardState]`.

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
- **Where:** https://learn.microsoft.com/en-us/windows/win32/learnwin32/creating-a-window · API ref: https://learn.microsoft.com/en-us/windows/win32/api/
- **Verified:** 2026-07-22
- **Notes:** Canonical Win32 window semantics — window classes, `CreateWindowEx`, the window procedure, the message loop — m10's API authority. Cite as `[WIN32 Creating a Window]`.

### ZYL-HANDLES
- **Title:** "Handles are the better pointers": An Odin gamedev follow-up · odin-handle-map
- **Author:** Karl Zylinski
- **Type:** article
- **Where:** https://zylinski.se/posts/handle-based-arrays/ · repo: https://github.com/karl-zylinski/odin-handle-map · three-implementations write-up: https://zylinski.se/posts/handle-based-maps-three-implementations/
- **Verified:** 2026-07-18
- **Notes:** floooh's handle idea translated to idiomatic Odin (index+generation handle maps; static / growing-arena / pointer-stable variants) — Odin-side reference for m03.
