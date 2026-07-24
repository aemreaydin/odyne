# Interface design

> **Interface:** learner-designed — rationale: Win32's message side is fixed by Microsoft;
> what's open is everything odyne-side — the input currency (`Key`/`Mouse_Button` enums),
> the read model (snapshot vs event queue: the decision m10-01 explicitly deferred here),
> the scope (per-window vs global), and the policies (repeat, focus loss, wheel, capture).
> This surface outlives the lesson: m11's fixed-timestep loop samples it every frame and
> Breakout (m33) plays through it.

## Learner sketch

<!-- [you] Your proposed engine:platform input API. Rough is fine — this starts the design
     conversation. Address:
       - currency: the Key enum (coverage set) + Mouse_Button enum; where VK→Key translation
         lives. No VK_*/WM_*/OS type in any public signature.
       - read model — TAKE THE DEFERRED DECISION: snapshot polling with edge queries
         (define "pressed" precisely, relative to poll_events), an ordered event queue
         (event struct, drain protocol, overflow policy), or a stated combination.
         Argue from what m11's loop and Breakout actually consume.
       - scope: per-window state (routed via the GWLP_USERDATA handle) or global —
         note keyboard→focus window, mouse→under cursor, wheel→focus; defend your pick
         against the two-window test if global.
       - policies: repeat key-downs (lparam bit 30) vs pressed edges · state on WM_KILLFOCUS ·
         wheel representation + per-frame reset · mouse position type + out-of-client
         behavior · SetCapture now or later · WM_CHAR in or deferred.
       - file split: grow window.odin/window_windows.odin or add input.odin/input_windows.odin;
         the WndProc dispatch is shared either way — say how.
     Signatures in Odin. See lesson.md §Exercise for the full brief. -->

- we will use input_windows.odin -- Input interface could be referenced by window
- Key enum for now will support the letters and the numbers and common keys like space, enter, backspace etc.
  Mouse_button will support the mouse buttons supported in win32 and we will have enum-array maps for these keybinds
  to map the win keys
- Can you find me resources to read about the read model
- GWLP_USERDATA handle for per-window state
- I want more research on policies please

## Tutor critique

