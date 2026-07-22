# Lesson: m10-01/win32-window — A Win32 window

> **Type:** build · **Module:** m10 Window & input · **Interface:** learner-designed (the `engine:platform` window API — what the layers above are allowed to see; Win32 itself is fixed by Microsoft)

## Goals

- Put a real window on screen from `engine/platform` — raw Win32 through `core:sys/windows`, no GLFW/SDL-style middleware — and run its message loop cleanly.
- Understand the Win32 windowing model: window **class** → `CreateWindowExW` → the **window procedure** → the **message loop**, and why the OS's push-model callback must be adapted to the engine's poll-model frame loop.
- Design the platform layer's first real public surface under the layering law: handle-based, no `HWND` leaking upward — the discipline m03 built, applied for the first time at an OS boundary.
- Meet Odin's foreign-callback reality: a `proc "system"` has **no Odin context** — the first time ZII-and-context comfort meets a boundary where neither exists.

## Prerequisites

- **m03 (containers & handles)** — the handle discipline and the pool; this lesson is its first consumer at a package boundary.
- **m02 (memory)** — allocator awareness for whatever state the platform layer keeps.
- **m01-01 (skeleton)** — `engine:platform` exists, may import `core`, must never import `render`/`game`.

## Explanation

### The platform layer earns its name

Until now `engine/platform` was a stub. Gregory's architecture places a *platform independence layer* just above the OS: the rest of the engine talks to it, and only it talks to the operating system [[GEA ch.1]](https://www.gameenginebook.com/). That's the contract this lesson establishes: **`import "core:sys/windows"` appears in `engine/platform` and nowhere else, ever.** The render layer will get a surface to draw into, the game layer will get events — neither will ever see an `HWND`. This is the same seam discipline as "no `vk*` outside the Vulkan package" in phase 2; the window is where the habit starts.

### The Win32 model in four moves

Microsoft's own tutorial is the cleanest map [[WIN32 Creating a Window]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/creating-a-window):

1. **Register a window class** — a `WNDCLASSEXW` naming a class and, crucially, a pointer to your **window procedure**. A "class" here is an OS-side data structure, not an OOP class; it exists so many windows can share behavior.
2. **`CreateWindowExW`** — instantiate the class: style flags (`WS_OVERLAPPEDWINDOW`), title, size, and back comes an `HWND` — Windows' own opaque handle. (You spent m03 building exactly this shape: index-plus-liveness behind an integer. Microsoft has shipped it since 1985.)
3. **The window procedure** — a callback the OS invokes with messages (`WM_CLOSE`, `WM_SIZE`, `WM_DESTROY`, …). Anything you don't handle goes to `DefWindowProcW`, which supplies all default window behavior.
4. **The message loop** — Windows doesn't call your WndProc out of thin air: your thread must pump the queue. A game uses the non-blocking form — `PeekMessageW` / `TranslateMessage` / `DispatchMessageW` — once per frame, so the loop never stalls waiting for input. Handmade Hero builds this exact structure on camera and it's worth watching being discovered rather than recited [[HMH day 2]](https://guide.handmadehero.org/code/day002/).

### Push meets poll: the impedance mismatch

Here is the design problem the whole lesson turns on. Win32 *pushes*: during `DispatchMessageW`, the OS calls your WndProc re-entrantly with whatever messages arrived. Your engine *polls*: once per frame it wants to ask "what happened since last frame?" Every windowing abstraction ever written is a buffer between those two models — the WndProc's job is to **record** events somewhere, and the platform API's job is to **serve** them to the frame loop. Where that buffer lives, what an "event" is, and how the caller drains it — that's your `design.md` sketch.

Two Win32 mechanics make the buffering non-trivial, and both are worth understanding before you sketch:

- **WndProc has no user parameter.** The OS calls it with `(hwnd, msg, wparam, lparam)` — no pointer to *your* state. The sanctioned pattern: smuggle your state pointer through `CreateWindowExW`'s last parameter, catch it in `WM_NCCREATE`/`WM_CREATE` via the `CREATESTRUCTW`, store it on the window with `SetWindowLongPtrW(hwnd, GWLP_USERDATA, ...)`, and fetch it with `GetWindowLongPtrW` on every later message [[WIN32 Creating a Window]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/creating-a-window). It's the moral equivalent of a C callback's `void* userdata`, except you have to build the plumbing yourself.
- **Close is a negotiation, not an event.** Clicking ✕ sends `WM_CLOSE` — a *request*. Default handling destroys the window; engines instead record "close requested" and let the frame loop decide (save first, confirm, etc.). `WM_DESTROY` is the actual teardown notification. Your API needs to expose the request without surrendering the decision.

> **C++ delta #1 — `proc "system"` and the missing context.** In C++ a WndProc is just a free function with the right calling convention. In Odin, a foreign callback is `proc "system" (...)` — and procs with a foreign calling convention **do not receive the implicit `context`** [[ODIN §Foreign system]](https://odin-lang.org/docs/overview/#foreign-system). No `context.allocator`, no `context.temp_allocator`, nothing — inside the WndProc you are in C-land. If the callback needs Odin machinery, it must establish a context itself (`context = runtime.default_context()` is the standard opening line). Better: need as little as possible in there — record the event into plain memory reached via `GWLP_USERDATA` and get out.
>
> **C++ delta #2 — UTF-16 at the border.** Odin strings are UTF-8; the Win32 `W` API speaks UTF-16 (`wchar_t`). Every title crossing the boundary converts — `core:sys/windows` ships the helpers (`utf8_to_wstring`) alongside the full bindings, so unlike C++ there's no `<windows.h>` macro fog and no `TCHAR` archaeology: 1000+ typed declarations, `WS_*`/`WM_*` constants included [[ODIN-SYS]](https://pkg.odin-lang.org/core/sys/windows/).

### Windows-only code in a portable tree

This is odyne's first OS-specific code. Odin resolves this by file, not by `#ifdef`: a file named `*_windows.odin` (or opening with a `#+build windows` tag) compiles only on Windows [[ODIN]](https://odin-lang.org/docs/overview/). The portable surface (types + procs the engine calls) and the Win32 implementation can live in separate files inside `package platform` — when a Linux backend arrives, it's a sibling `*_linux.odin`, same surface, and callers never notice. Decide the file split in your sketch.

### The boundary is handle-based — you built the tool

The layering law requires handle-based cross-package APIs, and you now own a generational handle pool in `engine:core` whose whole purpose is this seam. The design question you must take a position on: does the window API deal in a `Window_Handle` (distinct, pool-backed — even if the pool holds one window for years), or in something simpler (a single implicit window, HMH-style module state)? There are real arguments both ways — multi-window is speculative generality today, but the handle keeps `HWND` provably private and exercises the discipline every later system will follow (textures, buffers, entities). Whichever you choose, the hard rule stands: **no `HWND`, no `MSG`, no `core:sys/windows` type in any public signature.**

## In the industry

Every engine has this seam. Gregory's platform-independence layer exists precisely so "the rest of the engine doesn't know what OS it's on" [[GEA ch.1]](https://www.gameenginebook.com/). Handmade Hero spends its first week exactly where you are — window class, WndProc, message pump, and the discovery that the elegant-looking blocking `GetMessage` loop is wrong for games [[HMH day 2]](https://guide.handmadehero.org/code/day002/). Most shipped engines buy this layer as middleware (GLFW, SDL, or the console's proprietary equivalent) `[unverified — common knowledge, no registered source]`; odyne builds it raw for the same reason HMH does — so that when middleware is offered later, you know precisely what it's hiding. And Windows itself validates the m03 doctrine: `HWND` is an opaque handle into an OS-owned table — Microsoft has been running the "handles, not pointers" playbook for forty years.

