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

### GB-MEM
- **Title:** Memory Allocation Strategies (series, parts 1–6)
- **Author:** Ginger Bill
- **Type:** article
- **Where:** https://www.gingerbill.org/series/memory-allocation-strategies/
- **Verified:** 2026-06-10
- **Notes:** Arena/stack/pool/free-list allocators, by Odin's creator — spine of m02. Cite as `[GB-MEM pt.2]`.

### GEA
- **Title:** Game Engine Architecture, 4th Edition (two-volume set)
- **Author:** Jason Gregory
- **Type:** book
- **Where:** ISBN 9781041162599 · https://www.gameenginebook.com/
- **Verified:** 2026-06-10
- **Notes:** The course spine — engine layering, subsystems, the industry view in most lessons. (4e supersedes the 3e named at proposal time; swap if the learner owns 3e.)

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
- **Title:** Odin Programming Language — Overview
- **Author:** Odin team (Ginger Bill et al.)
- **Type:** docs
- **Where:** https://odin-lang.org/docs/overview/
- **Verified:** 2026-06-10
- **Notes:** Language semantics: defer, context, slices, parapoly, SOA — m00 and every C++-delta explanation.

### RTR
- **Title:** Real-Time Rendering, 4th Edition
- **Author:** Tomas Akenine-Möller, Eric Haines, Naty Hoffman, Angelo Pesce, Michał Iwanicki, Sébastien Hillaire
- **Type:** book
- **Where:** ISBN 978-1138627000 · https://www.realtimerendering.com/
- **Verified:** 2026-06-10
- **Notes:** Rendering theory — pipeline, transforms, lighting — m43 and renderer lessons generally.

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
