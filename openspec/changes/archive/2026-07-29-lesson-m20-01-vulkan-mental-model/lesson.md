# Lesson: m20-01/vulkan-mental-model — The Vulkan mental model

> **Type:** concept · **Module:** m20 Vulkan bootstrap · **Interface:** not applicable (concept lesson — no exercise interface; m20-02 designs and builds instance/device/queue selection against this model)

## Goals

- Explain what an **explicit** graphics API moves onto you that OpenGL/D3D11 kept in the driver, and what you get for it — so the ceremony in m20-02 reads as consequence, not ritual.
- Know the **stack you are actually calling into**: application → loader → layers → ICD, why validation layers are an install-time property of the machine rather than a library you link, and why Odin's `vendor:vulkan` is a table of function pointers with no `foreign import`.
- Hold the **two-timeline execution model** — host records, device executes, submission returns immediately — and place fences, semaphores, and barriers on it correctly.
- Know why GPU memory is **allocated in a few big blocks and sub-allocated**, and recognize it as m02's arena problem one level down.
- Know how Vulkan reports **capabilities** along four independent axes, why "supported" and "enabled" are different things, and the design rule that follows: **branch on capability, never on platform** — modern path first, fallback behind one check, both driven by a single queried record.
- Know exactly **where you are standing** — a MoltenVK translation layer on an Apple M2 — as the *first customer* of that capability record rather than as a special case to hardcode around.

## Prerequisites

- m03-01 (handles, not pointers) — Vulkan is a handle-based API; this lesson cashes that in.
- m02-01/m02-02 (allocators, arena) — device memory is the same problem with a worse failure mode.
- m11-02 (main loop & fixed timestep) — you have one clock; you are about to acquire a second one you don't control.
- m01-01 (layering law) — `core → platform → render → game`, and no `vk*` type escapes `engine/render`.

## Explanation

Vulkan's difficulty is not syntax. It is that the API declines to do four jobs the previous
generation of APIs did silently on your behalf: it does not track state, it does not
synchronize, it does not manage memory, and it does not check your work. Every one of those
refusals shows up as code you write. This lesson is the map, so that m20-02 and m20-03 are
typing rather than confusion.

### What "explicit" is buying

Khronos is careful not to call Vulkan an upgrade: it is *"a new generation graphics and
compute API that provides high-efficiency, cross-platform access to modern GPUs used in a
wide variety of devices from PCs and consoles to mobile phones and embedded platforms"*, and
*"not a direct replacement for OpenGL, but rather an explicit API that allows for more
explicit control of the GPU"* [[KHR-GUIDE What is Vulkan]](https://docs.vulkan.org/guide/latest/what_is_vulkan.html).
The honest part of the pitch is the next sentence: Vulkan *"puts more work and responsibility
into the application. Not every developer will want to make that extra investment, but those
that do so correctly can find power and performance improvements"* [[KHR-GUIDE What is Vulkan]](https://docs.vulkan.org/guide/latest/what_is_vulkan.html).

What was the old cost? In an implicit API, a draw call is a request to a driver that must
reconstruct your intent: it inspects a large mutable state machine, decides whether the
currently-bound state needs a new shader variant compiled, may allocate, may patch, may
defer, and does all of this on whatever thread called it. The results are a per-call CPU
overhead you cannot see, a single-threaded submission bottleneck, and — the one that actually
ruins games — *hitches*, when a driver decides frame 4,000 is the moment to compile a
pipeline. The explicit trade is: you tell the driver everything up front, in objects that are
expensive to create and cheap to use, and you accept that nothing is implicit anymore. Every
piece of Vulkan tedium is one of those hidden driver behaviours made into an object you own.

### The stack you are calling into

`vkCreateInstance` is not a driver call. Between your program and the GPU vendor's driver
sits the **loader**, which *"is critical to managing the proper dispatching of Vulkan
functions to the appropriate set of layers and drivers"* [[VKLOADER]](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md).
Three tiers:

- **Drivers (ICDs, Installable Client Drivers).** *"Vulkan allows multiple ICDs each
  supporting one or more devices. Each of these devices is represented by a Vulkan
  VkPhysicalDevice object"* [[VKLOADER]](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md).
  This is why enumeration returns a list: one machine, potentially several
  implementations.
- **Layers.** *"Optional components that augment the Vulkan development environment. They
  can intercept, evaluate, and modify existing Vulkan functions on their way from the
  application down to the drivers and back up"* [[VKLOADER]](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md).
  The loader splices them into call chains at instance and device creation.
- **The loader**, which finds both through JSON **manifest files** naming the library and its
  configuration [[VKLOADER]](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md).

That manifest detail has a practical edge: validation is not a library you link and it is not
a compile flag. It is a component installed on the machine, discovered at runtime, and named
by string at `vkCreateInstance`. Ask for a layer that isn't installed and you get an error;
ask for none and you get a driver that silently does whatever it likes with your mistakes.

