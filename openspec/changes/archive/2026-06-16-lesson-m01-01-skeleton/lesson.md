# Lesson: m01-01/skeleton — Build, test, and the layered package skeleton

> **Type:** build · **Module:** m01 Tooling & project skeleton · **Interface:** learner-designed (your first; I critique)

## Goals

- Stand up `engine/` as four real Odin packages — `core`, `platform`, `render`, `game` — wired so dependencies point **downward only**, and prove the wiring by booting through the whole stack.
- Own the engine build/test workflow: the `engine` collection, `odin build` for the app, `odin test` per package, `-vet -strict-style` as the always-on gate.
- See that the layering law isn't a convention you police by hand — Odin's compiler rejects an upward import as a `Cyclic importation` error. The architecture is enforced by the toolchain.
- Design your first interface from a blank page (the core build-info seam + each layer's boot surface) and defend the package boundaries in review.

## Prerequisites

- m00-01 (the Odin tour) and m00-02 (warm-up katas) — you have the syntax and the `odin test` loop.
- A working Odin toolchain (`odin version` prints `dev-2025-12-...`).

## Explanation

Until now you wrote one throwaway package under `katas/`. This lesson creates the engine's permanent spine: the directory layout every later lesson lands code into, and the build commands you'll type a thousand times. It is deliberately boring and deliberately structural — the value is in the *shape*, not the volume of code.

### A package is a directory — there are no headers

In Odin, **a package is a directory of `.odin` files that all share the same `package` clause**; one directory holds exactly one package [[ODIN §Packages]](https://odin-lang.org/docs/overview/#packages). There is no `.h`/`.cpp` split, no include guards, no forward-declaration dance, no link order to babysit. You `import` a package by path and call its exported (capitalized-or-not — Odin exports by default within the package's public names) procedures qualified by the package name: `core.version_string()`.

> **C++ habit vs Odin:** stop thinking in translation units and headers. There is no "declare in the header, define in the cpp." A file is just a file in its package; every file in the directory sees every other file's declarations with no ordering or `#include` graph. The unit of compilation and of dependency is the *package* (the directory), not the file.

### Collections give the layers clean names

An import path has a *collection* prefix: `import "core:fmt"` reads `fmt` from the built-in `core` collection [[ODIN §Packages]](https://odin-lang.org/docs/overview/#packages). You define your own with the compiler's `-collection:<name>=<path>` flag (see `odin build -help`), so that:

```
-collection:engine=engine        # on the command line
import "engine:core"             # anywhere in the tree
```

resolves `engine:core` to `engine/core/`. Without a prefix, imports are resolved *relative to the current file* — fine within a package, but the collection is what lets `engine/game/` say `import "engine:render"` without a brittle `../render` path. Every engine build command in this project carries `-collection:engine=engine`. *(Verified against the compiler, dev-2025-12: the collection import builds and runs.)*

### The layering law, and why the compiler enforces it

Shipping engines are stratified: the low-level platform/core layers know nothing about the high-level game layer, and dependencies run strictly downward through the stack [[GEA ch.1]](https://www.gameenginebook.com/). odyne's law is `core → platform → render → game`, drawn so that **arrows (imports) point down**:

```
game      ← top:    gameplay, uses everything below
  ↓ imports
render    ← drawing; uses platform + core
  ↓ imports
platform  ← OS seam: window, input, time; uses core
  ↓ imports
core      ← bottom:  memory, containers, math, logging — depends on nothing in-engine
```

`game` may import `render`, `platform`, `core`; `core` may import *none* of them. Why so strict? Because the bottom layers are the ones you reuse, test in isolation, and eventually run under a second backend (DX12 in phase 5) — a `core` that secretly reached up into `game` could never be any of those things.

Here is the part that makes this real rather than aspirational: **if `core` tries to `import "engine:platform"` while `platform` already imports `core`, the Odin compiler refuses to build it** —

```
Error: Cyclic importation of 'core'
```

*(Verified against the compiler, dev-2025-12.)* The acyclic package graph *is* the layering law. You don't need a linter for the common violation; an upward import that closes a cycle simply won't compile. (Odin permits packages to reference each other only when no cycle results, so two sibling packages at the same layer must not import each other either — keep the graph a strict DAG.)

> **C++ habit vs Odin:** in C++ you'd enforce layering with code review, `#include`-what-you-use tooling, or physical-dependency linters, and circular includes are merely annoying (forward declarations paper over them). In Odin a package cycle is a hard compile error, so the most important architectural invariant in the engine is checked on every build for free.

### What "boot through the stack" means here

To prove the wiring (and to give the demo checkpoint something to show), the app boots top-down: `app/main` calls into `game`, which calls `render`, which calls `platform`, which calls `core`. Each layer reports itself; the app prints a banner. There is no real window or GPU yet — those are m10 and m20. Today every "boot" proc is a near-stub that returns its layer's identity. The point is the *seam*, compiled and exercised, not the behavior behind it.

## In the industry

The layered architecture you're sketching is the standard runtime shape: Jason Gregory diagrams the engine as a stack of layers — platform independence and core systems at the bottom, gameplay at the top — with higher layers built on lower ones and dependencies flowing down, precisely so lower layers stay reusable and independently testable [[GEA ch.1]](https://www.gameenginebook.com/). Large C++ codebases spend real tooling effort (physical-dependency analysis, strict `#include` hygiene, separate build targets per layer) to keep that graph acyclic; you get the same guarantee from `odin build`. The "always-on `-vet -strict-style`" habit mirrors how studios run with warnings-as-errors and a house style enforced in CI — the cheapest bugs are the ones the toolchain refuses to compile.

## Performance notes

This lesson's cost model is about the *build*, not the runtime — establishing the baseline you'll watch grow:

- **Compilation is whole-package.** Odin compiles a package as a unit; touching one file recompiles its package. A clean four-package build plus the `core` library is your floor. Record it now so you can see what adding Vulkan (phase 2) does to it.
- **The skeleton is nearly empty**, so the binary size and build time you measure are essentially fixed overhead — a useful "zero point."

**Measurement task (tutor runs it; numbers land in `curriculum/JOURNAL.md`):**
1. Clean build of the app (`odin build engine/app -collection:engine=engine -out:...`): wall-clock time and binary size, `-o:none` vs `-o:speed`.
2. Incremental rebuild after touching one `core` file (no-op edit): wall-clock time — the clean-vs-incremental delta.
3. `odin test` time per package and the package count compiled.

## Exercise

Build the engine skeleton in `engine/`. **You design the interface** (this is your first from-scratch design — sketch it in `design.md`, I critique, we record the agreed shape before any test exists).

- **Packages:** `engine/core`, `engine/platform`, `engine/render`, `engine/game` — each a directory with its own `package` clause, importable as `engine:core`, etc.
- **Layering:** imports point downward only (`game→render→platform→core`); the build must stay acyclic. No two same-layer packages import each other.
- **App entry:** `engine/app/` with `main`, building to an executable via the `engine` collection. Running it prints a boot banner that walks all four layers (your demo checkpoint).
- **Build helper:** a `build.ps1` (or equivalent) at the repo root recording the canonical build/test/vet commands so they're not folklore.
- **Tested seam:** the `core` package exposes the engine's build/version info; I provide a failing `core:testing` test for it (red before you implement). The rest of the skeleton you build out to make the demo run and the build/vet pass.
- **Constraints:** `-vet -strict-style` clean; no upward or sideways imports; no real platform/GPU code yet (stub the boot procs).

### Definition of done

- `odin test engine/core` green · leak check clean · `odin test` passes for every package that has tests
- `odin build engine/app -collection:engine=engine` produces an exe; running it prints the four-layer banner (demo checkpoint confirmed)
- `-vet -strict-style` clean across the tree; build graph acyclic
- Measurement numbers recorded in `curriculum/JOURNAL.md`
- Review passed (layering law especially) · ≥2 comprehension probes answered · journal entry written (your own words)

## Reading list

- **Required:** [ODIN §Packages](https://odin-lang.org/docs/overview/#packages) — packages-as-directories, the `import` statement, and library collections; and `odin build -help` (skim the `-collection`, `-vet`, `-strict-style`, `-out` entries — these are your daily flags).
- **Recommended:** [GEA ch.1](https://www.gameenginebook.com/) — "Runtime Engine Architecture": the layered stack and why dependencies flow down. The diagram is the thing to internalize.
- **Deeper:** [HMH day 1–2](https://guide.handmadehero.org/) — the same "build the skeleton and the build script before any feature" discipline, on camera in C.