The positions you took are sound: OS-specific decode in an `input_windows.odin`, a bounded
`Key` enum instead of exposing VKs, translation via lookup tables, and per-window state riding
the m10-01 `GWLP_USERDATA` handle plumbing. Two of the five design axes (read model, policies)
you've turned into research requests — answered below with newly registered sources
([GLFW](https://www.glfw.org/docs/latest/input_guide.html),
[SDL](https://wiki.libsdl.org/SDL3/SDL_GetKeyboardState) — the two middleware layers every
indie engine either uses or reimplements; both now in the bibliography). Findings first,
worst-first:

**1 — Half a file split.** `input_windows.odin` alone can't hold the API: the portable
currency (`Key`, `Mouse_Button`, the query procs' declarations) must be visible on every OS,
so the split mirrors m10-01 — **`input.odin`** (portable types + surface) and
**`input_windows.odin`** (VK table + message decode). The WndProc dispatch stays where it is:
`window_windows.odin`'s `wndproc` gains `case`s that call package-private procs in
`input_windows.odin` — same package, cross-file calls are free, no new plumbing.

**2 — Your table direction is backwards (probably).** "Enum-array maps … to map the win keys"
reads as `[Key]VK`. The hot path runs the other way: a message arrives carrying a VK in
`wparam`, and you need a `Key` — that's a **VK-indexed** table, `[256]Key` (Odin: a plain
fixed array, windows-side; unknown VKs land on a `.Unknown` zero value, ZII doing the
error handling). The *enumerated* array `[Key]bool` (or a bit array) is the other store —
portable-side per-key state
[[ODIN §Enumerated array]](https://odin-lang.org/docs/overview/#enumerated-array). Two
tables, two directions, two files.

**3 — Coverage misses this curriculum's actual consumers.** Letters + digits + space/enter/
backspace serves typing, but nothing in phase 1–3 types. What consumes input: the demo
checkpoint (**Escape**), Breakout's paddle (**arrows**), the debug overlay's toggles
(**F-keys**, m23-03), and chord observation (**modifiers**). Proposed set: A–Z, 0–9, arrows,
Space/Enter/Escape/Tab/Backspace, Shift/Ctrl/Alt (left/right split — Win32 can distinguish;
merging loses information you can't recover later), F1–F12, plus `.Unknown = 0`.

**4 — Per-window state: accepted, with its consequence named.** Queries take the handle —
`key_down(h, .Space)` — and each window's block accumulates only messages routed to *its*
WndProc. Note the asymmetry you inherit from the OS: keyboard messages follow **focus**,
mouse messages follow the **cursor**, wheel follows **focus**
[[WIN32 Keyboard Input]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/keyboard-input) ·
[[WIN32 Mouse Clicks]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/mouse-clicks) ·
[[WIN32 WM_MOUSEWHEEL]](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-mousewheel).
Per-window storage makes the two-window independence test natural — same shape as m10-01's.

### The read model — your reading, then your position

Short course, three sources, ~30 minutes:

1. **[GEA §9.5]** (Game Engine HID Systems) — the conceptual frame: devices are polled or
   event-driven; the engine snapshots whatever it gets and *derives* the rest, edge detection
   ("just went down") computed by comparing this frame's state to last frame's
   [[GEA §9.5]](https://www.gameenginebook.com/).
2. **[SDL SDL_GetKeyboardState](https://wiki.libsdl.org/SDL3/SDL_GetKeyboardState)** — SDL
   ships **both** models at once: an event queue (key events carrying `down` + `repeat`
   flags [[SDL SDL_KeyboardEvent]](https://wiki.libsdl.org/SDL3/SDL_KeyboardEvent)) *and* a
   snapshot array updated by the pump. Read the caveat on that page carefully — it is Q1
   below, stated in SDL's own words.
3. **[GLFW Input guide](https://www.glfw.org/docs/latest/input_guide.html)** — same dual
   shape (callbacks + `glfwGetKey` cached state), plus *sticky keys*, their patch for the
   same Q1 problem.

The recommendation I'll defend: **snapshot + derived edges now; no queue this lesson.** Every
consumer through Milestone 1 — m11's fixed-timestep loop sampling per tick, Breakout's
held-paddle/pressed-launch/Escape, the overlay's toggles — is a state question. The queue's
unique payoffs (intra-frame ordering, text input) have **no consumer in the curriculum until
a debug console exists**, and adding a queue later is purely additive — nothing in the
snapshot design blocks it. m10-01's "queue in m10-02" note was a forecast, not a contract;
the argument above overturns it, and yes/no-ing that argument is part of your lock. But the
snapshot is *not* the naive design, which brings us to:

**Q1 — the lost tap (answer before anything locks).** The user taps Space: `WM_KEYDOWN` and
`WM_KEYUP` both arrive within one `poll_events` drain. If the WndProc merely sets and clears
`current[key]`, what do `key_down` and `key_pressed` report for the entire next frame? SDL
documents this exact failure for its snapshot ("if a key has been pressed and released before
you process events, the pressed state will never show up"
[[SDL SDL_GetKeyboardState]](https://wiki.libsdl.org/SDL3/SDL_GetKeyboardState)); GLFW's
sticky-keys mode exists to patch it
[[GLFW Input guide]](https://www.glfw.org/docs/latest/input_guide.html). Answer in your own
words, then pick a mechanism that makes the tap observable — the WndProc recording
*transitions* rather than only levels is the shape all three patches share; the exact
representation (sticky down-bit, went-down/went-up bits, transition counter) is your call
and becomes the heart of the spec's frame-coherence scenarios.

### Policies — the research you asked for

- **Repeat.** Autorepeat sends extra `WM_KEYDOWN`s flagged by lparam bit 30
  [[WIN32 Keyboard Input]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/keyboard-input).
  Industry position is unambiguous: GLFW's repeat action is "intended for text input" and
  should not drive gameplay [[GLFW Input guide]](https://www.glfw.org/docs/latest/input_guide.html);
  SDL tags repeats so consumers can skip them
  [[SDL SDL_KeyboardEvent]](https://wiki.libsdl.org/SDL3/SDL_KeyboardEvent). Recommended
  policy: **repeats produce no `pressed` edge** — and note that edge-from-state-comparison
  is immune *by construction* (the key is already down, so no 0→1 transition exists), while
  edge-from-messages must filter bit 30 by hand. One of these is robust; say which your
  mechanism is.
- **Focus loss.** The key-up for a key held across Alt+Tab is delivered to the other app;
  your state says "down" forever. `WM_KILLFOCUS` arrives immediately before focus is lost
  [[WIN32 WM_KILLFOCUS]](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-killfocus)
  — recommended policy: **clear all key and button state there** (a mass "released" event,
  not a silent zeroing, if you want released-edges to fire — decide).
- **Wheel.** Delta rides `wparam`'s high word in multiples *or divisions* of
  `WHEEL_DELTA` = 120 — free-spinning wheels send fractions, so accumulate
  [[WIN32 WM_MOUSEWHEEL]](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-mousewheel).
  Recommended: **`f32` in detent units (raw/120), accumulated across the frame, reset at
  `poll_events`** — GLFW likewise hands out floating scroll offsets
  [[GLFW Input guide]](https://www.glfw.org/docs/latest/input_guide.html). Remember the two
  wheel gotchas from lesson.md: focus routing, screen coords (don't reuse move math).
- **Mouse position.** `[2]i32`, client pixels, **signed** — capture and multi-monitor
  produce legal negatives, which is why the unsigned `LOWORD`/`HIWORD` path corrupts and
  the sanctioned decode goes through the signed 16-bit halves
  [[WIN32 Mouse Clicks]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/mouse-clicks)
  (Odin: widen via `i16`). GLFW offers sub-pixel doubles; odyne needs that fidelity only
  when raw input arrives (m43) — `i32` now.
- **Capture.** `SetCapture` on first button-down / `ReleaseCapture` on last button-up is the
  sanctioned three-step [[WIN32 Mouse Movement]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/mouse-movement)
  and closes the stuck-*button* cousin of the Alt+Tab bug (release outside the window is
  otherwise never delivered). Recommended: **now** — it's one branch in two handlers.
- **`WM_CHAR`.** No text consumer exists in the curriculum yet; `TranslateMessage` already
  runs (m10-01), so the messages flow and are simply unhandled. Recommended: **deferred**,
  one sentence in the spec saying so.

### Proposed interface — confirm or adjust (tests bind to this)

```odin
package platform
// input.odin (portable) + input_windows.odin (VK table, message decode)

Key :: enum u8 {
	Unknown = 0,
	A, B, C, /* … */ Z,
	Num_0, /* … */ Num_9,
	Space, Enter, Escape, Tab, Backspace,
	Left, Right, Up, Down,
	Left_Shift, Right_Shift, Left_Ctrl, Right_Ctrl, Left_Alt, Right_Alt,
	F1, /* … */ F12,
}

Mouse_Button :: enum u8 { Left, Right, Middle, X1, X2 }

// Frame-coherent: all answers fixed at poll_events; invalid handle ⇒ false / {0,0} / 0.
key_down       :: proc(h: Window_Handle, k: Key) -> bool  // held this frame
key_pressed    :: proc(h: Window_Handle, k: Key) -> bool  // went down since last poll (repeats: no)
key_released   :: proc(h: Window_Handle, k: Key) -> bool  // went up since last poll
mouse_down     :: proc(h: Window_Handle, b: Mouse_Button) -> bool
mouse_pressed  :: proc(h: Window_Handle, b: Mouse_Button) -> bool
mouse_released :: proc(h: Window_Handle, b: Mouse_Button) -> bool
mouse_position :: proc(h: Window_Handle) -> [2]i32        // client px, signed
mouse_wheel    :: proc(h: Window_Handle) -> f32           // detents this frame, + away from user
```

Internals sketch (package-private, tests may touch): an `Input_State` embedded in
`Window_State` — per-key/per-button level + transition storage per your Q1 mechanism, wheel
accumulator, cursor position; `[256]Key` VK table in `input_windows.odin`; WndProc cases
`WM_KEYDOWN/UP`, `WM_SYSKEYDOWN/UP` (observe, then **fall through to `DefWindowProcW`** —
eat them and Alt+F4 dies
[[WIN32 Keyboard Input]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/keyboard-input)),
mouse move/buttons/wheel, `WM_KILLFOCUS`. Threading contract unchanged from m10-01
(single-threaded, `-define:ODIN_TEST_THREADS=1`); tests drive hidden windows with
`PostMessageW` (targets the hwnd directly — deterministic, focus-independent).

**To lock, I need from you:**
1. **Q1 answered in your own words** + your chosen transition mechanism.
2. Read-model position: accept snapshot-now/queue-later (overturning m10-01's forecast), or
   argue the queue in — from consumers, not generality.
3. Key enum: yes/no on arrows + L/R-split modifiers + F-keys; any additions.
4. Policy yes/nos: repeat-no-edge · clear-on-`WM_KILLFOCUS` (silent or released-edges?) ·
   wheel `f32` detents reset per poll · capture now · `WM_CHAR` deferred.
5. Naming: `key_down`/`key_pressed`/`key_released` + `mouse_*` as proposed, or your scheme.

## Agreed interface

Locked 2026-07-23 (learner confirmed via the design Q&A). **Q1 resolved with one correction
recorded for the journal:** the learner correctly named the snapshot's blind spot (a
sub-frame tap reads "not pressed") but located the fix in *inter-frame* storage —
"poll_events stores the state between frames." Storage between frames only catches presses
that **span** a poll boundary; the tap is lost *within* one drain (down-then-up writes the
same level slot before anyone samples it). The fix lives at **message time**: the WndProc
records **transitions**, not just levels — the shape shared by SDL's documented caveat
[[SDL SDL_GetKeyboardState]](https://wiki.libsdl.org/SDL3/SDL_GetKeyboardState), GLFW's
sticky keys [[GLFW Input guide]](https://www.glfw.org/docs/latest/input_guide.html), and
HMH's counters [[HMH day 6]](https://guide.handmadehero.org/code/day006/).

**Locked decisions:**
- **Mechanism C — half-transition counts:** per key/button, `{half_transitions: u8,
  ended_down: bool}` — the counter increments on every level *flip* recorded during the
  drain; the level persists across frames; counters (and the wheel accumulator) reset when
  `poll_events` retires the frame. Repeats count nothing *by construction* (no flip — bit 30
  never needs reading). A sub-frame tap leaves `ended_down == false, half_transitions == 2`:
  observable.
- **Read model:** snapshot + derived edges; **no event queue this lesson** (m10-01's
  forecast overturned — no consumer until a text/UI system exists; a queue is additive later).
- **Scope:** per-window state embedded in `Window_State`, queries take `Window_Handle`.
- **Policies:** repeat ⇒ no `pressed` edge · `WM_KILLFOCUS` ⇒ **silent clear** (levels,
  counters, wheel zeroed; no edges fired)
  [[WIN32 WM_KILLFOCUS]](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-killfocus)
  · wheel = `f32` detents (raw/120), accumulated per frame, reset at poll, + away from user
  [[WIN32 WM_MOUSEWHEEL]](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-mousewheel)
  · mouse position `[2]i32` signed client px (decode through `i16`, never `LOWORD`/`HIWORD`)
  [[WIN32 Mouse Clicks]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/mouse-clicks)
  · `SetCapture` on first button-down / `ReleaseCapture` on last button-up
  [[WIN32 Mouse Movement]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/mouse-movement)
  · `WM_CHAR` deferred (no text consumer).
- **Key enum:** A–Z (WASD included), digits, arrows, Space/Enter/Escape/Tab/Backspace,
  L/R-split modifiers, F1–F12, `.Unknown = 0`.
- **Naming:** as proposed (`key_down`/`key_pressed`/`key_released`, `mouse_*`).

**Threading contract:** unchanged from m10-01 — single-threaded, the message-pumping thread;
tests run `-define:ODIN_TEST_THREADS=1`.

`engine/platform/input.odin` (portable types) + `engine/platform/input_windows.odin`
(VK table, message decode, queries; wired via new `case`s in `window_windows.odin`'s wndproc):

```odin
package platform

Key :: enum u8 {
	Unknown = 0,
	A, B, C, D, E, F, G, H, I, J, K, L, M,
	N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
	Num_0, Num_1, Num_2, Num_3, Num_4, Num_5, Num_6, Num_7, Num_8, Num_9,
	Space, Enter, Escape, Tab, Backspace,
	Left, Right, Up, Down,
	Left_Shift, Right_Shift, Left_Ctrl, Right_Ctrl, Left_Alt, Right_Alt,
	F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
}

Mouse_Button :: enum u8 { Left, Right, Middle, X1, X2 }

Button_State :: struct {
	half_transitions: u8, // level flips during the last drain (saturate, don't wrap)
	ended_down:       bool,
}

Input_State :: struct {
	keys:    [Key]Button_State,
	buttons: [Mouse_Button]Button_State,
	cursor:  [2]i32, // client px, signed
	wheel:   f32,    // detents this frame, + away from user
}

// Frame-coherent: all answers fixed at poll_events; invalid handle ⇒ false / {0,0} / 0.
key_down       :: proc(h: Window_Handle, k: Key) -> bool
key_pressed    :: proc(h: Window_Handle, k: Key) -> bool
key_released   :: proc(h: Window_Handle, k: Key) -> bool
mouse_down     :: proc(h: Window_Handle, b: Mouse_Button) -> bool
mouse_pressed  :: proc(h: Window_Handle, b: Mouse_Button) -> bool
mouse_released :: proc(h: Window_Handle, b: Mouse_Button) -> bool
mouse_position :: proc(h: Window_Handle) -> [2]i32
mouse_wheel    :: proc(h: Window_Handle) -> f32
```

**Per-operation contract** (tests enforce; tests are in-package and post synthetic messages
with `PostMessageW` — deterministic, focus-independent):

| Operation | Behavior | Edge |
|---|---|---|
| `poll_events` (extended) | NEW first step — retire the frame for every live window: zero all `half_transitions` and the wheel accumulator (levels persist); then drain as m10-01 | retire cost measured |
| WndProc `WM_KEYDOWN`/`WM_SYSKEYDOWN` | resolve `Key` via the VK-indexed table; `VK_SHIFT`/`VK_CONTROL`/`VK_MENU` resolve L/R from lparam (scancode bits 16–23 / extended bit 24 [[WIN32 WM_KEYDOWN]](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-keydown)); record flip+count if level was up; SYS variants fall through to `DefWindowProcW` **after** recording (eat them and Alt+F4 dies) | unmapped VK (`.Unknown`) ⇒ ignored |
| `WM_KEYUP`/`WM_SYSKEYUP` | symmetric | |
| `WM_MOUSEMOVE` | cursor ← signed unpack (through `i16`) | negatives legal |
| `WM_?BUTTONDOWN`/`UP` | button slot flip+count; `SetCapture` on first down, `ReleaseCapture` on last up | releases outside the client arrive via capture |
| `WM_MOUSEWHEEL` | `wheel += f32(delta)/120` | fractional deltas accumulate |
| `WM_KILLFOCUS` | silent clear: all levels + counters + wheel zeroed, no edges; release capture if held | |
| `key_down`/`mouse_down` | level (`ended_down`) as of the last drain | invalid handle ⇒ `false` |
| `key_pressed`/`key_released` (+ `mouse_*`) | "≥1 up→down (resp. down→up) transition occurred during the last drain" — derived from `{half_transitions, ended_down}`; the derivation is implementation (yours) | invalid ⇒ `false` |
| `mouse_position` / `mouse_wheel` | snapshot reads | invalid ⇒ `{0,0}` / `0` |

### Amendment — locked 2026-07-23 (mid-build design conversation)

1. **Focus is observable: `has_focus :: proc(h: Window_Handle) -> bool`** — level query in
   the `should_close` grammar, updated by `WM_SETFOCUS` and cleared in the `WM_KILLFOCUS`
   handler [[WIN32 WM_KILLFOCUS]](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-killfocus).
   No edge queries — focus changes are rare and coarse; callers compare across frames.
   Consumers: m11 pause-on-unfocus, m32 audio duck, m43 cursor-lock release. Backing state:
   `focused: bool` in `Window_State`. Invalid handle ⇒ `false`.
2. **Cursor survives focus loss** — the silent clear zeroes levels, counters, and wheel but
   **not** the cursor: `mouse_position` keeps reporting last-known rather than a fabricated
   `{0,0}` (with `has_focus` in the surface, the caller can see *why* input went quiet).
3. **Capture stays private; stolen capture reconciled now** — no public capture API: chord
   capture is a correctness mechanism of the button state machine, and `SetCapture` is a
   Win32 mechanism, not a portable concept; the future public knob is a *cursor mode*
   (m43, with raw input) [[GLFW Input guide]](https://www.glfw.org/docs/latest/input_guide.html).
   The OS can reassign capture and says so via `WM_CAPTURECHANGED` — sent to the loser,
   even on self-release, and re-grabbing in response is forbidden
   [[WIN32 WM_CAPTURECHANGED]](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-capturechanged).
   Contract: losing capture ends the chord — button levels+counters clear silently, the
   internal holds-capture flag drops, and a stale button-up arriving later must NOT call
   `ReleaseCapture` (that would strip the new owner).

4. **Window title is settable: `set_window_title :: proc(h: Window_Handle, title: string)`**
   (added 2026-07-24, demo checkpoint) — the title-bar readout needed a portable title
   command; grammar mirrors `set_should_close` (pool resolve, invalid handle ⇒ no-op).
   Win32 side: `utf8_to_wstring` → `SetWindowTextW` — wide, never the ANSI `A` variant
   (Odin strings are UTF-8). Belongs to the platform-window capability, not input.

Amended per-operation rows:

| Operation | Behavior | Edge |
|---|---|---|
| WndProc `WM_SETFOCUS` | `focused = true` | |
| WndProc `WM_KILLFOCUS` (amended) | `focused = false`; silent clear of levels+counters+wheel; **cursor persists**; `ReleaseCapture` if held | |
| WndProc `WM_CAPTURECHANGED` | if losing: chord over — buttons clear silently, holds-capture flag drops; never re-grab, never release | self-release also delivers this message |
| `has_focus` | state query via pool resolve | invalid ⇒ `false` |