The dispatch mechanism explains an oddity you already met in m03-01. A **dispatchable** handle
— `VkInstance`, `VkDevice`, `VkQueue`, `VkCommandBuffer` — is not opaque to the loader:
*"the dispatchable object handle is a pointer to a structure, which in turn, contains a
pointer to a dispatch table maintained by the loader. This dispatch table contains pointers to
the Vulkan functions appropriate to that object"* [[VKLOADER]](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md) —
one table built at `vkCreateInstance`, another at `vkCreateDevice`. The spec's own view of
the same objects: dispatchable handles are pointers to opaque types that *"may be used by
layers as part of intercepting API commands"*, while **non-dispatchable** handles —
`VkBuffer`, `VkImage`, `VkPipeline`, and most of the API — are 64-bit integers whose meaning
is implementation-defined, and which are not even required to be unique unless the
`privateData` feature is enabled [[VKSPEC §Fundamentals — Object Model]](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html#fundamentals-objectmodel).
Read that last clause again with m03-01 in mind: a non-dispatchable handle may be an index,
a packed word, or a pointer — the driver's business, opaque to you, exactly as your own
handles are opaque to callers.

> **C++ delta — where did `vkCreateInstance` go?** In C++ you link `vulkan-1.lib` and call
> the symbol. Odin's `vendor:vulkan` has **no `foreign import`**: every entry point is a
> mutable global function pointer, and you must fill them in via `load_proc_addresses`,
> which the bindings overload for the global, instance, and device tiers
> (`load_proc_addresses_global/_instance/_device`) [[ODIN-SRC vendor/vulkan/procedures.odin]](https://github.com/odin-lang/Odin).
> That is not Odin being awkward — it is the loader architecture made honest. You bootstrap
> from a single `vkGetInstanceProcAddr`, then re-resolve after you have an instance, then
> again after you have a device, because each tier gets a *different, more specific* dispatch
> table. The upside is that no linker flags are needed for Vulkan at all.

### Everything is a handle you created and must destroy

Vulkan is the API m03-01 was preparing you for: *"at the API level, all objects are referred
to by handles"* [[VKSPEC §Fundamentals — Object Model]](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html#fundamentals-objectmodel).
Three habits follow.

**Creation is a struct, not an argument list.** Every `vkCreate*` takes a `Vk*CreateInfo`
whose first two members are `sType` (a tag naming the struct's own type) and `pNext` (a
pointer to another such struct). That pair is the API's extension mechanism: new features
arrive as new structs chained onto `pNext` rather than as new function signatures, which is
how a 2016 API absorbed a decade of hardware without breaking ABI. In Odin, ZII does most of
the work — you set the fields you care about and let the rest be zero — but `sType` is the
one field that is never optional.

**Destruction is yours, in order, by hand.** There is no reference counting. A `VkImageView`
does not keep its `VkImage` alive; destroying them in the wrong order is undefined behaviour,
not an error. `defer` gives you LIFO teardown, which matches creation order and is the right
tool — but note precisely what it does *not* give you, below.

**Errors are values.** Almost every call returns a `VkResult`; there are no exceptions.
`or_return` from m00-02 is the ergonomic answer, and the enum distinguishes real failures
(`ERROR_OUT_OF_DEVICE_MEMORY`) from conditions you must handle as flow control
(`SUBOPTIMAL_KHR`, `ERROR_OUT_OF_DATE_KHR` — you will meet both in m20-03 when the window is
resized).

### Two timelines

Here is the shift that matters most. Your program and the GPU are two machines running
concurrently, and Vulkan never pretends otherwise. The system exposes *"one or more devices,
each of which exposes one or more queues which may process work asynchronously to one
another"* [[VKSPEC §Fundamentals — Execution Model]](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html#fundamentals-execution).
Queues come in **families** grouped by capability — graphics, compute, transfer, video
decode/encode, sparse, protected [[VKSPEC §Fundamentals — Execution Model]](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html#fundamentals-execution) —
and which families exist, and how many queues each has, is a property of the machine you must
query rather than assume. (What that query returns on *this* machine is one of this lesson's
measurements, and it is not what desktop-GPU tutorials will lead you to expect.)

You do not call drawing functions. You **record** commands into a `VkCommandBuffer` — an
ordinary buffer of encoded work, built on the CPU, at whatever rate you like, on whatever
thread you like — and then **submit** it to a queue. And submission does not wait: queue
submission commands *"should return as soon as the work has been submitted, without waiting
for the work to complete"*; within a single queue, submissions *"respect submission order and
other implicit ordering guarantees, but otherwise may overlap or execute out of order"*
[[VKSPEC §Fundamentals — Execution Model]](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html#fundamentals-execution).

So: `vkQueueSubmit` returning tells you *nothing* about the GPU. The command buffer you just
submitted is still being read. The buffer it references is still being sampled. The image it
renders into is still being written. Your fixed-timestep loop from m11-02 has acquired a
second clock that it does not own and cannot poll for free — and every resource-lifetime bug
in Vulkan is some version of freeing a thing the other timeline is still using.

> **C++ habit vs explicit-API reality:** the RAII instinct says the destructor is the place to
> free, and `defer` is the Odin shape of that instinct. It is right about *order* and wrong
> about *time*. `defer vk.DestroyBuffer(...)` at the end of a frame destroys a buffer the GPU
> may not have finished reading. There is no ownership annotation, no borrow checker, and no
> refcount that will save you — the only thing that means "the device is done" is a **fence**
> you waited on. This is a genuinely new failure mode with no C++ type-system analogue: the
> compiler cannot see the second timeline. Engines answer it structurally, not per-object,
> with **frames in flight** — N frames' worth of per-frame structures, cycled, each guarded by
> its own fence, which is exactly what [VKGUIDE]'s `FRAME_OVERLAP` and per-frame
> `_renderFence` build [[VKGUIDE ch.1 Mainloop Code]](https://vkguide.dev/docs/new_chapter_1/vulkan_mainloop_code/) —
> and **deletion queues**, where destruction is recorded as deferred work and flushed only
> after a fence says the GPU is finished, in reverse order of creation
> [[VKGUIDE ch.2 Improving the render loop]](https://vkguide.dev/docs/new_chapter_2/vulkan_new_rendering/).

### Synchronization is the actual work

Because nothing is ordered by default, ordering is something you request. Four primitives,
each on a different edge of the two-timeline picture [[VKSPEC §Synchronization]](https://docs.vulkan.org/spec/latest/chapters/synchronization.html):

| Primitive | Synchronizes | Use |
|---|---|---|
| **Fence** | device → host | *"communicate to the host that execution of some task on the device has completed"* — "is frame N done?" |
| **Semaphore** | queue → queue (device-side) | *"control resource access across multiple queues"* — "present only after rendering finished" |
| **Pipeline barrier** | within a queue | ordering + memory visibility between commands, including image layout changes |
| **Event** | fine-grained, either side | *"signaled either within a command buffer or by the host, and can be waited upon within a command buffer or queried on the host"* |

Two ideas underneath them are worth internalizing now, because they are what make barriers
confusing on first contact.

**Execution dependency ≠ memory dependency.** An *execution dependency* is *"a guarantee that
for two sets of operations, the first set must happen-before the second set"*
[[VKSPEC §Synchronization]](https://docs.vulkan.org/spec/latest/chapters/synchronization.html).
That orders the work — and by itself does not guarantee the second set can *see* what the
first set wrote. The memory half is two-stage: *"availability operations cause the values
generated by specified memory write accesses to become available to a memory domain for
future access"*, and *"visibility operations cause values available to a memory domain to
become visible to specified memory accesses"* [[VKSPEC §Synchronization]](https://docs.vulkan.org/spec/latest/chapters/synchronization.html).
Write → **available** (flushed out of the writing agent's caches) → **visible** (readable by
the specified later accesses). A barrier that orders correctly but names the wrong access
masks produces a race that runs perfectly on your GPU and corrupts on someone else's. If your
C++ instinct reaches for `std::atomic` and acquire/release here, that instinct is pointed the
right way — same shape, different scale.

**Images have layouts.** The same pixels are stored differently depending on what the hardware
is about to do with them (render target, sampled texture, transfer source, presentable). You
transition between layouts as part of a memory dependency, and the rule has a sharp edge: the
old layout *"must either be VK_IMAGE_LAYOUT_UNDEFINED, or match the current layout"*
[[VKSPEC §Synchronization]](https://docs.vulkan.org/spec/latest/chapters/synchronization.html) —
`UNDEFINED` meaning "discard the contents, I'm about to overwrite everything." Vulkan does not
track the current layout for you; *you* track it. This is the single most common source of
validation errors in a first renderer, and m20-03's swapchain image is where you will meet it.

### Memory: you allocate, and then you sub-allocate

The device exposes **heaps** (physical pools of memory, with sizes) and **memory types**
(combinations of properties drawn from a heap: `DEVICE_LOCAL`, `HOST_VISIBLE`,
`HOST_COHERENT`, `HOST_CACHED`, `LAZILY_ALLOCATED`). To create a buffer you allocate a
`VkDeviceMemory` of a suitable type and bind the buffer to it. The naive reading —
one allocation per resource — is wrong everywhere, and on most desktop drivers it is *fatally*
wrong: `maxMemoryAllocationCount` is a real limit and is commonly around four thousand.

The industry answer is a sub-allocator: allocate a small number of large blocks and hand out
`(VkDeviceMemory + offset + size)` triples. That is exactly what AMD's Vulkan Memory Allocator
does — *"functions that allocate memory blocks, reserve and return parts of them
(`VkDeviceMemory` + offset + size) to the user. Library keeps track of allocated memory
blocks, used and unused ranges inside them, finds best matching unused ranges for new
allocations, respects all the rules of alignment and buffer/image granularity"* [[VMA]](https://gpuopen.com/vulkan-memory-allocator/) —
and it is *"integrated into the majority of Vulkan® game titles on PC"* [[VMA]](https://gpuopen.com/vulkan-memory-allocator/).

Stop and notice what that is. It is m02's arena: one big block, a bump of an offset, alignment
rules, group-by-lifetime. You have already built this. The new parts are that alignment is
dictated by the device rather than by the type, that the memory may not be CPU-addressable at
all (hence staging buffers in m22-01), and that freeing is bounded by the second timeline
rather than by scope.

### The spec does not check you — the layer does

*"Vulkan implementations are not required to validate that the correct use of each command is
satisfied"* [[VKSPEC §Fundamentals]](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html#fundamentals-validusage).
Break a rule and behaviour is undefined: it may work, it may render garbage, it may hang the
GPU, and it will very likely do something different on the next vendor's driver. There is no
`GL_INVALID_OPERATION` waiting for you.

`VK_LAYER_KHRONOS_validation` is the compiler you don't otherwise have. It intercepts every
call, checks it against the spec's valid-usage statements, and reports through
`VK_EXT_debug_utils` with a message you can breakpoint on. Treat it as non-negotiable in
development builds and off in shipping builds, and treat a validation error as a build break,
not a warning. Every hour you will spend in phase 2 is cheaper with it on.

### Capabilities are queried, recorded, and branched on

Vulkan runs on a phone, a laptop's integrated GPU, a workstation card, a console, and a
translation layer on top of someone else's API. It cannot promise the same feature set to all
of them, so it does something more useful: it tells you exactly what *this* implementation can
do, along four independent axes.

| Axis | Queried with | Shape |
|---|---|---|
| **API version** | `vkEnumerateInstanceVersion` (loader/instance) and `VkPhysicalDeviceProperties.apiVersion` (device) | one version number each — and they can differ |
| **Extensions** | `vkEnumerateInstanceExtensionProperties` / `vkEnumerateDeviceExtensionProperties` | a list of names; opt in by name |
| **Features** | `vkGetPhysicalDeviceFeatures2` + a `pNext` chain of `VkPhysicalDevice*Features` structs | booleans — "can you do this at all" |
| **Limits & properties** | `VkPhysicalDeviceProperties.limits`, plus per-format `vkGetPhysicalDeviceFormatProperties` | numbers and bitmasks — "how much, how big, which formats" |

Three rules make this into engineering rather than trivia.

**Version subsumes extensions.** Vulkan promotes proven extensions into the core API at each
minor release: *"each minor release version of Vulkan promoted a different set of extension to
core. This means that it's no longer necessary to enable an extensions to use it's
functionality if the application requests at least that Vulkan version (given that the version
is supported by the implementation)"* [[KHR-GUIDE Release Summary]](https://docs.vulkan.org/guide/latest/vulkan_release_summary.html).
`VK_KHR_dynamic_rendering` and `VK_KHR_synchronization2` were promoted in **1.3**;
`VK_KHR_timeline_semaphore` and `VK_KHR_buffer_device_address` in **1.2**
[[KHR-GUIDE Release Summary]](https://docs.vulkan.org/guide/latest/vulkan_release_summary.html).
So "modern Vulkan" mostly means *target a high enough core version*, and the fallback is
*ask for the extension by name*, and the fallback to that is *do it the old way*. Same
capability, three tiers of availability.

**Supported is not enabled.** You query with `vkGetPhysicalDeviceFeatures2`, whose `pNext`
chain lets one call fill in extension and newer-core feature structs together — but
*"all features must be enabled at `VkDevice` creation time inside the `VkDeviceCreateInfo`
struct"*: core-1.0 features via `pEnabledFeatures`, everything else by chaining a
`VkPhysicalDeviceFeatures2` onto `VkDeviceCreateInfo.pNext`
[[KHR-GUIDE Enabling Features]](https://docs.vulkan.org/guide/latest/enabling_features.html).
Query, decide, then *re-declare what you decided*. Using a supported-but-not-enabled feature
is invalid usage — undefined behaviour that validation catches and the driver does not
[[VKSPEC §Fundamentals]](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html#fundamentals-validusage).

**Branch on capability, never on platform.** This is the design rule, and it is the one worth
arguing about. The tempting shortcut is `when ODIN_OS == .Darwin` — you know MoltenVK is
weaker in specific ways, so you special-case the OS. It is wrong for a reason that has nothing
to do with tidiness: the OS is not the thing that varies. MoltenVK 1.4 on an M2 and MoltenVK
1.2 on an older Mac differ from each other; two Windows machines with a 2015 GPU and a 2024
GPU differ far more than macOS and Windows do; and the same binary on the same OS behaves
differently after a driver update. Every OS check is a guess about capability that goes stale,
silently, on someone else's machine. Every capability check is a fact, obtained at startup,
about the machine actually running.

So the renderer does exactly one capability pass, at device creation, and produces one
**immutable capability record** — resolved decisions, not raw query results:

- what core version we got, and therefore which promoted features are free;
- which optional extensions we asked for and actually received;
- the resolved answer to each question the renderer will ask later ("do we take the dynamic-rendering path?", "is `synchronization2` available?", "what is our max MSAA sample count?");
- the limits later code must respect (alignments, max image dimension, allocation count).

Nothing downstream re-queries the device, and nothing downstream mentions an operating system.
Code reads `caps.dynamic_rendering`, not `ODIN_OS`, and not `vkGetPhysicalDeviceFeatures2`.
That is the same discipline as m11-02's frame-coherent input snapshot — query once at a
defined point, then let everyone read one consistent view — and it earns the same benefit:
decisions are made in one auditable place instead of scattered across the frame.

**Three legitimate shapes of fallback**, and it matters which one you're writing:

1. **Path fallback** — same visible result, different code. Dynamic rendering vs. render-pass
   and framebuffer objects; `synchronization2` barriers vs. the original barrier structs. Costs
   you a second code path to maintain and test.
2. **Quality fallback** — reduced result, still correct. Fewer MSAA samples, smaller shadow
   maps, no anisotropic filtering, a simpler shader. Costs you a decision about what "good
   enough" means.
3. **Hard requirement** — refuse to run. Entirely legitimate, and much kinder than limping:
   check at startup, name the missing capability, and exit. A renderer that fails clearly on
   launch beats one that corrupts at frame 500.

The teaching order for the rest of phase 2 follows from this: **the modern path is what we
learn and what we write first**, because it is simpler, it is where the API is going, and it is
what the hardware you're on supports. The fallback is written second, deliberately, and marked
as such. What you must not do is invert that — learning Vulkan 1.0's render passes first
"because they're more compatible" teaches you a worse mental model to save a compatibility
problem you can measure instead of guess at.

And the honest problem with fallbacks: **the path you don't run is the path that doesn't work.**
Your M2 reports Vulkan 1.4, so nearly every modern feature is core-available and your fallback
branches will never execute in normal development. The fix is in the section below, and it's
already installed on this machine.

### Where you are actually standing

The machine you are developing on does not have a Vulkan driver, which makes it the first and
best customer for everything above. Apple ships Metal; Vulkan reaches the GPU through
**MoltenVK**, *"a layered
implementation of Vulkan 1.4 graphics and compute functionality, that is built on Apple's
Metal graphics and compute framework"* and *"a key component of the Khronos Vulkan Portability
Initiative"* [[MOLTENVK]](https://github.com/KhronosGroup/MoltenVK) — that initiative being
*"an effort inside the Khronos Group to develop resources to define and evolve the subset of
Vulkan capabilities that can be made universally available at native performance levels across
all major platforms"* [[KHR-GUIDE Portability]](https://docs.vulkan.org/guide/latest/portability_initiative.html).

Translation cannot be complete, so the portability extension exists to say so. It lets a
non-conformant implementation *"mark otherwise-required capabilities as unsupported, or to
establish additional properties and limits that the application should adhere to in order to
guarantee portable behavior and operation across platforms"*, and its presence is itself the
signal: *"fully-conformant Vulkan implementations provide all the required capabilities, and
so will not provide this extension"* [[VKPORT]](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/appendices/VK_KHR_portability_subset.adoc).
Two obligations land on m20-02, and both fail in confusing ways if missed:

1. **At instance creation** — enable `VK_KHR_portability_enumeration` and set
   `VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR`, because *"the Vulkan Loader will only
   include MoltenVK VkPhysicalDevices in the list returned by vkEnumeratePhysicalDevices() if
   the VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR flag is enabled in
   vkCreateInstance()"* [[MOLTENVK]](https://github.com/KhronosGroup/MoltenVK). Forget it and
   the machine appears to have no GPU.
2. **At device creation** — *"if this extension is supported by the Vulkan implementation, the
   application must enable this extension"* [[VKPORT]](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/appendices/VK_KHR_portability_subset.adoc).
   Not optional, not conditional on using any of its features.

And one trap that is already documented in this project: SDL, asked to load Vulkan with no
hint, can open MoltenVK **directly** and bypass the loader entirely — at which point
`VK_KHR_portability_enumeration` does not exist (it is a loader feature) and no validation
layer loads, silently. The fix on this machine is the `SDL_VULKAN_LIBRARY` environment
variable pointing at the real `libvulkan`, which is why the loader tier above is worth
understanding rather than accepting. [unverified — SDL's default library-search behaviour here
is an observation on this machine, not a documented SDL guarantee.]

Notice how little of that is macOS-specific in *form*. Detecting `VK_KHR_portability_subset` is
an extension query; setting the enumeration flag is conditional on an instance extension being
present; and `VkPhysicalDevicePortabilitySubsetFeaturesKHR` is just another feature struct to
chain onto the `pNext` of your `vkGetPhysicalDeviceFeatures2` call and fold into the capability
record. A renderer written the way the previous section describes handles a translation layer
without a single `when ODIN_OS` — it reads the machine, records what it found, and takes the
narrower path where required. Which is the whole argument: the portability subset is not an
Apple problem, it is the general problem wearing today's clothes.

**And this is where the fallback paths become testable.** The `VK_LAYER_KHRONOS_profiles` layer
— installed on this machine, as the census will confirm — takes a **profile**, meaning
*"the explicit expression and formalization of Vulkan requirements"*: a named capability set
covering version, extensions, features, and limits [[VKPROFILES]](https://github.com/KhronosGroup/Vulkan-Profiles/blob/main/OVERVIEW.md).
Crucially it *"simulates but doesn't emulate"* — it **restricts** what the device reports to
match the profile rather than adding functionality — so *"when combined with the Validation
Layer, developers can test applications as if running on more limited hardware than their
development system"* [[VKPROFILES]](https://github.com/KhronosGroup/Vulkan-Profiles/blob/main/OVERVIEW.md).
Point it at a lower baseline such as `VP_LUNARG_desktop_baseline_2024` (Vulkan 1.2) and your
1.4 M2 will honestly report itself as a 1.2 device — your capability record takes the fallback
branches, and validation tells you whether they were right. One machine, both paths exercised.
That is what makes "keep the fallback available" a claim you can verify rather than hope for.
(Confirmed working on this machine before this lesson shipped: under that profile the M2's
`VkPhysicalDeviceProperties.apiVersion` drops from 1.4.334 to 1.2.197. The full before/after
diff is one of this lesson's measurements.)

Which raises a distinction worth nailing down now, because four version numbers are in the air
on this machine and only two of them are Vulkan API versions:

| Number | Value here | What it is |
|---|---|---|
| SDK package | `1.4.350.1` | LunarG's *distribution* version — four components, not an API version |
| Instance / loader | `1.4.350` | `vkEnumerateInstanceVersion` — the highest version the loader speaks |
| **Device** | `1.4.334` | `VkPhysicalDeviceProperties.apiVersion` — the highest version *this driver on this GPU* supports |
| Driver build | `1.4.1` / `0.2.2209` | MoltenVK's own version (`driverInfo` / `driverVersion`) — no relation to the API version |

The device number is the one the capability record is built from, because it decides which
promoted features are free. Note that it is **lower** than the loader's: a new SDK does not
upgrade the driver underneath it. Assuming the device matches the instance is wrong by 16 patch
releases here and harmless — but on a machine with a 1.4 loader over a 1.1 driver it is the
difference between working code and undefined behaviour, which is why axis 1 is *two* queries
and not one.

### The shape this takes in odyne

`engine/render` is one package today, containing an `info()` stub. Over m20–m23 it becomes the
Vulkan renderer, and the layering law fixes its boundary in advance: **no `vk*` type appears in
any signature outside `engine/render`.** Textures, buffers, and pipelines cross the boundary as
odyne handles — `distinct` types over the generational handle pool you built in m03 — which is
precisely the seam that lets phase 5 slide a DX12 backend underneath without `engine/game`
noticing, exactly as SDL3 slid underneath `window.odin` and `input.odin` in phase 1.

Two standing rules for the whole of phase 2, both consequences of the capability section:

- **The capability record is built once, in m20-02, and is the only source of truth about what
  the device can do.** It is produced by device selection and thereafter immutable. Every later
  lesson that wants a modern path adds a resolved field to it rather than querying the device
  again — so by m23 there is a single place that answers "what kind of machine is this?", and a
  single place to look when a bug turns out to be capability-dependent.
- **No `when ODIN_OS` in `engine/render`.** Platform differences enter through the capability
  record or not at all. If a genuine OS difference appears that capabilities cannot express —
  surface creation is the likely candidate — it belongs behind the platform layer's seam, where
  `window_sdl.odin` already absorbs exactly that kind of difference, not sprinkled through
  renderer code.

Those two rules are the design commitment this lesson makes on m20-02's behalf; m20-02's design
conversation gets to decide the *shape* of the record, not whether there is one.

## In the industry

The order this curriculum uses is the order the reference tutorial uses, and for the same
reason. [VKGUIDE] is structured *ch.0* project setup → *ch.1* initialization and a render loop
to a clear colour → *ch.2* compute → *ch.3* meshes through the graphics pipeline → *ch.4*
textures and descriptors → *ch.5* glTF scenes, and it deliberately uses **dynamic rendering
rather than render passes** *"so that it can act as a better base code for a game engine"*
[[VKGUIDE]](https://vkguide.dev/). odyne follows that choice: render-pass objects and
framebuffers were Vulkan 1.0's way of declaring attachment usage up front for tiler hardware,
and dynamic rendering (core in 1.3) removes an entire class of object plumbing that a
learning engine gains nothing from.

Memory management is the clearest case of "nobody hand-rolls this in shipping code": VMA is
*"integrated into the majority of Vulkan® game titles on PC"*, and also used by Google
Filament and the official Khronos Vulkan Samples [[VMA]](https://gpuopen.com/vulkan-memory-allocator/).
odyne will write its own sub-allocator anyway, in m22-01 — that's the point of the course —
but knowing the shipping answer tells you what shape the result should be.

The layering law this lesson enforces is the standard engine-architecture move: Gregory's
rendering chapter builds up from the hardware and the pipeline before any engine abstraction
sits on it [[GEA §11.1–11.2]](https://www.gameenginebook.com/), and the reason every large
engine has a "render hardware interface" is that graphics APIs are the part of the stack that
changes underneath you — Vulkan, D3D12, Metal, and consoles' own. Phase 5 is where odyne pays
that lesson forward; phase 2's job is to earn the right to design that seam by having built
one backend for real.

Capability targeting is formalized enough to have its own Khronos toolset. A **Vulkan Profile**
is *"the explicit expression and formalization of Vulkan requirements"* — a named baseline of
version, extensions, features, and limits that an application declares it needs, instead of
assuming universal support [[VKPROFILES]](https://github.com/KhronosGroup/Vulkan-Profiles/blob/main/OVERVIEW.md).
The predefined set tells you how the industry slices the hardware landscape:
`VP_KHR_roadmap_2022` and `VP_KHR_roadmap_2024` (both Vulkan 1.3) are Khronos's statements of
what modern hardware should be assumed to have; `VP_LUNARG_desktop_baseline_2024` (1.2) is the
conservative desktop floor; `VP_ANDROID_vulkan_profile_2022` (1.1) is mobile reality
[[VKPROFILES]](https://github.com/KhronosGroup/Vulkan-Profiles/blob/main/OVERVIEW.md). Engines
pick a floor like these and then tier upward from it — which is exactly the modern-path-first,
fallback-behind-a-check structure this lesson argues for, at industry scale. odyne will not
adopt the profiles library, but the capability record m20-02 builds is a hand-rolled profile
check, and knowing that shape exists tells you what "done" looks like.

Finally, the platform reality: shipping a Vulkan renderer on Apple hardware *means* shipping on
MoltenVK, and the portability subset is not an exotic case but the normal condition of
cross-platform Vulkan in 2026 [[MOLTENVK]](https://github.com/KhronosGroup/MoltenVK) [[KHR-GUIDE Portability]](https://docs.vulkan.org/guide/latest/portability_initiative.html).
Developing on it from day one is an advantage: you will find the portability mistakes now
instead of at port time — provided the renderer is written to read the machine rather than to
recognize it.

## Performance notes

The cost model to carry into phase 2:

- **Object creation is expensive; object use is cheap.** Pipelines, descriptor set layouts,
  and render targets are built once and reused; that asymmetry is the whole design. Anything
  you create per frame is a bug in waiting.
- **The CPU cost of a frame is recording, not drawing.** Command buffer recording is your
  code, on your threads, and is measurable with your own timer from m11-01. Anything after
  `vkQueueSubmit` is on the other timeline and needs GPU timestamps to see.
- **Allocation counts are a hard limit, not a soft one** — `maxMemoryAllocationCount`, and
  the reason VMA ships a debug macro whose only job is catching you exceeding it [[VMA]](https://gpuopen.com/vulkan-memory-allocator/).
- **Validation is a development cost you pay deliberately.** Every call goes through an extra
  intercepting layer [[VKLOADER]](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md);
  you want the number so you know what you're trading.
- **Capability checks are free where they're read and expensive where they're asked.** Device
  queries are startup-time API calls; a resolved `caps.dynamic_rendering` is a bool load from a
  struct that is hot in cache and branch-predicted perfectly. That asymmetry is the performance
  argument for the record — and the reason a per-frame or per-draw capability query is a bug,
  not merely inelegant.

**Measurement task (tutor-run; numbers recorded in `curriculum/JOURNAL.md`).** No engine code
exists yet, so this lesson measures the *machine and the toolchain* — the ground truth m20-02
will be written against:

1. **Capability census** (`vulkaninfo`), organized along the four axes so the record m20-02
   builds has a template: **version** (instance vs device `apiVersion` — they differ here),
   **extensions** (instance and device counts, plus whether each of dynamic rendering,
   `synchronization2`, timeline semaphores and buffer device address is *core-available*,
   *extension-only*, or *absent* — the three-tier availability from §Capabilities, filled in for
   real), **features** (the `VkPhysicalDevicePortabilitySubsetFeaturesKHR` table, specifically
   which entries are `false` on this M2), and **limits** (`maxMemoryAllocationCount`,
   `maxImageDimension2D`, `maxPushConstantsSize`, `minUniformBufferOffsetAlignment`,
   `nonCoherentAtomSize`). Plus the structural facts m20-02 depends on — **queue families and
   their flags**, **memory heaps and memory types**, the ICD list with driver name and
   conformance version. Recorded next to typical discrete-GPU values, because the contrast is
   the lesson: what this machine reports is not what a tutorial written for a desktop card will
   assume.
2. **The fallback path, made visible.** Re-run the census under `VK_LAYER_KHRONOS_profiles`
   forcing a lower baseline (`VP_LUNARG_desktop_baseline_2024`, Vulkan 1.2) and record what
   *changed*: which features and extensions disappeared, which limits shrank, what the reported
   `apiVersion` became. That diff is the concrete list of decisions a capability record has to
   make, and the demonstration that a single machine can exercise both branches
   [[VKPROFILES]](https://github.com/KhronosGroup/Vulkan-Profiles/blob/main/OVERVIEW.md).
3. **The layer stack, observed.** Run a real Vulkan program (`vkcube` from the SDK) under
   `VK_LAYER_LUNARG_api_dump` and count: how many Vulkan calls happen **before the first
   frame**, and how many happen **per frame** thereafter. That number is the concrete answer to
   "how much ceremony is this API", and the per-frame figure is the budget m21-02's triangle
   will be measured against. Then run it with and without `VK_LAYER_KHRONOS_validation` to get
   the validation cost as a frame-time delta.
4. **Toolchain zero-point.** Build a throwaway package that does nothing but
   `import vk "vendor:vulkan"` and record the compile-time and binary-size delta against an
   empty package — `vendor:vulkan` is a large binding and this is the "before" number for the
   build-time curve m01-01 started watching. Plus `glslc` on a trivial vertex+fragment pair:
   compile time and SPIR-V byte size, the m21-01 baseline.

The tutor records **Built + Measured** and walks you through the numbers; you write
**Takeaways + Reflections**.

## Exercise

Concept lesson — 11 recall questions, answered in your own words (in chat or written into this
file; the tutor reviews against the sources and asks ≥2 follow-up probes). No code this
lesson; m20-02 is where you design and build instance, device, queue selection **and the
capability record**, and m20-03 the swapchain.

1. Name the four jobs an explicit API declines to do for you that OpenGL/D3D11 did in the driver. For each, say what you have to build instead, and name the *symptom* the old way produced that the new way is meant to remove.
Memory management - You are in charge of the memory 
Swapchain management - You are in charge of the frames and the triple buffers
Synchronization - You are in charge of syncing device and host
Resource Management - You are in charge of cleaning up resources
Command Buffers - You are in charge of recording commands for gpu bound operations

2. Sketch the call path from your program to the GPU, naming each tier. Where do validation layers sit, how does the loader find them, and why can't you get validation by linking a library or flipping a compile flag?

Instance creation - binding layers(validation) - physical device selection - device creation - device features/capabilities selections - then device creates everything else

3. Odin's `vendor:vulkan` has no `foreign import` — every entry point is a function pointer you fill in. Explain what in the loader architecture makes that the *honest* binding, and why `load_proc_addresses` has to be called more than once.

We will need to call load_proc_address for instance and then device and then for some extensions

4. Distinguish dispatchable from non-dispatchable handles: what is each, physically, and why does the loader care about the difference? Connect the non-dispatchable case to what you learned in m03-01 about opaque handles.

dispatcahable  handles are opaque handles that point to a struct that points to a set a loader
that has a set of pointers to a functoin table
non-dispatchables are literally just handles

5. `vkQueueSubmit` has returned `VK_SUCCESS`. State precisely what you now know and what you do not. Then: you want to free the buffer that submission read from — what is the only thing that tells you it's safe, and why is `defer` insufficient?
THe queueSubmit just means that the commands are submitted - it doesn't mean that they are executed. You are responsible for making sure that the device and host are ready to move on via sync primitives - if you defer when the frame ends - you are not guaranteed that the queue was executed.

6. Fence, semaphore, barrier: give the edge each one synchronizes (which two parties) and a one-line example of when you reach for it. Then explain why an execution dependency alone can still leave a reader seeing stale data, using "available" and "visible" correctly.

fence - device - queue sync (make sure the next time we use the frame handles that they're ready)
semaphore - queue to queue - make sure that the requirements of one queue are met before using 
pipeline barrier - in queue helps transition memory and pipelines based on future dependencies etc

7. Why is one `vkAllocateMemory` per buffer wrong? Give both the hard-limit reason and the performance reason, then say what the standard fix is — and what you already built in m02 that has the same shape and where the analogy breaks down.

You have a hard limit of allocations you can do within the API - the standard fix is to use a sort of Arena allocator where you allocate based on the size the Vulkan API gives you

8. Name the four axes along which Vulkan reports capabilities and how each is queried. Then explain the query-vs-enable asymmetry: what does `vkGetPhysicalDeviceFeatures2` tell you, what do you still have to do, and what happens if you skip it?

API version
Extensions
Features
Limits & properties

you need to query - decide and then enable -- you have to query through VkPhysicalDevice*Featuers capabilities and feature sets for enableing extensions and featuers

9. Make the case against `when ODIN_OS == .Darwin` in `engine/render` to a colleague who thinks it's simpler than a capability record. Give at least two concrete ways the OS check goes wrong that a capability check doesn't. Then: something *is* genuinely OS-specific in getting Vulkan on screen — what, and where does it belong instead?
There can be api differences between vulkan versions and an old mac might lack some features that the new one has - therefore , this is not a OS-specific enablement. We need to clearly understand each systems capabilitiies.

10. Dynamic rendering is core in Vulkan 1.3, an extension before that, and absent from Vulkan 1.0. Describe the three-tier availability check you'd write, and say which of the three fallback shapes (path / quality / hard requirement) each tier calls for. Then: your M2 reports Vulkan 1.4, so the fallback branches never run in development — what do you do about that, and why is "test it when we port" the wrong answer?

path fallback (use older version) - quality fallback (render less quality) - hard fallback (refuse and exit)

11. You are on an Apple M2 with no Vulkan driver. What is MoltenVK, what does the presence of `VK_KHR_portability_subset` tell you, and what are the two things m20-02 must do about it? What is the observable symptom of getting each one wrong? Finally — how much of your answer is actually macOS-specific, as opposed to the general capability machinery wearing a Mac hat?

it's a translation layer supported by the khronos group the aim is to have proper support in the macos platform as well. The portability subset is required for the MoltenVK to function.
moltenVK requires the portability subset to load the physical devices in macos. I don't know if it has use cases anywhere else.

### Definition of done

- Recall questions answered well (tutor-reviewed) · ≥2 follow-up probes answered
- Measurement task run by the tutor; **Built + Measured** recorded in `curriculum/JOURNAL.md`
- Journal entry completed — **Takeaways + Reflections** in your own words

## Reading list

- **Required:** [What is Vulkan? [KHR-GUIDE]](https://docs.vulkan.org/guide/latest/what_is_vulkan.html) — short, sets the frame; [Vulkan API introduction [VKGUIDE]](https://vkguide.dev/docs/introduction/vulkan_overview/) — the same picture from an engine-builder's angle, plus what ch.0/ch.1 will ask of you; [[VKSPEC §Fundamentals]](https://docs.vulkan.org/spec/latest/chapters/fundamentals.html) — read the **Object Model**, **Execution Model**, and **Valid Usage** sections only, and read them properly: this is the lesson's spine.
- **Also required, both short:** [Vulkan Release Summary [KHR-GUIDE]](https://docs.vulkan.org/guide/latest/vulkan_release_summary.html) — skim the promotion tables; you want the *habit* of asking "which core version did this land in", not the contents memorized. [Enabling Features [KHR-GUIDE]](https://docs.vulkan.org/guide/latest/enabling_features.html) — the query-then-enable asymmetry, which m20-02 gets wrong once if you skip this.
- **Recommended:** [Architecture of the Vulkan Loader Interfaces [VKLOADER]](https://github.com/KhronosGroup/Vulkan-Loader/blob/main/docs/LoaderInterfaceArchitecture.md) — the "Overview" and "Application Interface to Loader" sections; [Vulkan Profiles OVERVIEW [VKPROFILES]](https://github.com/KhronosGroup/Vulkan-Profiles/blob/main/OVERVIEW.md) — read the "What is a Vulkan Profile" and Profiles Layer parts; this is the industry's version of what m20-02 builds by hand, and the tool that keeps your fallbacks honest; [[VKPORT]](https://github.com/KhronosGroup/Vulkan-Docs/blob/main/appendices/VK_KHR_portability_subset.adoc) and [[MOLTENVK]](https://github.com/KhronosGroup/MoltenVK) — the ground you are standing on, skim both; [[VKSPEC §Synchronization]](https://docs.vulkan.org/spec/latest/chapters/synchronization.html) — the introduction and the fence/semaphore/barrier definitions; don't try to absorb the whole chapter, you'll return to it every lesson of phase 2.
- **Deeper:** [Vulkan Memory Allocator [VMA]](https://gpuopen.com/vulkan-memory-allocator/) — the shipping answer to device memory, which m22-01 will re-derive; [GEA §11.1–11.2](https://www.gameenginebook.com/) — rasterization foundations and the rendering pipeline, the hardware story under all of this; [RTR](https://www.realtimerendering.com/) — the graphics pipeline and GPU architecture chapters, for the theory phase 2 assumes and m43 will need. [unverified — RTR 4e chapter numbers not confirmed; publisher's site returned HTTP 403 at verification.]
