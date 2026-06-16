# Interface design

> **Interface:** learner-designed — this is your first from-scratch interface. Sketch below; I critique in the next section; we record the agreed shape under "Agreed interface" before any test is written.

## Learner sketch

## Package layout

### engine/core

The core engine layer
Includes, containers, memory, allocators, logging, math
Will depend on nothing this is the bottom layer
Core will have a version proc to show the engine version

### engine/platform

The platform layer
Platform specific code will live here
May depend only on core
Will expose EventManager, InputManager, Time code and windowing

### engine/render

The rendering layer
The graphics layer, later abstracted via RHI - initially Vulkan support
Will depend on core - might depend on platform
Will expose rendering functionality - without exposing Vulkan/DirectX specific code
Will expose `renderScene` type of functions

### engine/game

The gameplay layer
Gameplay, scripting, etc will live here
Will depend on everything else

### examples(testbed)

Testbed will be the examples - the initial will return prints that shows each packages information.

<!-- [you] (task 2.1) Propose the skeleton's interface. You don't need much code — you need
     decisions. Cover at least:

       1. Package layout: confirm engine/core, engine/platform, engine/render, engine/game,
          and the app entry (engine/app or other). One package per directory.

       2. The downward dependency edges you intend (which package imports which). Draw the
          DAG. Remember: arrows point down only; no two same-layer packages import each other.

       3. The `core` build-info seam — the one unit-tested surface. What does core expose so a
          test can assert the engine version/build info? (A constant? A proc returning a
          string or a small struct? Name it.)

       4. Each layer's boot/identity surface: what does platform/render/game expose so the app
          can boot top-down through all four and print a banner? Signatures, roughly.

       5. What the app's main does and what the banner looks like (your demo checkpoint).

     Rough is fine. Ownership/lifetime notes welcome but nothing here allocates yet. -->

## Tutor critique

**The layering is correct — this is the important part and you nailed it.** Every edge points down and the graph is acyclic:

```
examples/testbed (app)
        ↓
      game ───→ render ───→ core
        │         │           ↑
        ├─────────┴───────────┤
        └──→ platform ────────┘
```

`core → nothing`, `platform → core`, `render → core`, `game → {render, platform, core}`, app → `game`. That maps cleanly onto GEA's layered runtime stack — low-level core/platform at the bottom, gameplay on top, dependencies flowing strictly downward so the lower layers stay reusable and independently testable [[GEA ch.1]](https://www.gameenginebook.com/). Four decisions to settle before I write the test:

1. **`render` "might depend on platform" — defer the edge.** Make `render` import `core` only for now. The renderer *will* need a window/surface handle from `platform` in m20, and that's the right time to add the edge — when there's an actual need, not a speculative one. Adding it now buys nothing and the skeleton's banner doesn't require it. (Both directions are legal; I'm recommending the smaller graph. Your call.)

2. **`examples/testbed` as the app entry — accepted, good instinct.** A `testbed` executable separate from the engine packages is exactly how shipping engines lay this out, and it keeps the engine free of a `main`. So `engine/` holds the four library packages, and `examples/testbed/` holds `main`. Build target: `odin build examples/testbed -collection:engine=engine`.

3. **The `core` version seam — let's make it concretely testable.** You said "a version proc." Pinning it down: a `VERSION` constant plus `version :: proc() -> string` that returns it. The constant is the single source of truth; the proc is the seam a `core:testing` test asserts against (`version() == VERSION`). Minimal, and it's the one unit-tested surface this lesson needs.

4. **Who assembles the banner? Let `game` walk the stack.** Rather than the app reaching into all four packages, give `game` a `boot :: proc() -> string` that calls *down* to `render`, `platform`, and `core` and assembles the banner. That makes the demo exercise a real cross-layer call chain (`game → render/platform/core`) — which is the whole point of "boot through the stack" — and keeps `testbed/main` thin. Each of `platform`, `render`, `game` exposes a one-line `info :: proc() -> string` identity string; `game.boot` stitches them together with `core.version()`.

**One Odin-idiom note for the surfaces you named** (`EventManager`, `InputManager`, `renderScene`): Odin's house style is `snake_case` for procedures/variables and `Ada_Case` for types — so when those land in later lessons they'll be `Input_State` / `input_poll`, `render_scene`, an `Event` type, etc., not C++/Java-style `PascalCase` managers. Nothing to build now, but worth setting the habit early since we run `-strict-style`.

## Agreed interface

> **Status:** AGREED (2026-06-16). `render` imports `core` only — the `platform` edge is deferred to m20 (learner confirmed). Nothing here allocates; all "boot" procs are stubs returning identity strings.

**`engine/core`** (imports: none)
```odin
package core

VERSION :: "0.1.0"           // single source of truth for the engine version

// version returns the engine version string (== VERSION). The unit-tested seam.
version :: proc() -> string
```

**`engine/platform`** (imports: `engine:core`)
```odin
package platform

// info returns a one-line identity for the platform layer (stub for now).
info :: proc() -> string
```

**`engine/render`** (imports: `engine:core`)
```odin
package render

// info returns a one-line identity for the render layer (stub for now).
info :: proc() -> string
```

**`engine/game`** (imports: `engine:core`, `engine:platform`, `engine:render`)
```odin
package game

// boot assembles the startup banner by querying each lower layer, demonstrating
// the downward call chain game → render / platform / core. Returns the banner
// (the testbed prints it). Example:
//   "odyne 0.1.0 | platform: stub | render: stub | game: stub"
boot :: proc() -> string
```

**`examples/testbed`** (imports: `engine:game`)
```odin
package testbed

// main boots the engine and prints the banner — the demo checkpoint.
main :: proc()
```

Build: `odin build examples/testbed -collection:engine=engine -out:testbed.exe`
Test: `odin test engine/core` (the `version()` seam, red before you implement).