## Performance notes

A window is created once; what runs forever is the **pump**. The numbers that matter:

**Measurement task (tutor-run; numbers recorded in `curriculum/JOURNAL.md`):**
1. **Empty pump cost** — `poll`/pump with no pending messages, measured over many frames (ns/frame). This is pure per-frame overhead the engine pays for its lifetime; it should be sub-microsecond.
2. **Window creation → visible** — one-shot wall time (ms) from `init` to the window painted. One number, for the journal's record of what startup costs.
3. **Build cost** — testbed clean `-o:speed` build time + binary size vs m03-03's 472,576 B baseline: the price of linking user32 and pulling `core:sys/windows` into the tree.

## Exercise

Bring up a window from `engine/platform`, driven by the testbed's frame loop, with the Win32 machinery fully hidden.

**Interface is learner-designed — that's your first task.** Sketch in `design.md` (§Learner sketch):

- **The public surface:** creation (what config? ZII defaults?), destruction, the per-frame pump, and how the frame loop learns "close was requested" and "the window resized." Signatures, in Odin.
- **The boundary type:** `Window_Handle` via your m03 pool, or a simpler single-window model — take a position and defend it against the layering law.
- **The event path:** what the WndProc records, where it records it (remember: no context, no user parameter — `GWLP_USERDATA` plumbing), and how the caller drains it. Define your event representation (enum? struct? fixed queue?).
- **File split:** portable surface vs `*_windows.odin` implementation.

The tutor critiques against the cited sources and records the agreed surface; then the spec delta and failing tests land against it.

- **Build:** implement in `engine/platform` — window class registration, `CreateWindowExW`, WndProc with `GWLP_USERDATA` state, `PeekMessageW` pump, clean destroy. `core:sys/windows` imports live only in platform.
- **Tested seam:** tests create a *hidden* window (no `ShowWindow`), exercise the lifecycle — create → pump → close-request → destroy — and verify events and handle validity without anything appearing on screen.
- **Demo checkpoint:** the testbed opens a visible titled window that stays responsive (moves, resizes, doesn't white-out) and exits cleanly when you click ✕ — verified by observation, the first odyne artifact you can *see*.
- **Constraints:** `odin test` green · leak-clean · `-vet -strict-style` clean · layering law holds (`core:sys/windows` nowhere above platform).

### Definition of done

- Tests green for `engine/platform` · leak check clean · vet/style clean across the tree
- Demo checkpoint confirmed by observation: visible window, responsive, clean exit via ✕
- `platform-window` spec delta written and its scenarios covered by passing tests
- Layering verified: no OS type in a public signature; `core:sys/windows` imported only in platform
- Measurement recorded in `curriculum/JOURNAL.md` · review passed · ≥2 comprehension probes answered
- Journal **Takeaways + Reflections** in your own words

## Reading list

- **Required:** [WIN32 Creating a Window](https://learn.microsoft.com/en-us/windows/win32/learnwin32/creating-a-window) — read the whole Learn-Win32 module through "Closing the Window" (window class → WndProc → message loop → close/destroy); [HMH day 2](https://guide.handmadehero.org/code/day002/) — watch a window brought up from nothing.
- **Recommended:** [ODIN §Foreign system](https://odin-lang.org/docs/overview/#foreign-system) — calling conventions and the missing context; skim [core:sys/windows [ODIN-SYS]](https://pkg.odin-lang.org/core/sys/windows/) for the bindings you'll call (`RegisterClassExW`, `CreateWindowExW`, `DefWindowProcW`, `PeekMessageW`).
- **Deeper:** [GEA ch.1](https://www.gameenginebook.com/) — the platform-independence layer in the runtime architecture; your own m03-01 LESSON — reread "why stored pointers rot" and notice `HWND` obeying every rule.
