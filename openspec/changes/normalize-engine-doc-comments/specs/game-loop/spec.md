# game-loop Specification (delta)

## ADDED Requirements

### Requirement: The frame loop lives in the top engine layer
The frame loop SHALL reside in `game`, the topmost engine layer, and SHALL NOT reside in
`core`. The loop pumps the platform, drives the renderer, and calls application code; from
`core` every one of those calls would point upward and violate the layering law. Placing it
in `game` makes each call downward, so the loop requires no dependency inversion, procedure-
pointer indirection, or `rawptr` type erasure to be legal.

The application sits above `game` and supplies its work as callbacks — the same
inverted-control shape SDL and sokol_app use, and the only shape available on platforms
where an application-owned infinite loop is not permitted to exist [SDL], [SOKOL].

#### Scenario: Loop placement respects the layering law
- **WHEN** the frame loop's imports are inspected
- **THEN** every dependency points downward along `core → platform → render → game`, and no upward call into application code is made through a `core`-level indirection

#### Scenario: Application drives by callback
- **WHEN** an application runs the engine-owned loop
- **THEN** it supplies its per-frame work as callbacks rather than owning the iteration itself

### Requirement: The engine-owned loop is a convenience, not the only path
The pacing and timing components SHALL remain usable independently of the engine-owned
loop, so that a tool, an asset cooker, or a test harness can write its own iteration
without depending on `game`.

#### Scenario: Loop assembled by a caller
- **WHEN** a caller drives the pacer and frame clock directly, without the engine-owned loop
- **THEN** those components function fully, having no dependency on the loop
