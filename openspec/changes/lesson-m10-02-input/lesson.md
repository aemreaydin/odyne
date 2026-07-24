# Lesson: m10-02/input — Keyboard & mouse input

> **Type:** build · **Module:** m10 Window & input · **Interface:** learner-designed (the `engine:platform` input API — the currency the game loop reads; Win32's message side is fixed by Microsoft)

## Goals

- Grow the m10-01 WndProc ears: keyboard and mouse messages recorded in platform state, served to the frame loop through a portable input API — no `VK_*`, no `WM_*`, no packed `lparam` above the platform layer.
- Understand Win32's input model: scan codes vs **virtual-key codes** vs characters; key-down/up and the repeat flag; system keys and why you must not eat them; mouse coordinates packed in `lparam`; wheel detents; capture and focus.
- Take the design decision m10-01 explicitly deferred: **event queue or polled snapshot** — what the engine's input currency *is*, and what "pressed this frame" means relative to `poll_events`.
- Meet the classic input bugs before they meet you: key repeat masquerading as presses, keys stuck down after Alt+Tab, signed mouse coordinates mangled by unsigned macros.

## Prerequisites

- **m10-01 (win32-window)** — the window, the WndProc, the `GWLP_USERDATA` handle plumbing, and `poll_events`; this lesson extends all four.
- **m03 (containers & handles)** — the boundary discipline; input queries take the same `Window_Handle` or defensibly don't (a design decision below).
- **m01-01 (skeleton)** — layering law: `core:sys/windows` stays confined to `engine/platform`.

## Explanation

### The pump grows ears

m10-01 built the buffer between Win32's push and the engine's poll, and deliberately kept it minimal: two facts (`should_close`, `client_size`), no ordered events — "the queue earns its complexity when keyboard input arrives" was the recorded rationale for deferring. Input has now arrived. The WndProc will see an order of magnitude more messages, and the frame loop needs richer answers than booleans: *is Space down? did it just go down? where is the mouse? how far did the wheel turn?* What the platform records, and in what shape the frame loop reads it, is this lesson's design problem.

### Three currencies of a keystroke

Win32 is emphatic that **a key stroke is not a character** [[WIN32 Keyboard Input]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/keyboard-input). Three layers:

1. **Scan codes** — hardware-specific, per-keyboard; the driver translates them away and you will almost never care.
2. **Virtual-key codes** — device-independent key identities (`VK_LEFT` = 0x25). Delivered in `wparam` of the key messages. Letters and digits map to their ASCII uppercase values — but there is deliberately no `VK_A` constant, because a key is not a character: the A key can produce `a`, `A`, or `á` depending on modifiers and layout [[WIN32 Keyboard Input]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/keyboard-input).
3. **Characters** — produced by `TranslateMessage` (already sitting in your m10-01 pump), which converts key-downs into `WM_CHAR` messages carrying UTF-16 [[WIN32 Keyboard Input]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/keyboard-input). Characters are for *text* — chat boxes, console input. Game actions bind to keys, not characters; a game that binds "jump" to `WM_CHAR` breaks the moment the layout changes.

The messages: pressing a key sends `WM_KEYDOWN` to the **focus window**; releasing sends `WM_KEYUP`. Hold the key and autorepeat sends *multiple* key-downs before the single key-up — distinguishable via `lparam` bit 30, the "previous key state" flag, set to 1 on repeats [[WIN32 Keyboard Input]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/keyboard-input). Your design must decide what a repeat *means* (spoiler: for game input, nothing).

**System keys are borrowed, not owned.** Alt+anything and F10 arrive as `WM_SYSKEYDOWN`/`WM_SYSKEYUP` — key strokes that invoke system commands (Alt+Tab, Alt+F4, menu activation). You may *observe* them, but you must pass them to `DefWindowProcW` afterward or you block the OS from handling its own commands [[WIN32 Keyboard Input]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/keyboard-input) — m10-01's `WM_CLOSE`-from-Alt+F4 path literally depends on this.

### The mouse: packed, signed, and full of gotchas

Mouse messages go to the window **under the cursor** (not the focus window — a routing difference from the keyboard worth internalizing). The set: `WM_MOUSEMOVE`, plus down/up pairs per button — `WM_LBUTTONDOWN`/`UP`, `WM_RBUTTONDOWN`/`UP`, `WM_MBUTTONDOWN`/`UP`, `WM_XBUTTONDOWN`/`UP` for the side buttons [[WIN32 Mouse Clicks]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/mouse-clicks). All of them pack the cursor position into `lparam` — x in the low 16 bits, y in the next 16, in **pixels relative to the client area**, and **signed**: with capture active or multiple monitors, coordinates go negative. That's why the docs forbid `LOWORD`/`HIWORD` here — they treat the halves as unsigned and mangle negatives; use the `GET_X_LPARAM`/`GET_Y_LPARAM` shape, i.e. in Odin: go through `i16` before widening [[WIN32 Mouse Clicks]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/mouse-clicks). `wparam` carries `MK_*` flags — the state of the other buttons plus Shift/Ctrl at message time [[WIN32 Mouse Clicks]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/mouse-clicks).

Three second-order behaviors to design around:

- **Capture.** By default `WM_MOUSEMOVE` stops at the client edge. A drag that leaves the window (aiming, sliders, camera orbit) needs `SetCapture` on button-down and `ReleaseCapture` on button-up — the sanctioned three-step [[WIN32 Mouse Movement]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/mouse-movement). Without it, a button released outside the window never sends you its `WM_?BUTTONUP` — a stuck-button bug twin of the Alt+Tab stuck key.
- **The wheel is different on purpose.** `WM_MOUSEWHEEL` goes to the **focus** window (keyboard-style routing), its `lparam` coordinates are **screen**-relative, not client (the one mouse message where reusing your move-handler math silently lies), and the delta rides the high word of `wparam` in multiples *or divisions* of `WHEEL_DELTA` = 120 — free-spinning wheels send many small deltas, so accumulate until ±120 or scroll fractionally [[WIN32 WM_MOUSEWHEEL]](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-mousewheel).
- **Moves without motion.** A `WM_MOUSEMOVE` can arrive when the cursor didn't move (e.g. a window under the cursor was hidden) — coordinates may repeat between messages [[WIN32 Mouse Movement]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/mouse-movement). Don't infer "the user moved" from message arrival; compare positions.

### Polling vs events — the design centerpiece

Gregory frames the engine-side question: HIDs are either *polled* (read current state every frame) or *event-driven* (the OS tells you when something changed), and a game engine HID system typically converts whichever it gets into whichever the game wants, layering on the derived signals raw devices don't provide — among them **edge detection**: "button just went down" computed by comparing this frame's state against the previous frame's [[GEA §9.5]](https://www.gameenginebook.com/). Win32 hands you events (messages); your frame loop wants to ask questions. Two canonical shapes for the buffer between them:

- **Snapshot polling.** The WndProc writes into a *current* state block (key bits, mouse position, button bits, wheel accumulator). `poll_events` timing defines the frame boundary: the previous snapshot is retired, messages drain into the current one, and every query for the rest of the frame answers from these two blocks — `down(k)` reads current, `pressed(k)` is down-now-and-not-before. This is frame-coherent by construction (a query returns the same answer at frame start and frame end — no mid-frame re-read of live OS state) and it's all the m11 fixed-timestep loop and Breakout need. Windows itself endorses the snapshot idea: `GetKeyState` reports queue-synchronized state — the keyboard as of the messages you've processed, not the physical keyboard right now (`GetAsyncKeyState` is the live one) [[WIN32 Keyboard Input]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/keyboard-input). Handmade Hero's platform layer takes essentially this shape — keyboard messages processed straight in the pump into per-frame input state alongside the polled XInput pads [[HMH day 6]](https://guide.handmadehero.org/code/day006/).
- **An ordered event queue.** The WndProc appends `Input_Event` records (key, edge, position, wheel…) to a bounded queue; the frame loop drains it. Strictly more information: ordering *within* a frame ("W-then-S beats S-then-W"), no lost taps shorter than a frame — wait, taps *can't* be lost by the snapshot either, if you think carefully about what the WndProc records; whether they can is one of this lesson's probe questions. The queue's real payoffs are ordering, text input, and UI consumers; its real costs are an event vocabulary, a drain protocol, and an overflow policy that all have to be designed *now*.

Snapshot answers "what is true this frame"; the queue answers "what happened, in order." Engines commonly need both eventually — the design question is which one *this* engine needs *this* phase, and m10-01's deferral note pointed at the queue. You get to confirm or overturn that with an argument.

> **C++ habit vs DOD approach.** The C++ reflex here is an `InputManager` class with observer registration — `AddKeyListener(this)`, virtual `OnKeyDown` — pushing control flow *into* game objects at message time. The data-oriented shape inverts it: input is **plain data updated at one known point in the frame** (the pump), and everything downstream *reads* it; nothing is called back. No subscription lifetime bugs, no reentrancy, and the whole input state is inspectable in one place — this is Gregory's snapshot-and-derive shape [[GEA §9.5]](https://www.gameenginebook.com/) and exactly how the m11 game loop will want to consume it.

### Two classic bugs, designed away in advance

- **The Alt+Tab stuck key.** The key-up for a key held during focus loss goes to the *other* app: your state says "W is down" forever. Windows tells you the moment to fix it — `WM_KILLFOCUS`, sent immediately before losing keyboard focus [[WIN32 WM_KILLFOCUS]](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-killfocus). Your sketch needs a policy (the industry-standard one: clear all key/button state on focus loss).
- **Repeat is not press.** Hold the jump key: autorepeat delivers a stream of `WM_KEYDOWN`s [[WIN32 Keyboard Input]](https://learn.microsoft.com/en-us/windows/win32/learnwin32/keyboard-input). If "pressed" edges are derived from *messages* rather than from *state comparison*, your character bunny-hops. Either filter bit 30 or make edges fall naturally out of the snapshot comparison — one of these is robust by construction; know which and say why.

### The portable currency

Just as m10-01 banned `HWND` above platform, this lesson bans `VK_*`: the public surface speaks a **platform-defined `Key` enum** (and a `Mouse_Button` enum), with the VK→`Key` translation table living in the `_windows` file next to the other Win32 knowledge. Deciding the enum's coverage (letters, digits, arrows, F-keys, modifiers, space/enter/escape/tab/backspace — enough for Breakout and a debug overlay, not all 256 VKs) is part of the sketch.

> **C++ delta #1 — enumerated arrays.** The natural store for per-key state in C++ is `std::array<bool, KEY_COUNT>` plus casts at every index. Odin has arrays *indexed by an enum type*: `[Key]bool` — length is the enum's cardinality, indexing takes the enum value directly, no cast, no `KEY_COUNT` sentinel to keep in sync [[ODIN §Enumerated array]](https://odin-lang.org/docs/overview/#enumerated-array).
>
> **C++ delta #2 — `bit_set`.** Where C++ reaches for `enum` + `|`/`&` bitmask idiom (and C++20 finally blesses it via `std::to_underlying` gymnastics), Odin has a first-class set type: `bit_set[Mouse_Button]` with `in` membership, union/intersection operators, and a guaranteed bit-vector representation [[ODIN §Bit sets]](https://odin-lang.org/docs/overview/#bit-sets). Candidate representation for button state and modifier state — one machine word, printable, comparable.
>
> (The WndProc rules from m10-01 stand unchanged: `proc "system"`, no context until you establish one, record-and-return — now with more message cases.)

## In the industry

Gregory's game engine HID system is a *derivation layer*: whatever the OS provides, the engine snapshots it and derives what raw devices don't give — edge detection, chords, hold-duration, dead zones for analog sticks, and ultimately **remapping**, so game code binds abstract actions ("jump") rather than physical keys [[GEA §9.5]](https://www.gameenginebook.com/). That action-mapping layer is deliberately *not* this lesson — it belongs to the game layer (Breakout will bind three keys and feel no pain); the platform's job is to deliver clean, portable, frame-coherent device state, which is exactly the seam Gregory draws. Handmade Hero does the platform half on camera — day 6 wires keyboard messages and XInput gamepads into the state the game samples [[HMH day 6]](https://guide.handmadehero.org/code/day006/). And when engines need mouse input *better* than `WM_MOUSEMOVE` — unaccelerated high-resolution deltas for FPS cameras, 1000 Hz mice overflowing the message loop — they register for **raw input**: `RegisterRawInputDevices` + `WM_INPUT` delivers device-level data, with a buffered read path (`GetRawInputBuffer`) precisely for high-frequency mice [[WIN32 Raw Input]](https://learn.microsoft.com/en-us/windows/win32/inputdev/about-raw-input). odyne defers raw input until a 3D camera demands it (m43): for cursor-driven and key-driven play, the legacy messages are not a compromise — they're the correct tool, pre-cooked by the OS (acceleration applied, focus rules enforced).

## Performance notes

Input's steady-state cost is the pump's cost under load — m10-01 measured the *empty* pump at ≈185 ns/frame; now the queue has traffic.

**Measurement task (tutor-run; numbers recorded in `curriculum/JOURNAL.md`):**
1. **Flooded pump** — post N synthetic input messages (`WM_KEYDOWN`/`WM_MOUSEMOVE` mix) to a hidden window, measure `poll_events` drain time; report ns/message and the projected per-frame cost at a realistic worst case (a 1000 Hz mouse ≈ 16 move messages per 60 Hz frame).
2. **Snapshot bookkeeping** — the per-frame fixed cost added to `poll_events` (snapshot retire/copy, wheel reset), measured with zero messages pending, vs m10-01's 185 ns/frame empty-pump baseline; plus `size_of` the input state block in bytes.
3. **Query cost** — `down`/`pressed` ns/query (expect pool-resolve + a load, i.e. ≈the 0.44 ns `should_close` measured in m10-01).
4. **Build cost** — testbed clean `-o:speed` build time + binary size vs m10-01's 480,256 B baseline.

## Exercise

Extend `engine/platform` with keyboard and mouse input: WndProc records, portable API serves, testbed visibly reacts.

**Interface is learner-designed — that's your first task.** Sketch in `design.md` (§Learner sketch):

- **The currency:** the `Key` enum (coverage set — what does Breakout + a debug overlay need?) and `Mouse_Button` enum; where the VK→`Key` translation lives. Hard rule: no `VK_*`, no `WM_*`, no OS type in any public signature.
- **The read model — take the deferred decision:** snapshot polling with edge queries (`down`/`pressed`/`released` — define *pressed* precisely, relative to `poll_events`), an ordered event queue (define the event struct, drain protocol, overflow policy), or a stated combination. m10-01's note leaned queue-ward; you may confirm or overturn it, but argue from what m11's loop and Breakout actually consume.
- **Scope:** input state per-window (routed via the `GWLP_USERDATA` handle like m10-01's state) or global (one keyboard, one mouse, one focused game window — defend against the two-window test if you go global). Note the routing asymmetry: keyboard→focus window, mouse→window under cursor, wheel→focus.
- **Policies, stated explicitly:** repeat key-downs (bit 30) vs `pressed` edges · state on `WM_KILLFOCUS` · wheel representation (accumulated detents? raw 120ths? per-frame reset?) · mouse position type and out-of-client behavior · `SetCapture` on drags: now or when a consumer needs it · `WM_CHAR` text input: in or deferred (recommend: deferred until a text consumer exists — but say so).
- **File split:** grow `window.odin`/`window_windows.odin` or add `input.odin`/`input_windows.odin`; either way the WndProc dispatch is shared — say how.

The tutor critiques against the cited sources and records the agreed surface; then the spec delta and failing tests land against it.

- **Build:** WndProc cases for the key/mouse/wheel/focus messages, VK translation table, snapshot/queue bookkeeping wired into `poll_events`, public queries — all in `engine/platform`, `core:sys/windows` confined as ever.
- **Tested seam:** tests drive a *hidden* window with `PostMessageW` — synthetic `WM_KEYDOWN`/`WM_KEYUP`/`WM_MOUSEMOVE`/button/wheel/`WM_KILLFOCUS` messages posted straight to its queue (deterministic and focus-independent, unlike `SendInput`), then `poll_events`, then assert state and edges. Repeat-bit, stuck-key-on-focus-loss, signed-coordinate, and frame-coherence cases included.
- **Demo checkpoint:** the testbed visibly reacts — window title (or console) shows live mouse position + button state + last key; **Esc requests close** through the same path as ✕. Verified by observation.
- **Constraints:** `odin test` green (single-threaded runner, as m10-01) · leak-clean · `-vet -strict-style` clean · layering law holds.

### Definition of done

- Tests green for `engine/platform` · leak check clean · vet/style clean across the tree
- Demo checkpoint confirmed by observation: live input readout, Esc-to-close
- `platform-input` spec delta written and its scenarios covered by passing tests
- Layering verified: no `VK_*`/`WM_*`/OS type in a public signature; `core:sys/windows` still platform-only
- Measurement recorded in `curriculum/JOURNAL.md` · review passed · ≥2 comprehension probes answered
- Journal **Takeaways + Reflections** in your own words

## Reading list

- **Required:** [WIN32 Keyboard Input](https://learn.microsoft.com/en-us/windows/win32/learnwin32/keyboard-input) — the three currencies, sys-keys, repeat, `GetKeyState`; [WIN32 Mouse Clicks](https://learn.microsoft.com/en-us/windows/win32/learnwin32/mouse-clicks) + [WIN32 Mouse Movement](https://learn.microsoft.com/en-us/windows/win32/learnwin32/mouse-movement) — coordinate packing, `MK_*` flags, capture; [HMH day 6](https://guide.handmadehero.org/code/day006/) — keyboard + gamepad wired into per-frame input state on camera.
- **Recommended:** [GEA ch.9](https://www.gameenginebook.com/) — Human Interface Devices, especially §9.5 Game Engine HID Systems (edge detection, chords, the derivation layer); [WIN32 WM_MOUSEWHEEL](https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-mousewheel) — detents, focus routing, screen coords.
- **Deeper:** [WIN32 Raw Input](https://learn.microsoft.com/en-us/windows/win32/inputdev/about-raw-input) — the `WM_INPUT` path odyne will want for 3D camera mice (m43); [Virtual-Key Codes](https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes) — the full VK table your translation covers a subset of; [ODIN §Enumerated array](https://odin-lang.org/docs/overview/#enumerated-array) + [§Bit sets](https://odin-lang.org/docs/overview/#bit-sets) — the state-block building blocks.
