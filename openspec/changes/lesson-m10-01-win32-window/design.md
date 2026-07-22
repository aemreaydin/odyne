# Interface design

> **Interface:** learner-designed — rationale: Win32's side of the seam is fixed by Microsoft;
> what's open is everything odyne-side — the platform window API the upper layers compile
> against, the boundary type, the event representation, and the WndProc→frame-loop buffering.
> This surface outlives the lesson: m10-02 (input) extends it, m20 (Vulkan) draws into it.

## Learner sketch

<!-- [you] Your proposed engine:platform window API. Rough is fine — this starts the design
     conversation. Address:
       - public surface: creation (config struct? ZII defaults for title/size?), destruction,
         the per-frame pump, close-request exposure, resize exposure — signatures in Odin
       - boundary type: Window_Handle via the m03 pool (defend the pool for a mostly-1-window
         engine) or a single-window model (defend it against the layering law) — take a position
       - event path: what the WndProc records, where (GWLP_USERDATA plumbing — no context, no
         user param in a proc "system"), what an event IS (enum/struct/fixed queue?), and how
         the frame loop drains it
       - file split: portable surface vs *_windows.odin implementation inside package platform
     Hard rule regardless of choices: no HWND / MSG / core:sys/windows type in any public
     signature. See lesson.md §Exercise for the full brief. -->

**The public surface:** creation (what config? ZII defaults?), destruction, the per-frame pump, and how the frame loop learns "close was requested" and "the window resized." Signatures, in Odin.
We'll need a window class and we'll start privaely a HWND and return a Window_Handle to the user. Outside platform, nothing will reference HWND and windows stdlib code. Every frame we will listen to messages via WndProc

- **The boundary type:** `Window_Handle` via your m03 pool, or a simpler single-window model — take a position and defend it against the layering law.
  We will have a Window_Handle distinct handle
- **The event path:** what the WndProc records, where it records it (remember: no context, no user parameter — `GWLP_USERDATA` plumbing), and how the caller drains it. Define your event representation (enum? struct? fixed queue?).
  On WM_CREATE we can use `SetWindowLongPtrW` to point to our state and use `GetWindowLongPtrW` to fetch it latter on
- **File split:** portable surface vs `*_windows.odin` implementation.
  \*\_windows.odin

## Tutor critique

The load-bearing calls are right: `Window_Handle` at the boundary, `HWND` and all of
`core:sys/windows` package-private, `GWLP_USERDATA` as the WndProc's state plumbing
[[WIN32 Creating a Window]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/creating-a-window),
`*_windows.odin` for the OS split. What's missing is everything tests bind to — signatures,
semantics, and one decision you haven't noticed you're making. Findings, worst-first:

**1 — "SetWindowLongPtrW to point to our state" is the m03 trap (the crux).**
Say your `Window_State` lives in your own m03 pool, and `GWLP_USERDATA` holds a raw
`^Window_State` into the pool's dense array. **Q1: what happens to that stored pointer when a
*different* window is destroyed?** Answer it from the pool's contract before reading on — then
reconcile it with what `GWLP_USERDATA` *can* hold: a `LONG_PTR`, i.e. 64 bits, i.e. **exactly a
`Window_Handle`**. The resolution I propose (and want you to justify in your own words to lock):
store the *handle* in `GWLP_USERDATA`, and let the WndProc resolve it through the pool on every
message — resolve → use → drop, the m03 borrowing rule applied *inside the OS callback*. The
callback that can't hold Odin's context also shouldn't hold Odin's pointers.

**2 — No signatures; tests bind to signatures.** Proposed full surface below — confirm or
adjust. Notable decisions embedded in it, each needing your yes/no:
- **(a) Package lifecycle:** `init(allocator)/shutdown()` bracket the window system (the pool
  needs an owner and the leak check needs a teardown to bind to). Window class registered
  lazily on first open.
- **(b) `hidden: bool` in the desc, ZII-false ⇒ visible by default.** Real callers get a
  visible window with an empty desc; tests pass `hidden = true` and never flash a window.
- **(c) State queries now, event queue in m10-02.** This lesson's frame loop needs exactly two
  facts — "close requested?" and "current size" — which `should_close(h)` and `client_size(h)`
  answer. An *ordered* event queue earns its complexity when keyboard input arrives (m10-02);
  building it now is speculative. Disagree if you want the queue today — but then your sketch
  must define the event struct and drain semantics.
- **(d) One global `pump_events()`, not per-window.** Win32 message queues are per-*thread*,
  not per-window; one `PeekMessageW` loop drains everything and `DispatchMessageW` routes to
  each window's WndProc by `hwnd` [[WIN32 Creating a Window]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/creating-a-window),
  the non-blocking shape HMH lands on for games [[HMH day 2]](https://guide.handmadehero.org/code/day002/).

**3 — Creation-time messages arrive before `CreateWindowExW` returns.** `WM_NCCREATE`,
`WM_CREATE`, and even a `WM_SIZE` are delivered to your WndProc *during* the create call —
before you've had any chance to call `SetWindowLongPtrW` yourself. The sanctioned sequence:
pool-add FIRST (handle exists, state is ZII), pass the handle as `CreateWindowExW`'s last
parameter, catch it in `WM_NCCREATE` from the `CREATESTRUCTW`, store it into `GWLP_USERDATA`
right there — every later message resolves normally
[[WIN32 Creating a Window]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/creating-a-window).
This ordering is part of the contract because a `WM_SIZE`-before-create-returns would otherwise
hit a window the pool doesn't know yet.

**4 — Close is recorded, never obeyed.** `WM_CLOSE` sets `close_requested` and returns 0
(*not* `DefWindowProcW`, whose default destroys the window). The frame loop reads
`should_close`, decides, and calls `close_window` — which is the only path to `DestroyWindow`.
The ✕ button asks; the engine answers.

**5 — WndProc discipline (the Odin part).** It's a `proc "system"` — no context
[[ODIN §Foreign system]](https://odin-lang.org/docs/overview/#foreign-system). First line
establishes one (`context = runtime.default_context()`); after that, touch only the pool
resolve and plain field writes. No allocation, no printing, no cleverness in the callback.

### Proposed interface — confirm or adjust (tests bind to this)

```odin
package platform
// portable surface in window.odin; all Win32 in window_windows.odin

Window_Handle :: distinct u64

Window_Desc :: struct {
	title:  string, // "" ⇒ "odyne"
	width:  i32,    // 0 ⇒ 1280 (client area)
	height: i32,    // 0 ⇒ 720
	hidden: bool,   // ZII false ⇒ visible; tests pass true
}

Window_Error :: enum {
	None,
	Init_Failed,     // class registration failed
	Create_Failed,   // CreateWindowExW failed
	Invalid_Handle,  // zero, stale, or foreign handle
}

init         :: proc(allocator := context.allocator)            // window-system state + pool
shutdown     :: proc()                                          // destroys remaining windows, frees pool
open_window  :: proc(desc: Window_Desc) -> (Window_Handle, Window_Error)
close_window :: proc(h: Window_Handle) -> Window_Error          // DestroyWindow + pool remove
pump_events  :: proc()                                          // per-frame; drains the thread queue
is_open      :: proc(h: Window_Handle) -> bool
should_close :: proc(h: Window_Handle) -> bool                  // ✕/Alt-F4 requested since open
client_size  :: proc(h: Window_Handle) -> [2]i32                // {0,0} on invalid handle
```

**Per-operation contract** (tests enforce; tests are in-package and may reach the private
`hwnd` to post a synthetic `WM_CLOSE`/`WM_SIZE`, then pump):

| Operation | Behavior | Edge |
|---|---|---|
| `init` | pool init from allocator; idempotent guard is learner's choice — state it | |
| `open_window` | pool-add first (ZII state) → class lazily registered → `CreateWindowExW` with handle as create param → `WM_NCCREATE` stores handle in `GWLP_USERDATA` → hwnd + size recorded; hidden windows skip `ShowWindow` | class fail → `Init_Failed`; create fail → pool entry removed, `Create_Failed` |
| `pump_events` | `PeekMessageW` loop until queue empty; `TranslateMessage` + `DispatchMessageW` | cheap when idle (measured) |
| WndProc | `context = runtime.default_context()`; resolve `GWLP_USERDATA` handle via pool; `WM_CLOSE` → `close_requested = true`, return 0; `WM_SIZE` → update size; `WM_DESTROY` → per your design; else `DefWindowProcW` | unresolvable handle → `DefWindowProcW` (never crash) |
| `should_close` / `client_size` / `is_open` | state queries via pool resolve | invalid handle → `false` / `{0,0}` / `false` |
| `close_window` | `DestroyWindow` + pool remove → handle stale | invalid/double → `Invalid_Handle` |
| `shutdown` | closes remaining windows, destroys pool | leak check binds here |

**To lock:** answer Q1 (the stored-pointer trap, in your own words — it's the whole reason the
handle goes in `GWLP_USERDATA`), and give yes/no on 2(a) init/shutdown, 2(b) hidden-flag
default, 2(c) state-queries-now/queue-in-m10-02, 2(d) global pump.

## Agreed interface

Locked 2026-07-22 (learner confirmed via the design Q&A). Q1 resolved with one correction
recorded for the journal: the learner first named A (the destroyed window) as the victim of the
stored-pointer scheme; the actual victim is **B, the surviving window**, whose state the pool's
swap-with-last relocates — any remove may move *your* item. The handle-in-`GWLP_USERDATA`
design stands precisely because resolve detects relocation and death; a raw pointer detects
neither. Names per learner: `create_window`/`destroy_window`, `poll_events`. `hidden` flag
confirmed. State-queries-now (event queue deferred to m10-02) and global pump confirmed.

**Threading note (contract):** the window system is single-threaded — `init`, `create_window`,
`poll_events`, `destroy_window`, `shutdown` are called from one thread, the thread that owns
the Win32 message queue (queues are per-thread). Tests run with `-define:ODIN_TEST_THREADS=1`.

`engine/platform/window.odin` (portable types) + `engine/platform/window_windows.odin`
(all Win32; the `_windows` suffix scopes it to Windows builds):

```odin
package platform

Window_Handle :: distinct u64

Window_Desc :: struct {
	title:  string, // "" ⇒ "odyne"
	width:  i32,    // 0 ⇒ 1280 (client area)
	height: i32,    // 0 ⇒ 720
	hidden: bool,   // ZII false ⇒ visible; tests pass true (no ShowWindow)
}

Window_Error :: enum {
	None,
	Init_Failed,    // window-class registration failed
	Create_Failed,  // CreateWindowExW failed
	Invalid_Handle, // zero, stale, or foreign handle
}

init           :: proc(allocator := context.allocator) // window-system state + pool
shutdown       :: proc()                               // destroys remaining windows, frees pool
create_window  :: proc(desc: Window_Desc) -> (Window_Handle, Window_Error)
destroy_window :: proc(h: Window_Handle) -> Window_Error
poll_events    :: proc()                               // per-frame; drains this thread's queue
is_open        :: proc(h: Window_Handle) -> bool
should_close   :: proc(h: Window_Handle) -> bool       // close requested since create
client_size    :: proc(h: Window_Handle) -> [2]i32     // {0,0} on invalid handle
```

**Internal structure (agreed; tests are in-package and may touch it):** package-private
`Window_State :: struct {handle: Window_Handle, hwnd: win32.HWND, size: [2]i32,
close_requested: bool}` stored in a package-private m03 pool
`handle_pool.Handle_Pool(Window_State, Window_Handle)`; `GWLP_USERDATA` holds the
**`Window_Handle`**, never a pointer; the WndProc resolves it per message (resolve → use →
drop).

**Per-operation contract** (tests enforce):

| Operation | Behavior | Edge |
|---|---|---|
| `init` | pool init from allocator | |
| `create_window` | pool-add first (ZII state) → window class lazily registered (already-registered counts as success) → `CreateWindowExW` with the handle as the create param → `WM_NCCREATE` stores it in `GWLP_USERDATA` → hwnd + client size recorded; `hidden` skips `ShowWindow`; ZII desc ⇒ "odyne", 1280×720, visible | class fail → `Init_Failed`; create fail → pool entry removed, `Create_Failed` |
| `poll_events` | `PeekMessageW` loop until empty; `TranslateMessage` + `DispatchMessageW`; never blocks | cheap when idle (measured) |
| WndProc | `context = runtime.default_context()` first; resolve `GWLP_USERDATA` handle via pool; `WM_CLOSE` → `close_requested = true`, return 0 (never `DefWindowProcW`); `WM_SIZE` → update `size`; else `DefWindowProcW` | unresolvable handle → `DefWindowProcW`, never crash |
| `is_open` / `should_close` / `client_size` | state queries via pool resolve | invalid → `false` / `false` / `{0,0}` |
| `destroy_window` | `DestroyWindow` + pool remove → handle stale | invalid/double → `Invalid_Handle` |
| `shutdown` | destroys remaining windows, frees pool | leak check binds here |
